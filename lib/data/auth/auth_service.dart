import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper around FirebaseAuth + GoogleSignIn so the UI layer can call
/// one place for sign-in/sign-out. Throws [AuthFailure] for caller-facing
/// errors so the UI can render a friendly message without inspecting plugin
/// error types.
class AuthService {
  AuthService({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
      : _auth = firebaseAuth ?? FirebaseAuth.instance,
        _google = googleSignIn ?? GoogleSignIn(scopes: const ['email']);

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return cred.user!;
    } on FirebaseAuthException catch (e) {
      // user-not-found → auto-create. Mirrors the HTML's "sign in or create"
      // single-button flow rather than forcing a separate signup screen.
      if (e.code == 'user-not-found') {
        return _createWithEmail(email: email, password: password);
      }
      throw AuthFailure(_friendly(e));
    }
  }

  Future<User> _createWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return cred.user!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  Future<User> signInWithGoogle() async {
    try {
      final account = await _google.signIn();
      if (account == null) {
        throw const AuthFailure('Google sign-in cancelled.');
      }
      final googleAuth = await account.authentication;
      final cred = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
      final result = await _auth.signInWithCredential(cred);
      return result.user!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_friendly(e));
    }
  }

  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }

  String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'That email is already registered. Try signing in.';
      case 'weak-password':
        return 'Password is too weak (6+ chars).';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a minute.';
      default:
        return e.message ?? 'Sign-in failed (${e.code}).';
    }
  }
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
