import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class RecordingService {
  static const String defaultServerUrl = 'http://localhost:3000';

  Future<bool> _probeEndpoint(String baseUrl, String endpointPath) async {
    final path = endpointPath.startsWith('/') ? endpointPath : '/$endpointPath';
    final response = await http
        .get(Uri.parse('$baseUrl$path'))
        .timeout(const Duration(milliseconds: 900));
    return response.statusCode >= 200 && response.statusCode < 400;
  }

  Future<bool> checkEndpointReachable(
    String serverUrl, {
    String endpointPath = '/api/health',
  }) async {
    final base = _normalizeServerUrl(serverUrl);
    if (base == null || base.isEmpty) return false;
    try {
      return await _probeEndpoint(base, endpointPath);
    } catch (_) {
      return false;
    }
  }

  /// Tries to auto-detect server URL on local network.
  /// Returns normalized base URL like http://192.168.1.5:3000 when found.
  /// [tryFirst] - URLs to probe first (e.g. from AppConfig) when phone/PC may be on different subnets.
  Future<String?> autoDetectServerUrl({
    int port = 3000,
    String healthPath = '/api/health',
    List<String>? tryFirst,
  }) async {
    // Probe tryFirst immediately (e.g. AppConfig) - PC may be on different subnet than phone
    if (tryFirst != null) {
      for (final url in tryFirst) {
        final base = _normalizeServerUrl(url);
        if (base != null && base.isNotEmpty) {
          try {
            if (await _probeEndpoint(base, healthPath)) return base;
          } catch (_) {}
        }
      }
    }

    final candidates = <String>{
      'http://10.0.2.2:$port',
      'http://127.0.0.1:$port',
      'http://localhost:$port',
    };

    final selfIps = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          selfIps.add(ip);
          final parts = ip.split('.');
          if (parts.length == 4) {
            final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
            for (var i = 1; i <= 254; i++) {
              final candidateIp = '$prefix.$i';
              if (candidateIp == ip) continue;
              candidates.add('http://$candidateIp:$port');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Auto-detect network interface read failed: $e');
    }

    final candidateList = candidates.toList();
    const chunkSize = 24;

    for (var start = 0; start < candidateList.length; start += chunkSize) {
      final end = (start + chunkSize) > candidateList.length
          ? candidateList.length
          : (start + chunkSize);
      final chunk = candidateList.sublist(start, end);

      final results = await Future.wait(
        chunk.map((base) async {
          try {
            final uri = Uri.parse(base);
            if (selfIps.contains(uri.host)) return null;
            if (await _probeEndpoint(base, healthPath)) return base;
          } catch (_) {}
          return null;
        }),
      );

      for (final found in results) {
        if (found != null) return found;
      }
    }

    return null;
  }

  /// Check if bot server is reachable. Returns true if GET /api/health succeeds.
  Future<bool> checkServerReachable(String serverUrl) async {
    final base = _normalizeServerUrl(serverUrl);
    if (base == null || base.isEmpty) return false;
    try {
      final response = await http
          .get(Uri.parse('$base/api/health'))
          .timeout(const Duration(seconds: 12));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    // Request camera and microphone permissions for Jitsi
    final cameraStatus = await Permission.camera.request();
    final microphoneStatus = await Permission.microphone.request();
    
    // Also request storage permission for recordings (optional)
    await Permission.storage.request();
    
    return cameraStatus.isGranted && microphoneStatus.isGranted;
  }

  Future<String?> downloadRecording({
    required String recordingUrl,
    required String meetingId,
  }) async {
    try {
      // Request permissions
      final hasPermission = await requestPermissions();
      if (!hasPermission) {
        return null;
      }

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${directory.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      // Download file
      final response = await http
          .get(Uri.parse(recordingUrl))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        // Get file extension from URL or default to webm
        final extension = recordingUrl.split('.').last.split('?').first;
        final filePath = '${recordingsDir.path}/recording_$meetingId.$extension';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      }
      return null;
    } catch (e) {
      debugPrint('Error downloading recording: $e');
      return null;
    }
  }

  /// Starts bot recording. Retries once on connection/timeout failure.
  Future<String?> startRecording({
    required String roomName,
    String serverUrl = defaultServerUrl,
    String? meetingId,
    String? backendBaseUrl,
    List<Map<String, String>> participants = const [],
  }) async {
    final base = _normalizeServerUrl(serverUrl);
    if (base == null || base.isEmpty) return null;

    final body = <String, dynamic>{'roomName': roomName};
    if (meetingId != null && meetingId.isNotEmpty) body['meetingId'] = meetingId;
    if (backendBaseUrl != null && backendBaseUrl.trim().isNotEmpty) body['backendBaseUrl'] = backendBaseUrl.trim();
    if (participants.isNotEmpty) body['participants'] = participants;

    Future<String?> attempt() async {
      final response = await http.post(
        Uri.parse('$base/api/start-recording'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    }

    debugPrint('Attempting to start recording: room=$roomName, server=$base');
    Object? lastError;
    const maxAttempts = 3;
    const retryDelay = Duration(seconds: 3);
    for (int i = 0; i < maxAttempts; i++) {
      try {
        final result = await attempt();
        if (result != null) {
          if (i > 0) debugPrint('Recording started on attempt ${i + 1}');
          return result;
        }
      } catch (e) {
        lastError = e;
        debugPrint('Attempt ${i + 1}/$maxAttempts failed: $e');
        if (i < maxAttempts - 1) await Future.delayed(retryDelay);
      }
    }
    if (lastError != null) throw lastError;
    throw Exception('Server did not start recording. Check server at $base');
  }

  static String? _normalizeServerUrl(String url) {
    final s = url.trim();
    if (s.isEmpty) return null;
    try {
      String toParse = s;
      if (!s.startsWith('http://') && !s.startsWith('https://')) {
        toParse = 'http://$s';
      }
      final uri = Uri.parse(toParse);
      if (!uri.scheme.startsWith('http')) return null;
      final port = uri.port;
      final host = uri.host;
      if (host.isEmpty) return null;
      return '${uri.scheme}://$host${port > 0 ? ':$port' : ''}';
    } catch (_) {
      return null;
    }
  }

  /// Stops recording and optionally auto-uploads to backend.
  /// Returns map with recordingUrl, minutes (if bot uploaded), uploaded_to_backend.
  Future<Map<String, dynamic>> stopRecording({
    required String roomName,
    String serverUrl = defaultServerUrl,
    List<Map<String, String>> participants = const [],
    String? backendBaseUrl,
  }) async {
    final base = _normalizeServerUrl(serverUrl);
    if (base == null || base.isEmpty) throw Exception('Invalid server URL');
    try {
      final body = <String, dynamic>{
        'roomName': roomName,
        'autoUpload': true,
        'participants': participants,
      };
      if (backendBaseUrl != null && backendBaseUrl.trim().isNotEmpty) {
        body['backendBaseUrl'] = backendBaseUrl.trim();
      }
      final response = await http.post(
        Uri.parse('$base/api/stop-recording'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      final respBody = response.body;
      final msg = respBody.isEmpty ? 'Server error ${response.statusCode}' : respBody;
      throw Exception(msg);
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      rethrow;
    }
  }

  Future<List<File>> getRecordings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${directory.path}/recordings');
      if (!await recordingsDir.exists()) {
        return [];
      }

      final files = recordingsDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.mp4'))
          .toList();

      return files;
    } catch (e) {
      debugPrint('Error getting recordings: $e');
      return [];
    }
  }

  /// Upload recording to Flask backend for transcription and minutes.
  /// Multipart: audio file + meeting_id + metadata JSON with participants.
  /// Returns the backend response with minutes on success; throws on error.
  Future<Map<String, dynamic>> uploadForMinutes({
    required String recordingPath,
    required String meetingId,
    required List<Map<String, String>> participants,
    required String backendUrl,
  }) async {
    final base = _normalizeServerUrl(backendUrl);
    if (base == null || base.isEmpty) {
      throw Exception('Invalid backend URL');
    }

    final file = File(recordingPath);
    if (!await file.exists()) {
      throw Exception('Recording file not found');
    }

    final uri = Uri.parse('$base/api/generate-minutes');
    final request = http.MultipartRequest('POST', uri);

    request.fields['meeting_id'] = meetingId;
    request.fields['metadata'] = jsonEncode({'participants': participants});

    final fileName = recordingPath.split(RegExp(r'[/\\]')).last;
    request.files.add(await http.MultipartFile.fromPath(
      'audio',
      recordingPath,
      filename: fileName,
    ));

    final streamed = await request.send().timeout(const Duration(minutes: 5));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      final body = response.body;
      final msg = body.isEmpty ? 'Server error ${response.statusCode}' : body;
      throw Exception(msg);
    }

    final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
    final error = jsonData['error'];
    if (error != null) {
      throw Exception(jsonData['message']?.toString() ?? error.toString());
    }

    return jsonData;
  }
}

