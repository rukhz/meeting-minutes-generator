import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'recording_service.dart';

/// Result of starting a meeting (bot recording).
class StartMeetingResult {
  final bool success;
  final String? message;
  final String? error;

  const StartMeetingResult({
    required this.success,
    this.message,
    this.error,
  });
}

/// Result of stopping a meeting; includes recording URL and minutes from Flask backend.
class StopMeetingResult {
  final bool success;
  final String? recordingUrl;
  final Map<String, dynamic>? minutes;
  final bool uploadedToBackend;
  final String? message;
  final String? error;

  const StopMeetingResult({
    required this.success,
    this.recordingUrl,
    this.minutes,
    this.uploadedToBackend = false,
    this.message,
    this.error,
  });
}

/// Service for Flutter ↔ Flask-backed meeting flow.
/// - Start/stop go through the bot server (which uploads to Flask and returns minutes).
/// - Minutes can also be fetched via direct Flask upload (existing recording).
class MeetingApiService {
  MeetingApiService({
    RecordingService? recordingService,
  }) : _recordingService = recordingService ?? RecordingService();

  final RecordingService _recordingService;

  /// Bot server base URL (Node; start/stop recording).
  static String _normalizeUrl(String? url) {
    final s = (url ?? '').trim();
    if (s.isEmpty) return '';
    try {
      final u = Uri.parse(s.startsWith(RegExp(r'https?://')) ? s : 'http://$s');
      if (!u.scheme.startsWith('http') || u.host.isEmpty) return '';
      return '${u.scheme}://${u.host}${u.port > 0 ? ':${u.port}' : ''}';
    } catch (_) {
      return '';
    }
  }

  /// 1. Trigger/start meeting recording via bot server (Flask backend receives upload after stop).
  Future<StartMeetingResult> startMeeting({
    required String roomName,
    required String meetingId,
    String? botServerUrl,
    String? backendBaseUrl,
    String? jitsiServerUrl,
    List<Map<String, String>> participants = const [],
  }) async {
    final base = _normalizeUrl(botServerUrl ?? AppConfig.botServerUrl);
    if (base.isEmpty) {
      return const StartMeetingResult(
        success: false,
        error: 'Invalid bot server URL. Set Server URL (e.g. http://PC_IP:3000).',
      );
    }

    try {
      final result = await _recordingService.startRecording(
        roomName: roomName,
        serverUrl: base,
        meetingId: meetingId,
        backendBaseUrl: backendBaseUrl?.trim().isNotEmpty == true ? backendBaseUrl : null,
        jitsiServerUrl: jitsiServerUrl?.trim().isNotEmpty == true ? jitsiServerUrl : null,
        participants: participants,
      );
      if (result != null && result.isNotEmpty) {
        try {
          final json = jsonDecode(result) as Map<String, dynamic>?;
          final success = json?['success'] == true;
          return StartMeetingResult(
            success: success,
            message: json?['message'] as String?,
            error: success ? null : (json?['error'] as String? ?? 'Unknown error'),
          );
        } catch (_) {
          return const StartMeetingResult(success: true, message: 'Recording started');
        }
      }
      return const StartMeetingResult(
        success: false,
        error: 'Server did not start recording. Check bot server and try again.',
      );
    } catch (e, st) {
      debugPrint('MeetingApiService.startMeeting error: $e $st');
      return StartMeetingResult(
        success: false,
        error: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
      );
    }
  }

  /// 2. Stop meeting via bot server; bot uploads to Flask and returns minutes.
  Future<StopMeetingResult> stopMeeting({
    required String roomName,
    required String meetingId,
    String? botServerUrl,
    String? backendBaseUrl,
    List<Map<String, String>> participants = const [],
  }) async {
    final base = _normalizeUrl(botServerUrl ?? AppConfig.botServerUrl);
    if (base.isEmpty) {
      return const StopMeetingResult(
        success: false,
        error: 'Invalid bot server URL.',
      );
    }

    try {
      final response = await _recordingService.stopRecording(
        roomName: roomName,
        serverUrl: base,
        meetingId: meetingId,
        backendBaseUrl: backendBaseUrl?.trim().isNotEmpty == true ? backendBaseUrl : null,
        participants: participants,
      );

      final success = response['success'] == true;
      final recordingUrl = response['recordingUrl'] as String?;
      final uploadedToBackend = response['uploaded_to_backend'] == true;

      // Minutes: bot returns Flask backend response (success, minutes: {...}, transcription_done, message)
      Map<String, dynamic>? minutes = response['minutes'] as Map<String, dynamic>?;
      if (minutes != null && minutes.isNotEmpty) {
        minutes = Map<String, dynamic>.from(minutes);
        // MeetingMinutesScreen accepts full backend response (with optional nested 'minutes') or flat minutes
        if (!minutes.containsKey('minutes') && minutes.containsKey('transcript')) {
          minutes = {'minutes': minutes, 'transcription_done': minutes['transcription_done'] ?? true};
        }
      }

      return StopMeetingResult(
        success: success,
        recordingUrl: recordingUrl,
        minutes: minutes,
        uploadedToBackend: uploadedToBackend,
        message: response['message'] as String?,
        error: success ? null : (response['error'] as String?),
      );
    } catch (e, st) {
      debugPrint('MeetingApiService.stopMeeting error: $e $st');
      return StopMeetingResult(
        success: false,
        error: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
      );
    }
  }

  /// 3. Fetch/generate meeting minutes from Flask backend (upload existing recording).
  /// Use when user taps "Generate minutes" on a saved recording.
  Future<Map<String, dynamic>> fetchMinutesFromBackend({
    required String recordingPath,
    required String meetingId,
    required String backendUrl,
    List<Map<String, String>> participants = const [],
  }) async {
    return _recordingService.uploadForMinutes(
      recordingPath: recordingPath,
      meetingId: meetingId,
      backendUrl: backendUrl,
      participants: participants,
    );
  }

  /// Check if bot server is reachable (GET /api/health).
  Future<bool> isBotServerReachable(String? botServerUrl) async {
    return _recordingService.checkServerReachable(
      botServerUrl ?? AppConfig.botServerUrl,
    );
  }

  /// Check if Flask minutes backend is reachable (GET /api/health).
  Future<bool> isBackendReachable(String? backendUrl) async {
    return _recordingService.checkEndpointReachable(
      backendUrl ?? AppConfig.minutesBackendUrl,
      endpointPath: '/api/health',
    );
  }
}
