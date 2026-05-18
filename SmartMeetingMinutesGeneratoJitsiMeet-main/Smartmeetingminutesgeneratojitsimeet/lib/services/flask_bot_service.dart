import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service for Flask app.py: /api/bot/join, /api/bot/leave, /api/meeting-minutes
class FlaskBotService {
  static String _normalizeUrl(String? url) {
    final s = (url ?? '').trim();
    if (s.isEmpty) return '';
    try {
      final u = Uri.parse(s.startsWith(RegExp(r'https?://')) ? s : 'http://$s');
      if (!u.scheme.startsWith('http') || u.host.isEmpty) return '';
      final port = u.port > 0 ? u.port : 5000;
      return '${u.scheme}://${u.host}:$port';
    } catch (_) {
      return '';
    }
  }

  /// POST /api/bot/join - start bot, triggers recording
  Future<Map<String, dynamic>> join({
    required String room,
    String? displayName,
    String? flaskUrl,
  }) async {
    final base = _normalizeUrl(flaskUrl);
    if (base.isEmpty) return {'success': false, 'error': 'Invalid Flask URL'};

    try {
      final body = <String, dynamic>{
        'room': room,
        'display_name': displayName ?? 'MeetingBot',
        'audio_muted': true,
        'video_muted': true,
      };
      final r = await http
          .post(
            Uri.parse('$base/api/bot/join'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(r.body) as Map<String, dynamic>? ?? {};
      return Map<String, dynamic>.from(json);
    } catch (e, st) {
      debugPrint('FlaskBotService.join error: $e $st');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// POST /api/bot/leave - stop bot, triggers stop_recording & transcription
  Future<Map<String, dynamic>> leave({String? flaskUrl}) async {
    final base = _normalizeUrl(flaskUrl);
    if (base.isEmpty) return {'success': false, 'error': 'Invalid Flask URL'};

    try {
      final r = await http
          .post(
            Uri.parse('$base/api/bot/leave'),
            headers: {'Content-Type': 'application/json'},
            body: '{}',
          )
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(r.body) as Map<String, dynamic>? ?? {};
      return Map<String, dynamic>.from(json);
    } catch (e, st) {
      debugPrint('FlaskBotService.leave error: $e $st');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// GET /api/bot/status - verify Flask server is reachable
  Future<Map<String, dynamic>> checkStatus({String? flaskUrl}) async {
    final base = _normalizeUrl(flaskUrl);
    if (base.isEmpty) return {'success': false, 'error': 'Invalid Flask URL'};
    try {
      final r = await http.get(Uri.parse('$base/api/bot/status')).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) return {'success': true};
      return {'success': false, 'error': 'Status ${r.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// GET /api/meeting-minutes - fetch minutes (add this route to app.py)
  Future<String?> fetchMinutes({String? flaskUrl}) async {
    final base = _normalizeUrl(flaskUrl);
    if (base.isEmpty) return null;

    try {
      final r = await http
          .get(Uri.parse('$base/api/meeting-minutes'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final json = jsonDecode(r.body) as Map<String, dynamic>?;
        return json?['minutes'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
