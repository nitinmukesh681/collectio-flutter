import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:io';
import 'providers/auth_provider.dart';
import 'theme/app_theme.dart';
import 'screens/landing_screen.dart';
import 'screens/home_screen.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'screens/import_link_screen.dart';
import 'screens/collection_detail_screen.dart';
import 'utils/link_import_utils.dart';
import 'utils/link_title_utils.dart';
import 'utils/share_intent_controller.dart';
import 'utils/username_utils.dart';
import 'services/username_lowercase_migration.dart';
import 'services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'services/firebase_messaging_background_handler.dart';

class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  
  if (kDebugMode && !kIsWeb) {
    HttpOverrides.global = _DevHttpOverrides();
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  ShareIntentController.install();
  runApp(const CollectioApp());
}

class CollectioApp extends StatelessWidget {
  const CollectioApp({super.key});

  /// Root navigator for share-intent routes (cold start safe).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Collectio',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        themeMode: ThemeMode.light,
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: const TextScaler.linear(0.9),
              platformBrightness: Brightness.light,
            ),
            child: child ??
                const SizedBox.expand(
                  child: ColoredBox(color: AppColors.backgroundSurface),
                ),
          );
        },
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  StreamSubscription<List<SharedMediaFile>>? _mediaSub;
  AuthProvider? _auth;
  String? _pendingSharedUrl;
  String? _pendingSharedTitle;
  bool _didHandlePendingShare = false;
  String? _postImportCollectionId;
  bool _isCheckingAndroidShare = false;
  bool _usernameMigrationStarted = false;
  bool _legacySearchSyncInFlight = false;
  static const _shareExtensionChannel = MethodChannel('com.collectio.app/share_extension');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ShareIntentController.attach(_handleNativeSharePayload);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runUsernameMigrationIfNeeded();
      // Android cold start from share can report zero viewport on first frame.
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _initShareIntentListeners();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (_auth != auth) {
      _auth?.removeListener(_onAuthUpdated);
      _auth = auth;
      _auth!.addListener(_onAuthUpdated);
    }
  }

  @override
  void dispose() {
    ShareIntentController.detach();
    _auth?.removeListener(_onAuthUpdated);
    WidgetsBinding.instance.removeObserver(this);
    _mediaSub?.cancel();
    super.dispose();
  }

  void _handleNativeSharePayload({
    required String? url,
    required String? text,
    required String? subject,
  }) {
    if (!mounted) return;

    if (url != null && _normalizeUrl(url) != null && (text == null || text == url)) {
      setState(() {
        _pendingSharedUrl = _normalizeUrl(url) ?? url;
        _pendingSharedTitle = LinkTitleUtils.resolveItemTitle(
          sharedTitle: subject,
          url: _pendingSharedUrl!,
        );
        _didHandlePendingShare = false;
      });
      return;
    }

    if (text != null && text.isNotEmpty) {
      _processSharedContent(text, sharedTitle: subject);
    }
  }

  void _onAuthUpdated() {
    if (_pendingSharedUrl != null && !_didHandlePendingShare && mounted) {
      setState(() {});
    }
    _runUsernameMigrationIfNeeded();
    _runLegacySearchIndexSyncIfNeeded();
  }

  void _runLegacySearchIndexSyncIfNeeded() {
    final auth = _auth;
    if (auth == null ||
        !auth.isAuthenticated ||
        !auth.firebaseReady ||
        auth.needsUsername ||
        !auth.userProfileLoaded) {
      return;
    }

    final userId = auth.userId;
    if (userId.isEmpty || _legacySearchSyncInFlight) return;

    _legacySearchSyncInFlight = true;
    unawaited(
      FirestoreService()
          .runLegacySearchIndexSyncIfNeeded(userId)
          .catchError((Object e) {
        debugPrint('[SearchIndex] Legacy sync failed: $e');
      })
          .whenComplete(() {
        _legacySearchSyncInFlight = false;
      }),
    );
  }

  void _runUsernameMigrationIfNeeded() {
    if (_usernameMigrationStarted) return;
    final auth = _auth;
    if (auth == null || !auth.isAuthenticated || !auth.firebaseReady) return;

    _usernameMigrationStarted = true;
    try {
      Firebase.app();
    } catch (_) {
      _usernameMigrationStarted = false;
      return;
    }

    unawaited(
      UsernameLowercaseMigration.runIfNeeded(FirebaseFirestore.instance).catchError(
        (Object e, StackTrace st) {
          debugPrint('[Migration] Username lowercase migration failed: $e');
          _usernameMigrationStarted = false;
        },
      ),
    );
  }


  Future<void> _pollAndroidShare() async {
    if (!Platform.isAndroid || !mounted) return;

    await _processAndroidShareFromExtrasOnly();

    try {
      final files = await ReceiveSharingIntent.instance.getInitialMedia();
      if (files.isNotEmpty) {
        await _processSharedMedia(files);
      }
    } catch (e) {
      debugPrint('[Share] Android getInitialMedia failed: $e');
    }

    if (mounted && _pendingSharedUrl != null) {
      setState(() {});
    }
  }

  Future<void> _clearNativeShare() async {
    try {
      await _shareExtensionChannel.invokeMethod('clearSharedUrl');
    } catch (e) {
      debugPrint('Error clearing shared URL: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (Platform.isIOS) {
      unawaited(_pollIOSSharedUrl());
    } else if (Platform.isAndroid) {
      unawaited(_pollAndroidShare());
    }
  }

  void _initShareIntentListeners() {
    if (Platform.isIOS) {
      _checkIOSShareExtensionData(retryOnStartup: true);
    } else if (Platform.isAndroid) {
      _checkAndroidShareIntent(retryOnStartup: true);
    }

    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        unawaited(_processSharedMedia(files));
      },
      onError: (err) => debugPrint('getMediaStream error: $err'),
    );
  }

  void _processSharedContent(String text, {String? sharedTitle}) {
    final url = _extractFirstUrl(text) ?? _normalizeUrl(text);
    if (url == null || !mounted) {
      debugPrint('[Share] could not parse URL from: ${text.isEmpty ? "(empty)" : text}');
      return;
    }

    final title = LinkTitleUtils.resolveItemTitle(
      sharedTitle: sharedTitle,
      shareText: text,
      url: url,
    );
    debugPrint('[Share] parsed URL: $url title: $title');
    setState(() {
      _pendingSharedUrl = url;
      _pendingSharedTitle = title;
      _didHandlePendingShare = false;
    });
  }

  Future<void> _processSharedMedia(List<SharedMediaFile> files) async {
    if (files.isEmpty) {
      if (Platform.isAndroid) {
        await _processAndroidShareFromExtrasOnly();
      }
      return;
    }

    String? url;
    var shareText = '';
    String? subject;

    for (final f in files) {
      final parsed = _urlFromSharedFile(f);
      if (parsed != null) {
        url = parsed;
        subject = f.message;
        shareText = [
          if (f.message != null && f.message!.trim().isNotEmpty) f.message,
          f.path,
        ].join('\n');
        break;
      }
    }

    if (Platform.isAndroid) {
      final extras = await _getAndroidShareExtras();
      subject = extras['subject'] ?? subject;
      final androidText = extras['text'];
      url ??= androidText != null
          ? (_extractFirstUrl(androidText) ?? _normalizeUrl(androidText))
          : null;
      if (androidText != null && androidText.trim().isNotEmpty) {
        shareText = [shareText, androidText]
            .where((part) => part.trim().isNotEmpty)
            .join('\n');
      }
    }

    if (url == null) {
      debugPrint(
        '[Share] received ${files.length} item(s) but no URL could be parsed',
      );
      if (Platform.isAndroid) {
        await _processAndroidShareFromExtrasOnly();
      }
      return;
    }

    _processSharedContent(
      shareText.trim().isNotEmpty ? shareText : url,
      sharedTitle: subject,
    );
  }

  Future<void> _processAndroidShareFromExtrasOnly() async {
    final extras = await _getAndroidShareExtras();
    final text = extras['text'];
    debugPrint(
      '[Share] Android extras fallback — text=${text ?? "(null)"} '
      'subject=${extras['subject'] ?? "(null)"}',
    );
    if (text == null || text.isEmpty) return;
    _processSharedContent(text, sharedTitle: extras['subject']);
  }

  Future<Map<String, String?>> _getAndroidShareExtras() async {
    try {
      final result = await _shareExtensionChannel.invokeMethod<Object?>(
        'getShareExtras',
      );
      if (result is Map) {
        return {
          'subject': _readShareString(result['subject']),
          'text': _readShareString(result['text']),
        };
      }
    } catch (e) {
      debugPrint('Error reading Android share extras: $e');
    }
    return const {};
  }

  String? _readShareString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _urlFromSharedFile(SharedMediaFile file) {
    if (file.type == SharedMediaType.url) {
      return _normalizeUrl(file.path);
    }

    final fromPath = _extractFirstUrl(file.path) ?? _normalizeUrl(file.path);
    if (fromPath != null) return fromPath;

    final combined = '${file.message ?? ''} ${file.path}'.trim();
    return _extractFirstUrl(combined) ?? _normalizeUrl(combined);
  }

  Future<void> _checkAndroidShareIntent({bool retryOnStartup = false}) async {
    if (!Platform.isAndroid || _isCheckingAndroidShare) return;
    _isCheckingAndroidShare = true;

    final maxAttempts = retryOnStartup ? 20 : 8;
    const delay = Duration(milliseconds: 250);

    try {
      await _processAndroidShareFromExtrasOnly();

      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (!mounted) break;
        if (_pendingSharedUrl != null) break;

        final files = await ReceiveSharingIntent.instance.getInitialMedia();
        if (files.isNotEmpty) {
          await _processSharedMedia(files);
          break;
        }
        if (attempt < maxAttempts - 1) {
          await Future.delayed(delay);
        }
      }

      if (mounted && _pendingSharedUrl != null) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('[Share] Error checking Android share intent: $e');
    } finally {
      _isCheckingAndroidShare = false;
    }
  }

  bool _isCheckingShareExtension = false;

  Future<void> _pollIOSSharedUrl() async {
    try {
      final sharedUrl =
          await _shareExtensionChannel.invokeMethod<String>('getSharedUrl');
      if (sharedUrl == null || sharedUrl.isEmpty || !mounted) return;

      debugPrint('[Share] iOS polled shared URL: $sharedUrl');
      setState(() {
        _pendingSharedUrl = sharedUrl;
        _pendingSharedTitle = null;
        _didHandlePendingShare = false;
      });
    } catch (e) {
      debugPrint('[Share] getSharedUrl failed: $e');
    }
  }

  Future<void> _checkIOSShareExtensionData({bool retryOnStartup = false}) async {
    if (_isCheckingShareExtension) return;
    _isCheckingShareExtension = true;

    final int maxAttempts = retryOnStartup ? 10 : 3;
    final Duration delay = const Duration(milliseconds: 200);

    try {
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (!mounted) break;

        final sharedUrl =
            await _shareExtensionChannel.invokeMethod<String>('getSharedUrl');
        if (sharedUrl != null && sharedUrl.isNotEmpty) {
          debugPrint('[Share] iOS startup shared URL: $sharedUrl');
          if (mounted) {
            setState(() {
              _pendingSharedUrl = sharedUrl;
              _pendingSharedTitle = null;
              _didHandlePendingShare = false;
            });
          }
          break;
        }

        if (attempt < maxAttempts - 1) {
          await Future.delayed(delay);
        }
      }
    } catch (e) {
      debugPrint('[Share] Error checking share extension data: $e');
    }

    _isCheckingShareExtension = false;
  }

  String? _extractFirstUrl(String text) {
    final match = RegExp(r'(https?://\S+)', caseSensitive: false).firstMatch(text);
    if (match == null) return null;
    final raw = match.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.replaceAll(RegExp(r'[)\]\},\.\!\?]+$'), '');
  }

  String? _normalizeUrl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final candidate = RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)
        ? trimmed
        : (trimmed.contains(' ') ? null : 'https://$trimmed');

    if (candidate == null) return null;
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri.toString();
  }

  bool _canPresentShareImport(AuthProvider auth) {
    if (!auth.firebaseReady || !auth.initialAuthChecked || auth.isLoading) {
      return false;
    }
    if (!auth.isAuthenticated || !auth.isEmailVerified || auth.needsUsername) {
      return false;
    }
    return true;
  }

  void _completeShareImport([String? collectionId]) {
    if (!mounted) return;
    setState(() {
      _pendingSharedUrl = null;
      _pendingSharedTitle = null;
      _didHandlePendingShare = true;
      _postImportCollectionId = collectionId;
    });
    _clearNativeSharePayload();
  }

  void _clearPostImportCollection() {
    if (!mounted) return;
    setState(() => _postImportCollectionId = null);
  }

  Widget? _buildShareImportScreen(AuthProvider auth) {
    if (_pendingSharedUrl == null || _didHandlePendingShare) return null;
    if (!_canPresentShareImport(auth)) return null;

    final url = _pendingSharedUrl!;
    final collectionId = LinkImportUtils.extractCollectionId(url);
    if (collectionId != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _completeShareImport();
        },
        child: CollectionDetailScreen(
          collectionId: collectionId,
          currentUserId: auth.userId,
        ),
      );
    }

    return ImportLinkScreen(
      sharedUrl: url,
      sharedTitle: _pendingSharedTitle,
      userId: auth.userId,
      userName: auth.resolvedUserName,
      onComplete: _completeShareImport,
    );
  }

  void _clearNativeSharePayload() {
    if (Platform.isAndroid) {
      ReceiveSharingIntent.instance.reset();
    }
    unawaited(_clearNativeShare());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (!auth.firebaseReady) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 80, color: Colors.orange),
                  const SizedBox(height: 24),
                  const Text('Firebase Setup Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Please add configuration files in Xcode/Android Studio.', textAlign: TextAlign.center),
                  ),
                  ElevatedButton(onPressed: auth.retryInit, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }

        if (!auth.initialAuthChecked) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          );
        }

        if (auth.isLoading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!auth.isAuthenticated) return const LandingScreen();
        if (!auth.isEmailVerified) return const EmailVerificationScreen();

        final shareImportScreen = _buildShareImportScreen(auth);
        if (shareImportScreen != null) {
          return shareImportScreen;
        }

        if (_postImportCollectionId != null) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _clearPostImportCollection();
            },
            child: CollectionDetailScreen(
              collectionId: _postImportCollectionId!,
              currentUserId: auth.userId,
            ),
          );
        }

        if (auth.isAuthenticated && !auth.userProfileLoaded) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          );
        }
        if (auth.needsUsername) return const UsernameScreen();

        return const HomeScreen();
      },
    );
  }
}

class EmailVerificationScreen extends StatelessWidget {
  const EmailVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.logout), onPressed: auth.signOut)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mark_email_read, size: 80, color: AppColors.primaryPurple),
            const SizedBox(height: 24),
            const Text('Verify Your Email', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text('Sent to ${auth.firebaseUser?.email}'),
            const SizedBox(height: 24),
            TextButton(onPressed: auth.resendEmailVerification, child: const Text('Resend Email')),
          ],
        ),
      ),
    );
  }
}

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});
  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Choose Username', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              TextFormField(
                controller: _controller,
                autocorrect: false,
                inputFormatters: UsernameUtils.inputFormatters,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: UsernameUtils.validate,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: auth.isLoading
                      ? null
                      : () {
                          if (!_formKey.currentState!.validate()) return;
                          auth.setUsername(UsernameUtils.normalize(_controller.text));
                        },
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
