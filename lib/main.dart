import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'providers/auth_provider.dart';
import 'theme/app_theme.dart';
import 'screens/landing_screen.dart';
import 'screens/home_screen.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'screens/import_link_screen.dart';

import 'firebase_options.dart';

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
  
  if (kDebugMode && !kIsWeb) {
    HttpOverrides.global = _DevHttpOverrides();
  }

  // Try to initialize Firebase - may fail if GoogleService-Info.plist is missing
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
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

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<List<SharedMediaFile>>? _mediaSub;
  String? _pendingSharedUrl;
  bool _didHandlePendingShare = false;

  @override
  void initState() {
    super.initState();
    _initShareIntentListeners();
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
  }

  void _initShareIntentListeners() {
    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      debugPrint('Share intent media stream received count=${files.length}');
      for (final f in files) {
        debugPrint('Share intent media item type=${f.type} mime=${f.mimeType} message=${f.message} path=${f.path}');
        final url = _extractFirstUrl('${f.message ?? ''} ${f.path}');
        if (url != null) {
          debugPrint('Share intent extracted url=$url');
          setState(() {
            _pendingSharedUrl = url;
            _didHandlePendingShare = false;
          });
          return;
        }
      }
    }, onError: (err) {
      debugPrint('Share intent media stream error: $err');
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      debugPrint('Share intent initial media received count=${files.length}');
      for (final f in files) {
        debugPrint('Share intent initial media item type=${f.type} mime=${f.mimeType} message=${f.message} path=${f.path}');
        final url = _extractFirstUrl('${f.message ?? ''} ${f.path}');
        if (url != null) {
          debugPrint('Share intent initial extracted url=$url');
          setState(() {
            _pendingSharedUrl = url;
            _didHandlePendingShare = false;
          });
          return;
        }
      }
    }).catchError((err) {
      debugPrint('Share intent initial media error: $err');
    });
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
                      style: TextStyle(color: Colors.grey),
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
        if (_pendingSharedUrl != null && !_didHandlePendingShare) {
          final url = _pendingSharedUrl!;
          final user = auth.userEntity;
          final userName = user?.userName ?? '';
          if (userName.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _didHandlePendingShare = true);
              debugPrint('Share intent navigating to ImportLinkScreen url=$url userId=${auth.userId} userName=$userName');
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
                    .then((_) => _consumeShare());
              } catch (e) {
                debugPrint('Share intent navigation ERROR: $e');
                _consumeShare();
              }
            });
          }
        }

        return const HomeScreen();
      },
    );
  }
}

/// Email verification screen placeholder
class EmailVerificationScreen extends StatelessWidget {
  const EmailVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.email_outlined, size: 80, color: Colors.purple),
              const SizedBox(height: 24),
              const Text(
                'Verify Your Email',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'We sent a verification link to ${auth.firebaseUser?.email}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () async {
                  final verified = await auth.checkEmailVerified();
                  if (!verified && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Email not yet verified')),
                    );
                  }
                },
                child: const Text('I\'ve Verified'),
              ),
              TextButton(
                onPressed: () => auth.resendEmailVerification(),
                child: const Text('Resend Email'),
              ),
              TextButton(
                onPressed: () => auth.signOut(),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Username setup screen placeholder
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline, size: 80, color: Colors.purple),
              const SizedBox(height: 24),
              const Text(
                'Choose a Username',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'Enter your username',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: auth.isLoading
                      ? null
                      : () async {
                          if (_controller.text.trim().isNotEmpty) {
                            await auth.setUsername(_controller.text.trim());
                          }
                        },
                  child: auth.isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Continue'),
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
