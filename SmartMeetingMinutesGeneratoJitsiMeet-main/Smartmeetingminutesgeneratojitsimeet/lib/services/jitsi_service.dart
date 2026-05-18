import 'package:flutter/foundation.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

/// Participant info for name mapping in meeting minutes.
class JitsiParticipant {
  final String id;
  final String name;

  JitsiParticipant({required this.id, required this.name});

  Map<String, String> toJson() => {'id': id, 'name': name};
}

class JitsiService {
  final JitsiMeet jitsiMeet = JitsiMeet();
  final uuid = const Uuid();

  final List<JitsiParticipant> _participants = [];

  /// Clear participant list (call before joining so we capture only this meeting).
  void clearParticipants() {
    _participants.clear();
  }

  /// Get participant list captured during the last in-app meeting.
  /// Empty if meeting was joined via browser or no participants were reported.
  List<JitsiParticipant> getParticipants() {
    return List.unmodifiable(_participants);
  }

  Future<void> joinMeeting({
    required String roomName,
    String? serverUrl,
    String? userDisplayName,
    bool audioMuted = false,
    bool videoMuted = false,
    bool useBrowser = false,
    bool useJitsiApp = false, // Open native Jitsi Meet app if installed
  }) async {
    final baseUrl = serverUrl ?? 'https://meet.jit.si';
    final meetingUrl = '$baseUrl/$roomName';

    // Open in Jitsi Meet native app (meet.jit.si only - app handles that domain)
    if (useJitsiApp && (baseUrl.contains('meet.jit.si') || baseUrl.contains('jit.si'))) {
      try {
        // Android: intent URL to open Jitsi Meet app directly; fallback opens in browser
        const pkg = 'org.jitsi.meet';
        final fallback = Uri.encodeComponent(meetingUrl);
        final intentUrl = 'intent://meet.jit.si/$roomName#Intent;scheme=https;package=$pkg;S.browser_fallback_url=$fallback;end';
        final launched = await launchUrl(Uri.parse(intentUrl), mode: LaunchMode.externalApplication);
        if (launched) return;
      } catch (e) {
        debugPrint('Jitsi app launch failed, falling back: $e');
      }
      // Fallback: external app (browser or Jitsi if user selects it)
      try {
        await launchUrl(Uri.parse(meetingUrl), mode: LaunchMode.externalApplication);
      } catch (e2) {
        throw Exception('Could not open meeting. Install Jitsi Meet app or turn off "Open in Jitsi app". Error: $e2');
      }
      return;
    }

    if (useBrowser) {
      final uri = Uri.parse(meetingUrl);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Error launching URL: $e');
        try {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        } catch (e2) {
          throw Exception('Could not launch meeting URL. Please check if a browser is installed. Error: $e2');
        }
      }
      return;
    }

    // In-app: capture participant names for minutes
    clearParticipants();
    final listener = JitsiMeetEventListener(
      conferenceJoined: (_) {},
      conferenceTerminated: (_, __) {},
      participantJoined: (email, name, role, participantId) {
        if (participantId != null && participantId.isNotEmpty) {
          final displayName = (name != null && name.toString().trim().isNotEmpty)
              ? name.toString().trim()
              : 'Participant';
          _participants.add(JitsiParticipant(
            id: participantId,
            name: displayName,
          ));
        }
      },
      participantLeft: (participantId) {
        if (participantId != null) {
          _participants.removeWhere((p) => p.id == participantId);
        }
      },
    );

    var options = JitsiMeetConferenceOptions(
      serverURL: baseUrl,
      room: roomName,
      userInfo: JitsiMeetUserInfo(
        displayName: userDisplayName ?? 'User',
      ),
    );

    await jitsiMeet.join(options, listener);
  }

  String generateRoomName() {
    return uuid.v4().substring(0, 8).replaceAll('-', '');
  }

  // Extract room name from Jitsi Meet URL
  // Supports formats like:
  // - https://meet.jit.si/roomname
  // - https://meet.jit.si/roomname?jwt=...
  // - meet.jit.si/roomname
  String? extractRoomNameFromUrl(String url) {
    try {
      // Remove protocol if present
      String cleanUrl = url.replaceFirst(RegExp(r'^https?://'), '');
      
      // Extract domain and path
      final parts = cleanUrl.split('/');
      if (parts.length >= 2) {
        String roomName = parts[1].split('?').first; // Remove query parameters
        if (roomName.isNotEmpty) {
          return roomName;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error extracting room name from URL: $e');
      return null;
    }
  }

  // Extract server URL from Jitsi Meet URL
  String? extractServerUrlFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
    } catch (e) {
      return null;
    }
  }
}

