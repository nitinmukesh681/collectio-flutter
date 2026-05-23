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
import 'utils/link_title_utils.dart';

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
            child: child ?? const SizedBox.shrink(),
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
  bool _isCheckingAndroidShare = false;
  bool _isOpeningImport = false;
  bool _isImportScreenOpen = false;
  static const _shareExtensionChannel = MethodChannel('com.collectio.app/share_extension');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupShareExtensionHandler();
    // Wait for first frame so Android has non-zero viewport before share handling.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initShareIntentListeners());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (_auth != auth) {
      _auth?.removeListener(_onAuthUpdated);
      _auth = auth;
      _auth!.addListener(_onAuthUpdated);
      _openPendingShareIfReady();
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthUpdated);
    WidgetsBinding.instance.removeObserver(this);
    _mediaSub?.cancel();
    _shareExtensionChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _onAuthUpdated() {
    _openPendingShareIfReady();
  }

  void _setupShareExtensionHandler() {
    _shareExtensionChannel.setMethodCallHandler((call) async {
      if (call.method != 'shareReceived' || !mounted) return;

      if (call.arguments is String) {
        final url = call.arguments as String;
        if (url.isEmpty) return;
        await _clearNativeShare();
        setState(() {
          _pendingSharedUrl = url;
          _pendingSharedTitle = null;
          _didHandlePendingShare = false;
          _isOpeningImport = false;
        });
        _openPendingShareIfReady();
        return;
      }

      if (call.arguments is Map) {
        final payload = Map<Object?, Object?>.from(call.arguments as Map);
        final text = _readShareString(payload['text']) ?? '';
        final subject = _readShareString(payload['subject']);
        if (text.isEmpty) return;
        debugPrint('[Share] native shareReceived text=$text subject=$subject');
        _processSharedContent(text, sharedTitle: subject);
      }
    });
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
      _checkIOSShareExtensionData();
    } else if (Platform.isAndroid && !_didHandlePendingShare) {
      _checkAndroidShareIntent();
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
      _isOpeningImport = false;
    });

    _openPendingShareIfReady();
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

    final maxAttempts = retryOnStartup ? 15 : 5;
    const delay = Duration(milliseconds: 250);

    try {
      if (mounted && _pendingSharedUrl == null) {
        await _processAndroidShareFromExtrasOnly();
      }

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
        _openPendingShareIfReady();
      }
    } catch (e) {
      debugPrint('Error checking Android share intent: $e');
    } finally {
      _isCheckingAndroidShare = false;
    }
  }

  bool _isCheckingShareExtension = false;

  Future<void> _checkIOSShareExtensionData({bool retryOnStartup = false}) async {
    if (_isCheckingShareExtension) return;
    _isCheckingShareExtension = true;

    final int maxAttempts = retryOnStartup ? 10 : 3;
    final Duration delay = const Duration(milliseconds: 200);
    
    try {
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (!mounted) break;
        
        final sharedUrl = await _shareExtensionChannel.invokeMethod<String>('getSharedUrl');
        if (sharedUrl != null && sharedUrl.isNotEmpty) {
          await _clearNativeShare();
          if (mounted) {
            setState(() {
              _pendingSharedUrl = sharedUrl;
              _pendingSharedTitle = null;
              _didHandlePendingShare = false;
              _isOpeningImport = false;
            });
            _openPendingShareIfReady();
          }
          break;
        }
        
        if (attempt < maxAttempts - 1) {
          await Future.delayed(delay);
        }
      }
    } catch (e) {
      debugPrint('Error checking share extension data: $e');
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

  void _openPendingShareIfReady() {
    if (!mounted ||
        _pendingSharedUrl == null ||
        _didHandlePendingShare ||
        _isOpeningImport) {
      return;
    }

    final auth = _auth;
    if (auth == null || !auth.firebaseReady) {
      return;
    }
    if (auth.isLoading) {
      debugPrint('[Share] waiting — auth isLoading');
      return;
    }
    if (!auth.isAuthenticated) {
      debugPrint('[Share] waiting — not authenticated');
      return;
    }
    if (!auth.isEmailVerified) {
      debugPrint('[Share] blocked — email not verified');
      return;
    }
    if (auth.needsUsername) {
      debugPrint('[Share] blocked — username required');
      return;
    }

    final userName = auth.userEntity?.userName ??
        auth.firebaseUser?.displayName ??
        auth.firebaseUser?.email?.split('@').first ??
        '';
    if (userName.isEmpty) {
      debugPrint('[Share] waiting — user profile not loaded yet');
      return;
    }

    _isOpeningImport = true;
    final url = _pendingSharedUrl!;
    final title = _pendingSharedTitle;

    _pushImportScreenWhenViewportReady(
      url: url,
      title: title,
      userId: auth.userId,
      userName: userName,
    );
  }

  void _pushImportScreenWhenViewportReady({
    required String url,
    required String? title,
    required String userId,
    required String userName,
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isOpeningImport = false;
        return;
      }

      final navigator = CollectioApp.navigatorKey.currentState;
      if (navigator == null) {
        if (attempt < 40) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (mounted) {
            _pushImportScreenWhenViewportReady(
              url: url,
              title: title,
              userId: userId,
              userName: userName,
              attempt: attempt + 1,
            );
          }
        } else {
          debugPrint('[Share] aborted — root navigator not ready');
          _isOpeningImport = false;
        }
        return;
      }

      debugPrint('[Share] opening ImportLinkScreen for $url (attempt $attempt)');
      if (Platform.isAndroid) {
        ReceiveSharingIntent.instance.reset();
      }

      setState(() => _isImportScreenOpen = true);

      navigator
          .push(
            MaterialPageRoute(
              builder: (context) => ImportLinkScreen(
                sharedUrl: url,
                sharedTitle: title,
                userId: userId,
                userName: userName,
              ),
            ),
          )
          .then((_) => _consumeShare())
          .catchError((Object e) {
            debugPrint('[Share] navigation error: $e');
            if (mounted) {
              setState(() {
                _didHandlePendingShare = false;
                _isOpeningImport = false;
                _isImportScreenOpen = false;
              });
            }
          })
          .whenComplete(() {
            if (mounted) {
              setState(() {
                _isOpeningImport = false;
                _isImportScreenOpen = false;
              });
            }
          });
    });
  }

  void _consumeShare() {
    ReceiveSharingIntent.instance.reset();
    _clearNativeShare();
    setState(() {
      _pendingSharedUrl = null;
      _pendingSharedTitle = null;
      _didHandlePendingShare = true;
    });
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

        if (auth.isLoading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!auth.isAuthenticated) return const LandingScreen();
        if (!auth.isEmailVerified) return const EmailVerificationScreen();
        if (auth.needsUsername) return const UsernameScreen();

        return _buildWithShareOverlay(const HomeScreen());
      },
    );
  }

  Widget _buildWithShareOverlay(Widget child) {
    final showShareWait = _pendingSharedUrl != null &&
        !_didHandlePendingShare &&
        !_isImportScreenOpen;

    if (!showShareWait) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        ColoredBox(
          color: Colors.white.withValues(alpha: 0.92),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Opening shared link…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ],
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
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Choose Username', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Username')),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => auth.setUsername(_controller.text.trim()),
                child: const Text('Continue'),
              ),
            ),
          ],
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
