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

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
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
  String? _pendingSharedUrl;
  bool _didHandlePendingShare = false;
  static const _shareExtensionChannel = MethodChannel('com.collectio.app/share_extension');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupShareExtensionHandler();
    _initShareIntentListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mediaSub?.cancel();
    _shareExtensionChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _setupShareExtensionHandler() {
    _shareExtensionChannel.setMethodCallHandler((call) async {
      if (call.method == 'shareReceived') {
        final url = call.arguments as String?;
        if (url != null && url.isNotEmpty && mounted) {
          await _clearNativeShare();
          setState(() {
            _pendingSharedUrl = url;
            _didHandlePendingShare = false;
          });
        }
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
    if (state == AppLifecycleState.resumed && Platform.isIOS) {
      _checkIOSShareExtensionData();
    }
  }

  void _initShareIntentListeners() {
    if (Platform.isIOS) {
      _checkIOSShareExtensionData(retryOnStartup: true);
    }
    
    // Listen for Shared Media/Files (including text in newer versions)
    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> files) {
      _processSharedMedia(files);
    }, onError: (err) => debugPrint('getMediaStream error: $err'));

    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> files) {
      _processSharedMedia(files);
    });
  }

  void _processSharedContent(String text) {
    final url = _extractFirstUrl(text);
    if (url != null && mounted) {
      setState(() {
        _pendingSharedUrl = url;
        _didHandlePendingShare = false;
      });
    }
  }

  void _processSharedMedia(List<SharedMediaFile> files) {
    for (final f in files) {
      final combined = '${f.message ?? ''} ${f.path}';
      final url = _extractFirstUrl(combined);
      if (url != null) {
        _processSharedContent(url);
        break;
      }
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
      debugPrint('Error checking share extension data: $e');
    }
    
    _isCheckingShareExtension = false;
  }

  String? _extractFirstUrl(String text) {
    // Robust URL extraction for strings like "Title - https://example.com"
    final match = RegExp(r'(https?://\S+)').firstMatch(text);
    if (match == null) return null;
    final raw = match.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    // Clean trailing punctuation often included in shared text
    return raw.replaceAll(RegExp(r'[)\]\},\.\!\?]+$'), '');
  }

  void _consumeShare() {
    ReceiveSharingIntent.instance.reset();
    _clearNativeShare();
    setState(() {
      _pendingSharedUrl = null;
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

        if (_pendingSharedUrl != null && !_didHandlePendingShare) {
          final url = _pendingSharedUrl!;
          final userName = auth.userEntity?.userName ?? '';
          if (userName.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _didHandlePendingShare = true);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ImportLinkScreen(
                    sharedUrl: url,
                    userId: auth.userId,
                    userName: userName,
                  ),
                ),
              ).then((_) => _consumeShare());
            });
          }
        }

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
