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
import 'package:flutter/services.dart';
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

  // Try to initialize Firebase - may fail if GoogleService-Info.plist is missing
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Set background message handler
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
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const AuthGate(),
      ),
    );
  }
}

/// Authentication gate - directs user to appropriate screen
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
    debugPrint('[AuthGate:ch] _setupShareExtensionHandler — registering handler for com.collectio.app/share_extension');
    _shareExtensionChannel.setMethodCallHandler((call) async {
      debugPrint('[AuthGate:ch] method call RECEIVED — method=${call.method} args=${call.arguments}');
      if (call.method == 'shareReceived') {
        final url = call.arguments as String?;
        debugPrint('[AuthGate:ch] shareReceived — url=$url mounted=$mounted');
        if (url != null && url.isNotEmpty && mounted) {
          debugPrint('[AuthGate:ch] shareReceived — clearing native URL and setting pending');
          try {
            await _shareExtensionChannel.invokeMethod('clearSharedUrl');
            debugPrint('[AuthGate:ch] shareReceived — clearSharedUrl OK');
          } catch (e) {
            debugPrint('[AuthGate:ch] shareReceived — clearSharedUrl ERROR: $e');
          }
          setState(() {
            _pendingSharedUrl = url;
            _didHandlePendingShare = false;
          });
          debugPrint('[AuthGate:ch] shareReceived — _pendingSharedUrl set to $url');
        } else {
          debugPrint('[AuthGate:ch] shareReceived — ignored (url null/empty or not mounted)');
        }
      } else {
        debugPrint('[AuthGate:ch] unhandled method: ${call.method}');
      }
    });
    debugPrint('[AuthGate:ch] handler registered');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[AuthGate:lifecycle] didChangeAppLifecycleState — state=$state platform.isIOS=${Platform.isIOS}');
    if (state == AppLifecycleState.resumed && Platform.isIOS) {
      debugPrint('[AuthGate:lifecycle] app RESUMED on iOS — resetting _didHandlePendingShare and triggering _checkIOSShareExtensionData');
      setState(() {
        _didHandlePendingShare = false;
      });
      _checkIOSShareExtensionData();
    }
  }

  void _initShareIntentListeners() {
    debugPrint('[AuthGate:init] _initShareIntentListeners — platform.isIOS=${Platform.isIOS}');
    if (Platform.isIOS) {
      debugPrint('[AuthGate:init] iOS — calling _checkIOSShareExtensionData(retryOnStartup: true)');
      _checkIOSShareExtensionData(retryOnStartup: true);
    }
    
    debugPrint('[AuthGate:init] subscribing to ReceiveSharingIntent.getMediaStream()');
    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      debugPrint('[AuthGate:stream] getMediaStream event — count=${files.length}');
      for (final f in files) {
        debugPrint('[AuthGate:stream] file: type=${f.type} mime=${f.mimeType} message=${f.message} path=${f.path}');
        final combined = '${f.message ?? ''} ${f.path}';
        final url = _extractFirstUrl(combined);
        debugPrint('[AuthGate:stream] combined=\'$combined\' extractedUrl=$url');
        if (url != null) {
          debugPrint('[AuthGate:stream] setting _pendingSharedUrl=$url');
          setState(() {
            _pendingSharedUrl = url;
            _didHandlePendingShare = false;
          });
          return;
        }
      }
      if (files.isNotEmpty) {
        debugPrint('[AuthGate:stream] no URL extracted from any file');
      }
    }, onError: (err) {
      debugPrint('[AuthGate:stream] getMediaStream ERROR: $err');
    });

    debugPrint('[AuthGate:init] calling ReceiveSharingIntent.getInitialMedia()');
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      debugPrint('[AuthGate:initial] getInitialMedia resolved — count=${files.length}');
      for (final f in files) {
        debugPrint('[AuthGate:initial] file: type=${f.type} mime=${f.mimeType} message=${f.message} path=${f.path}');
        final combined = '${f.message ?? ''} ${f.path}';
        final url = _extractFirstUrl(combined);
        debugPrint('[AuthGate:initial] combined=\'$combined\' extractedUrl=$url');
        if (url != null) {
          debugPrint('[AuthGate:initial] setting _pendingSharedUrl=$url');
          setState(() {
            _pendingSharedUrl = url;
            _didHandlePendingShare = false;
          });
          return;
        }
      }
      if (files.isNotEmpty) {
        debugPrint('[AuthGate:initial] no URL extracted from any file');
      }
    }).catchError((err) {
      debugPrint('[AuthGate:initial] getInitialMedia ERROR: $err');
    });
  }
  
  bool _isCheckingShareExtension = false;

  Future<void> _checkIOSShareExtensionData({bool retryOnStartup = false}) async {
    debugPrint('[AuthGate:poll] _checkIOSShareExtensionData — retryOnStartup=$retryOnStartup isAlreadyChecking=$_isCheckingShareExtension');
    if (_isCheckingShareExtension) {
      debugPrint('[AuthGate:poll] already checking — skipping');
      return;
    }
    _isCheckingShareExtension = true;

    final int maxAttempts = retryOnStartup ? 15 : 3;
    final Duration delay = retryOnStartup ? const Duration(milliseconds: 500) : const Duration(milliseconds: 200);
    debugPrint('[AuthGate:poll] maxAttempts=$maxAttempts delay=${delay.inMilliseconds}ms');
    
    if (retryOnStartup) {
      debugPrint('[AuthGate:poll] startup delay 100ms before first attempt');
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    try {
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (!mounted) {
          debugPrint('[AuthGate:poll] attempt $attempt — widget unmounted, stopping');
          break;
        }
        
        debugPrint('[AuthGate:poll] attempt $attempt/$maxAttempts — invoking getSharedUrl');
        try {
          final sharedUrl = await _shareExtensionChannel.invokeMethod<String>('getSharedUrl');
          debugPrint('[AuthGate:poll] attempt $attempt — getSharedUrl returned: $sharedUrl');
          
          if (sharedUrl != null && sharedUrl.isNotEmpty) {
            debugPrint('[AuthGate:poll] attempt $attempt — URL FOUND: $sharedUrl — clearing and setting pending');
            try {
              await _shareExtensionChannel.invokeMethod('clearSharedUrl');
              debugPrint('[AuthGate:poll] attempt $attempt — clearSharedUrl OK');
            } catch (e) {
              debugPrint('[AuthGate:poll] attempt $attempt — clearSharedUrl ERROR: $e');
            }
            
            if (mounted) {
              setState(() {
                _pendingSharedUrl = sharedUrl;
                _didHandlePendingShare = false;
              });
              debugPrint('[AuthGate:poll] attempt $attempt — _pendingSharedUrl set');
            } else {
              debugPrint('[AuthGate:poll] attempt $attempt — unmounted after URL found, cannot setState');
            }
            break;
          } else {
            debugPrint('[AuthGate:poll] attempt $attempt — no URL yet');
          }
        } catch (e) {
          final isMissing = e is MissingPluginException;
          if (!isMissing || attempt > 3) {
            debugPrint('[AuthGate:poll] attempt $attempt — invokeMethod ERROR (MissingPlugin=$isMissing): $e');
          } else {
            debugPrint('[AuthGate:poll] attempt $attempt — MissingPluginException (channel not ready yet)');
          }
        }
        
        if (attempt < maxAttempts - 1) {
          debugPrint('[AuthGate:poll] waiting ${delay.inMilliseconds}ms before attempt ${attempt + 1}');
          await Future.delayed(delay);
        }
      }
      debugPrint('[AuthGate:poll] polling loop complete — _pendingSharedUrl=$_pendingSharedUrl');
    } catch (e) {
      debugPrint('[AuthGate:poll] UNEXPECTED ERROR: $e');
    }
    
    _isCheckingShareExtension = false;
    debugPrint('[AuthGate:poll] _checkIOSShareExtensionData DONE');
  }

  String? _extractFirstUrl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'(https?://\S+)').firstMatch(trimmed);
    if (match == null) return null;
    final raw = match.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.replaceAll(RegExp(r'[)\]\},\.\!\?]+$'), '');
  }

  void _consumeShare() {
    ReceiveSharingIntent.instance.reset();
    setState(() {
      _pendingSharedUrl = null;
      _didHandlePendingShare = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // Firebase not ready - show error/setup screen
        if (!auth.firebaseReady) {
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off, size: 80, color: Colors.orange[400]),
                    const SizedBox(height: 24),
                    const Text(
                      'Firebase Setup Required',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Please add GoogleService-Info.plist to ios/Runner/ in Xcode and rebuild.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () {
                        // Retry initialization
                        auth.retryInit();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Show loading while checking auth state
        if (auth.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Not authenticated - show landing/login
        if (!auth.isAuthenticated) {
          return const LandingScreen();
        }

        // Needs email verification
        if (!auth.isEmailVerified) {
          return const EmailVerificationScreen();
        }

        // Needs username
        if (auth.needsUsername) {
          return const UsernameScreen();
        }

        // Fully authenticated - show home and optionally route share-intent
        debugPrint('[AuthGate:build] auth state — isAuthenticated=${auth.isAuthenticated} isEmailVerified=${auth.isEmailVerified} needsUsername=${auth.needsUsername} userEntity=${auth.userEntity?.userName} pendingUrl=$_pendingSharedUrl didHandle=$_didHandlePendingShare');
        if (_pendingSharedUrl != null && !_didHandlePendingShare) {
          final url = _pendingSharedUrl!;
          final user = auth.userEntity;
          final userName = user?.userName ?? '';
          debugPrint('[AuthGate:build] pending URL detected — url=$url userName=\'$userName\' (empty=${userName.isEmpty})');
          if (userName.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                debugPrint('[AuthGate:nav] postFrameCallback — widget unmounted, cannot navigate');
                return;
              }
              debugPrint('[AuthGate:nav] navigating to ImportLinkScreen — url=$url userId=${auth.userId} userName=$userName');
              setState(() => _didHandlePendingShare = true);
              try {
                Navigator.of(context)
                    .push(
                  MaterialPageRoute(
                    builder: (context) => ImportLinkScreen(
                      sharedUrl: url,
                      userId: auth.userId,
                      userName: userName,
                    ),
                  ),
                )
                    .then((_) {
                      debugPrint('[AuthGate:nav] ImportLinkScreen popped — consuming share');
                      _consumeShare();
                    });
                debugPrint('[AuthGate:nav] Navigator.push called');
              } catch (e) {
                debugPrint('[AuthGate:nav] navigation ERROR: $e');
                _consumeShare();
              }
            });
          } else {
            debugPrint('[AuthGate:build] pending URL but userName is empty — waiting for userEntity to load');
          }
        }

        return const HomeScreen();
      },
    );
  }
}

/// Redesigned Email verification screen
class EmailVerificationScreen extends StatelessWidget {
  const EmailVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A2E), size: 20),
          onPressed: () => auth.signOut(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_read_rounded, 
                  color: AppColors.primaryPurple, 
                  size: 64
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'Verify Your Email',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    color: const Color(0xFF6B7280),
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'We sent a verification link to\n'),
                    TextSpan(
                      text: auth.firebaseUser?.email ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              
              // Action Buttons
              TextButton(
                onPressed: () => auth.resendEmailVerification(),
                child: Text(
                  'Resend Email',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Redesigned Username setup screen
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
      backgroundColor: const Color(0xFFF9F9FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.face_retouching_natural_rounded, 
                    color: AppColors.primaryPurple, 
                    size: 64
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'Almost Ready!',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Choose a unique username to start sharing your collections.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  color: const Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 48),
              
              Text(
                'Username',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. creative_curator',
                  prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Container(
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryPurple, Color(0xFF9D84FF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryPurple.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: auth.isLoading
                      ? null
                      : () async {
                          if (_controller.text.trim().isNotEmpty) {
                            await auth.setUsername(_controller.text.trim());
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: auth.isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(
                          'Continue',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
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
