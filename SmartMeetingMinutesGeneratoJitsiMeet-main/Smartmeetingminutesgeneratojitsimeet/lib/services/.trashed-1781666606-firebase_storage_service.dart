import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Uploads MP4 recordings to Firebase Storage.
/// Path: recordings/{uid}/{meetingId}.mp4
class FirebaseStorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload local MP4 file and return the download URL.
  /// Returns null on failure.
  Future<String?> uploadRecording({
    required String localFilePath,
    required String uid,
    required String meetingId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) return null;

    final file = File(localFilePath);
    if (!await file.exists()) return null;

    final ref = _storage.ref().child('recordings').child(uid).child('$meetingId.mp4');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }
}
