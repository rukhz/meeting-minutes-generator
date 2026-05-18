import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'minutes_extractor.dart';

/// Transcribes audio via OpenAI Whisper API and builds minutes in-app.
/// No Flask backend needed when using this.
class CloudTranscriptionService {
  static const String whisperApiUrl = 'https://api.openai.com/v1/audio/transcriptions';

  /// Transcribe audio file and build minutes. Returns map with 'success', 'minutes', 'error'.
  static Future<Map<String, dynamic>> transcribeAndBuildMinutes({
    required String apiKey,
    required String filePath,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return {'success': false, 'error': 'File not found'};
      }
      final size = await file.length();
      if (size == 0) {
        return {'success': false, 'error': 'Audio file is empty'};
      }

      final uri = Uri.parse(whisperApiUrl);
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.fields['model'] = 'whisper-1';
      final fileName = filePath.replaceAll(r'\', '/').split('/').last;
      request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));

      final streamed = await request.send().timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw Exception('Request timed out'),
      );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        final err = response.body.isNotEmpty ? response.body : 'Status ${response.statusCode}';
        return {'success': false, 'error': 'Transcription failed: $err'};
      }

      final body = response.body;
      String transcriptText;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        transcriptText = (json['text'] as String?)?.trim() ?? '';
      } catch (_) {
        transcriptText = body.trim();
      }
      if (transcriptText.isEmpty) {
        return {
          'success': true,
          'minutes': MinutesExtractor.fromTranscript('No speech detected in recording.'),
        };
      }

      final minutes = MinutesExtractor.fromTranscript(transcriptText);
      return {'success': true, 'minutes': minutes};
    } on http.ClientException catch (e) {
      return {'success': false, 'error': 'Network error: ${e.message}'};
    } on SocketException catch (_) {
      return {'success': false, 'error': 'Cannot reach OpenAI. Check internet and API key.'};
    } catch (e) {
      return {'success': false, 'error': e.toString().replaceFirst(RegExp(r'^Exception: '), '')};
    }
  }

}
