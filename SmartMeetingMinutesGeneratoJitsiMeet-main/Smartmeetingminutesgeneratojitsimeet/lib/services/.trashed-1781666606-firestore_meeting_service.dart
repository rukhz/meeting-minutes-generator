// Firestore service for meeting metadata, transcripts, minutes.
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreMeetingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Create meeting document under user.
  Future<String?> createMeeting({
    required String uid,
    required String roomName,
    String? title,
    String? backendUrl,
  }) async {
    try {
      final meetingId =
          '${roomName.replaceAll(RegExp(r'[^\w\-]'), '_')}_${DateTime.now().toUtc().millisecondsSinceEpoch}';
      final ref = _db.collection('users').doc(uid).collection('meetings').doc(meetingId);
      await ref.set({
        'room_name': roomName,
        'title': title ?? roomName,
        'status': 'created',
        'created_at': FieldValue.serverTimestamp(),
        'user_id': uid,
        if (backendUrl != null) 'backend_url': backendUrl,
      });
      return meetingId;
    } catch (e) {
      return null;
    }
  }

  /// Update meeting status.
  Future<void> updateStatus(String uid, String meetingId, String status,
      {Map<String, dynamic>? extra}) async {
    final ref = _db.collection('users').doc(uid).collection('meetings').doc(meetingId);
    final data = <String, dynamic>{'status': status, 'updated_at': FieldValue.serverTimestamp()};
    if (extra != null) data.addAll(extra);
    await ref.set(data, SetOptions(merge: true));
  }

  /// Save full minutes from backend response.
  Future<void> saveMinutes(String uid, String meetingId, Map<String, dynamic> minutes) async {
    final ref = _db.collection('users').doc(uid).collection('meetings').doc(meetingId);
    await ref.set({
      'status': 'completed',
      'summary': minutes['summary'],
      'participants': minutes['participants'] ?? [],
      'topics': minutes['topics'] ?? [],
      'decisions': minutes['decisions'] ?? [],
      'action_items': minutes['action_items'] ?? [],
      'transcript': minutes['transcript'] ?? [],
      'clean_transcript': minutes['clean_transcript'] ?? minutes['cleanTranscript'] ?? '',
      'raw_transcript': minutes['raw_transcript'] ?? minutes['rawTranscript'] ?? '',
      'metadata': minutes['metadata'] ?? {},
      'meeting_date': minutes['meeting_date'],
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream meetings for user (realtime).
  Stream<QuerySnapshot<Map<String, dynamic>>> meetingsStream(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('meetings')
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  /// Get single meeting.
  Future<DocumentSnapshot<Map<String, dynamic>>?> getMeeting(String uid, String meetingId) async {
    try {
      return await _db
          .collection('users')
          .doc(uid)
          .collection('meetings')
          .doc(meetingId)
          .get();
    } catch (_) {
      return null;
    }
  }

  /// Search meetings by keyword (client-side filter for simplicity).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> searchMeetings(
    String uid, {
    String? keyword,
    DateTime? fromDate,
    DateTime? toDate,
    String? speaker,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection('users')
        .doc(uid)
        .collection('meetings')
        .orderBy('created_at', descending: true)
        .limit(100);

    final snap = await q.get();
    var list = snap.docs;

    if (keyword != null && keyword.trim().isNotEmpty) {
      final k = keyword.toLowerCase();
      list = list.where((d) {
        final data = d.data();
        final text = '${data['title']} ${data['summary']} ${data['room_name']}'.toLowerCase();
        return text.contains(k);
      }).toList();
    }
    if (fromDate != null) {
      list = list.where((d) {
        final ts = d.data()['created_at'] as Timestamp?;
        return ts != null && ts.toDate().isAfter(fromDate);
      }).toList();
    }
    if (toDate != null) {
      list = list.where((d) {
        final ts = d.data()['created_at'] as Timestamp?;
        return ts != null && ts.toDate().isBefore(toDate);
      }).toList();
    }
    if (speaker != null && speaker.trim().isNotEmpty) {
      final s = speaker.toLowerCase();
      list = list.where((d) {
        final participants = d.data()['participants'] as List<dynamic>? ?? [];
        return participants.any((p) =>
            (p is Map && (p['name'] ?? '').toString().toLowerCase().contains(s)));
      }).toList();
    }
    return list;
  }
}
