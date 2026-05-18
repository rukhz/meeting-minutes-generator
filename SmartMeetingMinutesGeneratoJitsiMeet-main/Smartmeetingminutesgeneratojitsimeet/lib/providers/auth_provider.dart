// Auth state provider for Firebase Authentication.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/firebase_db_service.dart';

void _authLog(String msg) => debugPrint('[AuthProvider] $msg');

class AuthProvider extends ChangeNotifier {
  AuthService? _auth;

  AuthService? get _authOrNull {
    if (_auth != null) return _auth;
    _authLog('Firebase.apps.isEmpty=${Firebase.apps.isEmpty}');
    if (Firebase.apps.isNotEmpty) {
      try {
        _auth = AuthService();
        _authLog('AuthService created');
        return _auth;
      } catch (e) {
        _authLog('AuthService create failed: $e');
      }
    }
    return null;
  }

  User? get currentUser => _authOrNull?.currentUser;
  String? get uid => _authOrNull?.currentUser?.uid;
  String? get email => _authOrNull?.currentUser?.email;
  bool get isSignedIn => _authOrNull?.currentUser != null;
  String get displayName =>
      _authOrNull?.currentUser?.displayName ??
      _authOrNull?.currentUser?.email?.split('@').first ??
      'User';

  Stream<User?> get authStateChanges =>
      _authOrNull?.authStateChanges ?? Stream<User?>.value(null);

  Future<String?> getIdToken({bool forceRefresh = false}) =>
      _authOrNull?.getIdToken(forceRefresh: forceRefresh) ?? Future.value(null);

  Future<void> signIn(String email, String password) async {
    final a = _authOrNull;
    if (a == null) return;
    await a.signInWithEmail(email: email, password: password);
    notifyListeners();
  }

  Future<void> signUp(String email, String password, {String? name}) async {
    final a = _authOrNull;
    if (a == null) return;
    final cred = await a.registerWithEmail(email: email, password: password, displayName: name);
    if (cred?.user != null) {
      try {
        await FirebaseDbService().saveUserProfile(
          uid: cred!.user!.uid,
          email: email.trim(),
          displayName: name?.trim().isEmpty == true ? null : name?.trim(),
        );
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _authOrNull?.signOut();
    notifyListeners();
  }

  Future<void> sendPasswordReset(String email) async {
    await _authOrNull?.sendPasswordResetEmail(email);
  }
}
