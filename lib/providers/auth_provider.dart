import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../models/user_entity.dart';
import '../utils/username_utils.dart';
import '../utils/avatar_display_utils.dart';

/// Authentication state provider
class AuthProvider extends ChangeNotifier {
  AuthService? _authService;
  FirestoreService? _firestoreService;
  NotificationService? _notificationService;
  StreamSubscription<UserEntity?>? _userSubscription;
  StreamSubscription<User?>? _authStateSubscription;

  User? _firebaseUser;
  UserEntity? _userEntity;
  bool _isLoading = false;
  String? _error;
  bool _needsUsername = false;
  bool _firebaseReady = false;
  bool _userProfileLoaded = false;
  bool _initialAuthChecked = false;

  // Getters
  User? get firebaseUser => _firebaseUser;
  UserEntity? get userEntity => _userEntity;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _firebaseReady && _firebaseUser != null;
  bool get isEmailVerified => _firebaseUser?.emailVerified ?? false;
  /// Only enforce username setup after Firestore profile has been checked.
  bool get needsUsername => _userProfileLoaded && _needsUsername;
  bool get userProfileLoaded => _userProfileLoaded;
  String get userId => _firebaseUser?.uid ?? '';
  bool get firebaseReady => _firebaseReady;
  bool get initialAuthChecked => _initialAuthChecked;

  /// Best available display username for denormalized fields (collections, comments).
  String get resolvedUserName {
    final fromEntity = _userEntity?.userName.trim();
    if (fromEntity != null && fromEntity.isNotEmpty) return fromEntity;
    final fromDisplay = _firebaseUser?.displayName?.trim();
    if (fromDisplay != null && fromDisplay.isNotEmpty) return fromDisplay;
    final fromEmail = _firebaseUser?.email?.split('@').first.trim();
    if (fromEmail != null && fromEmail.isNotEmpty) return fromEmail;
    return 'User';
  }

  AuthProvider() {
    _init();
  }

  Future<void> retryInit() async {
    await _authStateSubscription?.cancel();
    _authStateSubscription = null;
    _initialAuthChecked = false;
    await _init();
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
      _notificationService?.initialize().catchError((e) {
        debugPrint('Notification init failed: $e');
      });

      await _restorePersistedSession();

      await _authStateSubscription?.cancel();
      _authStateSubscription = _authService!.authStateChanges.listen(
        (user) => unawaited(_onAuthStateChanged(user)),
      );
    } catch (e) {
      debugPrint('Firebase not available: $e');
      _firebaseReady = false;
      _initialAuthChecked = true;
    }
    notifyListeners();
  }

  /// Waits for Firebase Auth to hydrate the persisted session from device storage.
  Future<void> _restorePersistedSession() async {
    final auth = _authService;
    if (auth == null) return;

    try {
      final user = await _waitForHydratedUser(auth);
      await _onAuthStateChanged(user);
    } catch (e) {
      debugPrint('Persisted session restore failed: $e');
      await _onAuthStateChanged(auth.currentUser);
    } finally {
      _initialAuthChecked = true;
    }
  }

  /// Firebase often emits null before the persisted user on cold start (e.g. share sheet).
  Future<User?> _waitForHydratedUser(AuthService auth) async {
    var user = auth.currentUser;
    if (user != null) return user;

    final completer = Completer<User?>();
    late StreamSubscription<User?> subscription;
    Timer? settleTimer;

    void complete(User? result) {
      if (completer.isCompleted) return;
      settleTimer?.cancel();
      subscription.cancel();
      completer.complete(result);
    }

    settleTimer = Timer(const Duration(milliseconds: 400), () {
      complete(auth.currentUser);
    });

    subscription = auth.authStateChanges.listen((event) {
      if (event != null) {
        complete(event);
      }
    });

    try {
      user = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          complete(auth.currentUser);
          return auth.currentUser;
        },
      );
    } catch (e) {
      complete(auth.currentUser);
      user = auth.currentUser;
    }

    return user;
  }

  Future<void> _onAuthStateChanged(User? user) async {
    final uidChanged = _firebaseUser?.uid != user?.uid;
    _firebaseUser = user;

    if (user != null) {
      if (uidChanged || !_userProfileLoaded) {
        unawaited(_loadUserEntity());
      }
    } else {
      _userSubscription?.cancel();
      _userSubscription = null;
      _userEntity = null;
      _needsUsername = false;
      _userProfileLoaded = false;
    }
    notifyListeners();
  }

  Future<void> _loadUserEntity() async {
    if (_firebaseUser == null || _firestoreService == null) return;
    try {
      debugPrint('Loading user entity for uid: ${_firebaseUser!.uid}');
      var profileTimedOut = false;
      // Initial one-time fetch for immediate state (bounded so cold start cannot hang).
      _userEntity = await _firestoreService!
          .getUser(_firebaseUser!.uid)
          .timeout(const Duration(seconds: 5), onTimeout: () {
        profileTimedOut = true;
        debugPrint('User entity load timed out — continuing offline');
        return null;
      });
      debugPrint('User entity result: ${_userEntity?.userName ?? "null (new user)"}');

      if (_userEntity != null) {
        // Save FCM token
        _notificationService?.saveTokenToUser(_userEntity!.id);
      }

      if (profileTimedOut) {
        _needsUsername = false;
      } else {
        _needsUsername =
            _userEntity == null || (_userEntity!.userName.isEmpty);
      }
      _userProfileLoaded = true;
      notifyListeners();

      // Set up real-time stream for seamless updates across the app
      _userSubscription?.cancel();
      _userSubscription = _firestoreService!.getUserStream(_firebaseUser!.uid).listen(
        (user) {
          if (user != null) {
            _userEntity = user;
            _needsUsername = user.userName.isEmpty;
            notifyListeners();
          }
        },
        onError: (e) {
          debugPrint('User stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('Error loading user entity: $e');
      _userEntity = null;
      // Do not block the app (or share import) when profile fetch fails offline.
      _needsUsername = false;
      _userProfileLoaded = true;
      notifyListeners();
    }
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

  /// Sign up with email and password, optional username
  Future<bool> signUpWithEmail(String email, String password, {String? username}) async {
    if (_authService == null || _firestoreService == null) return false;
    _setLoading(true);
    _error = null;
    try {
      if (username != null && username.trim().isNotEmpty) {
        final normalized = UsernameUtils.normalize(username);
        final available = await _firestoreService!.isUsernameAvailable(
          normalized,
          excludeUserId: '',
        );
        if (!available) {
          _error = 'This username is already taken.';
          _setLoading(false);
          return false;
        }
      }

      final userCredential = await _authService!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (userCredential.user != null && username != null && username.trim().isNotEmpty) {
        final newUser = UserEntity(
          id: userCredential.user!.uid,
          email: email,
          username: UsernameUtils.normalize(username),
        );
        await _firestoreService!.saveUser(newUser);
        _userEntity = newUser;
        _needsUsername = false;
      }

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
    _error = null;
    try {
      final normalized = UsernameUtils.normalize(username);
      final available = await _firestoreService!.isUsernameAvailable(
        normalized,
        excludeUserId: _firebaseUser!.uid,
      );
      if (!available) {
        _error = 'This username is already taken.';
        _setLoading(false);
        notifyListeners();
        return false;
      }

      final user = UserEntity(
        id: _firebaseUser!.uid,
        email: _firebaseUser!.email ?? '',
        username: normalized,
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

  Future<bool> sendPasswordResetForEmailOrUsername(String input) async {
    if (_authService == null || _firestoreService == null) return false;
    _setLoading(true);
    _error = null;
    try {
      String email = input.trim();
      if (!email.contains('@')) {
        final resolvedEmail = await _firestoreService!.getUserEmailByUsername(email);
        if (resolvedEmail == null) {
          throw FirebaseAuthException(code: 'user-not-found', message: 'No user found with this username.');
        }
        email = resolvedEmail;
      }
      await _authService!.sendPasswordResetEmail(email);
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

  /// Update user profile and refresh entity (does not toggle global [isLoading]).
  Future<bool> updateProfile(UserEntity updatedUser) async {
    if (_firestoreService == null) return false;
    _error = null;
    try {
      final previousAvatarUrl = _userEntity?.avatarUrl;
      await _firestoreService!.saveUser(updatedUser);
      await evictAvatarImageCache(
        previousUrl: previousAvatarUrl,
        newUrl: updatedUser.avatarUrl,
        userId: updatedUser.id,
      );
      await _firestoreService!.syncUserAvatarDenormalized(
        userId: updatedUser.id,
        avatarUrl: updatedUser.avatarUrl,
      );
      _userEntity = updatedUser;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Permanently deletes the signed-in user's Firestore data and auth account.
  Future<bool> deleteAccount({String? password, bool reauthenticateWithGoogle = false}) async {
    if (_authService == null || _firestoreService == null || _firebaseUser == null) {
      return false;
    }

    _setLoading(true);
    _error = null;
    final userId = _firebaseUser!.uid;

    try {
      if (reauthenticateWithGoogle) {
        await _authService!.reauthenticateWithGoogle();
      } else if (password != null && password.isNotEmpty) {
        final email = _firebaseUser!.email;
        if (email == null || email.isEmpty) {
          _error = 'Could not verify your identity. Please sign in again.';
          _setLoading(false);
          return false;
        }
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        await _firebaseUser!.reauthenticateWithCredential(credential);
      }

      await _firestoreService!.deleteUserAccount(userId);

      _userSubscription?.cancel();
      _userSubscription = null;

      await _authService!.deleteAccount();

      _userEntity = null;
      _needsUsername = false;
      _firebaseUser = null;
      _userProfileLoaded = false;
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _error = 'For security, please confirm your password to delete your account.';
      } else if (e.code == 'wrong-password') {
        _error = 'Incorrect password.';
      } else {
        _error = _getErrorMessage(e.code);
      }
      _setLoading(false);
      return false;
    } catch (e) {
      debugPrint('deleteAccount error: $e');
      final message = e.toString();
      if (message.contains('permission-denied')) {
        _error =
            'Could not delete your profile. Please sign out, sign back in, and try again.';
      } else {
        _error = 'Could not delete account. Please try again.';
      }
      _setLoading(false);
      return false;
    }
  }

  bool get usesEmailPassword =>
      _firebaseUser?.providerData.any((info) => info.providerId == 'password') ??
      false;

  bool get usesGoogleSignIn =>
      _firebaseUser?.providerData.any((info) => info.providerId == 'google.com') ??
      false;

  /// Sign out
  Future<void> signOut() async {
    _userSubscription?.cancel();
    _userSubscription = null;
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
      case 'username-already-in-use':
        return 'This username is already taken.';
      default:
        return 'An error occurred. Please try again.';
    }
  }
}
