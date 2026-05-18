import 'package:firebase_database/firebase_database.dart';

/// Saves user profile and meeting minutes/recordings to Firebase Realtime Database.
/// Structure:
///   users/{uid}
///     - email, displayName, createdAt
///   users/{uid}/meetings/{meetingId}
///     - roomName, minutes (JSON), recordingStorageUrl, createdAt
class FirebaseDbService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// Save user profile after registration (credentials: email + displayName only; password stays in Auth).
  Future<void> saveUserProfile({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    await _db.child('users').child(uid).set({
      'email': email,
      'displayName': displayName ?? email.split('@').first,
      'createdAt': ServerValue.timestamp,
    });
  }

  /// Save meeting minutes and recording URL to user's meetings.
  Future<void> saveMeeting({
    required String uid,
    required String meetingId,
    required String roomName,
    required Map<String, dynamic> minutes,
    String? recordingStorageUrl,
    List<Map<String, String>>? participants,
  }) async {
    final meetingsRef = _db.child('users').child(uid).child('meetings');
    await meetingsRef.child(meetingId).set({
      'roomName': roomName,
      'minutes': minutes,
      'recordingStorageUrl': recordingStorageUrl ?? '',
      'participants': participants ?? [],
      'createdAt': ServerValue.timestamp,
    });
  }

  /// Fetch meetings for a user.
  Future<List<Map<String, dynamic>>> getMeetings(String uid) async {
    final snapshot = await _db.child('users').child(uid).child('meetings').get();
    if (!snapshot.exists || snapshot.value == null) return [];
    final map = snapshot.value as Map<dynamic, dynamic>;
    final list = <Map<String, dynamic>>[];
    for (final e in map.entries) {
      final v = e.value as Map<dynamic, dynamic>;
      list.add({
        'meetingId': e.key.toString(),
        ...v.map((k, v) => MapEntry(k.toString(), v)),
      });
    }
    list.sort((a, b) {
      final at = (a['createdAt'] ?? 0) as int;
      final bt = (b['createdAt'] ?? 0) as int;
      return bt.compareTo(at);
    });
    return list;
  }
}
