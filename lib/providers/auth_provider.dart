import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../models/user_entity.dart';

/// Authentication state provider
class AuthProvider extends ChangeNotifier {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  NotificationService? _notificationService;

  User? _firebaseUser;
  UserEntity? _userEntity;
  bool _isLoading = false;
  String? _error;
  bool _needsUsername = false;
  bool _firebaseReady = false;

  // Getters
  User? get firebaseUser => _firebaseUser;
  UserEntity? get userEntity => _userEntity;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _firebaseReady && _firebaseUser != null;
  bool get isEmailVerified => _firebaseUser?.emailVerified ?? false;
  bool get needsUsername => _needsUsername;
  String get userId => _firebaseUser?.uid ?? '';
  bool get firebaseReady => _firebaseReady;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    // Check if Firebase is initialized
    try {
      Firebase.app();
      _firebaseReady = true;
      _authService = AuthService();
      _firestoreService = FirestoreService();
      _notificationService = NotificationService();
      
      // Initialize notifications (request permission)
      _notificationService?.initialize();
      
      _authService!.authStateChanges.listen((user) async {
        _firebaseUser = user;
        if (user != null) {
          await _loadUserEntity();
        } else {
          _userEntity = null;
        }
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Firebase not available: $e');
      _firebaseReady = false;
    }
    notifyListeners();
  }

  Future<void> _loadUserEntity() async {
    if (_firebaseUser == null || _firestoreService == null) return;
    try {
      debugPrint('Loading user entity for uid: ${_firebaseUser!.uid}');
      _userEntity = await _firestoreService!.getUser(_firebaseUser!.uid);
      debugPrint('User entity result: ${_userEntity?.userName ?? "null (new user)"}');
      
      if (_userEntity != null) {
        // Save FCM token
        _notificationService?.saveTokenToUser(_userEntity!.id);
      }
      
      _needsUsername = _userEntity == null || (_userEntity!.userName.isEmpty);
    } catch (e) {
      debugPrint('Error loading user entity: $e');
      // For now, assume user doesn't exist yet - they need to set username
      _userEntity = null;
      _needsUsername = true;
    }
    notifyListeners();
  }

  /// Sign in with email/username and password
  Future<bool> signInWithEmail(String emailOrUsername, String password) async {
    if (_authService == null || _firestoreService == null) return false;
    _setLoading(true);
    _error = null;
    try {
      debugPrint('Attempting sign in with: $emailOrUsername');
      
      String email = emailOrUsername;
      if (!email.contains('@')) {
        // It's a username, try to find the email
        final resolvedEmail = await _firestoreService!.getUserEmailByUsername(emailOrUsername);
        if (resolvedEmail == null) {
          throw FirebaseAuthException(
            code: 'user-not-found', 
            message: 'Username not found.'
          );
        }
        email = resolvedEmail;
        debugPrint('Resolved username $emailOrUsername to email $email');
      }

      await _authService!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint('Sign in successful, loading user entity...');
      await _loadUserEntity();
      debugPrint('User entity loaded');
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} - ${e.message}');
      _error = _getErrorMessage(e.code);
      _setLoading(false);
      return false;
    } catch (e) {
      debugPrint('Sign in error: $e');
      _error = e.toString();
      _setLoading(false);
      return false;
    }
  }

  /// Sign up with email and password
  Future<bool> signUpWithEmail(String email, String password) async {
    if (_authService == null) return false;
    _setLoading(true);
    _error = null;
    try {
      await _authService!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _authService!.sendEmailVerification();
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _getErrorMessage(e.code);
      _setLoading(false);
      return false;
    } catch (e) {
      _error = e.toString();
      _setLoading(false);
      return false;
    }
  }

  /// Sign in with Google
  Future<bool> signInWithGoogle() async {
    if (_authService == null) return false;
    _setLoading(true);
    _error = null;
    try {
      final result = await _authService!.signInWithGoogle();
      if (result == null) {
        _setLoading(false);
        return false;
      }
      await _loadUserEntity();
      _setLoading(false);
      return true;
    } catch (e) {
      _error = e.toString();
      _setLoading(false);
      return false;
    }
  }

  /// Set username for new user
  Future<bool> setUsername(String username) async {
    if (_firebaseUser == null || _firestoreService == null) return false;
    _setLoading(true);
    try {
      final user = UserEntity(
        id: _firebaseUser!.uid,
        email: _firebaseUser!.email ?? '',
        userName: username,
      );
      await _firestoreService!.saveUser(user);
      _userEntity = user;
      _needsUsername = false;
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _setLoading(false);
      return false;
    }
  }

  /// Resend email verification
  Future<void> resendEmailVerification() async {
    await _authService?.sendEmailVerification();
  }

  /// Check email verification status
  Future<bool> checkEmailVerified() async {
    if (_authService == null) return false;
    final verified = await _authService!.isEmailVerified();
    notifyListeners();
    return verified;
  }

  /// Send password reset email
  Future<bool> sendPasswordReset(String email) async {
    if (_authService == null) return false;
    _setLoading(true);
    _error = null;
    try {
      await _authService!.sendPasswordResetEmail(email);
      _setLoading(false);
      return true;
    } catch (e) {
      _error = e.toString();
      _setLoading(false);
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _authService?.signOut();
    _userEntity = null;
    _needsUsername = false;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak.';
      default:
        return 'An error occurred. Please try again.';
    }
  }
}
