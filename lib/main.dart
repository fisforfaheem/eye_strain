import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:eye_strain/services/auth_service.dart';
import 'package:eye_strain/screens/wrapper.dart';
import 'package:eye_strain/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';

// just make sure this is working ( sicne we are not using milkit for now, please please do a alternative that checks for the eye strain and shows result and in 3 seonds for demo only for now) Login/Register → Email & Password (Firebase Auth)
// Take a Selfie → Camera captures an image
// Analyze Image → ML Kit detects eye strain signs
// Show Result → "Take a Break" or "Continue Working"
// Save to History → Firestore stores past results
// View History → List of past eye strain checks

// Main entry point of the application
void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase with platform-specific options
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (kDebugMode) {
      print('[Firebase] Initialized successfully');
    }
  } catch (e) {
    if (kDebugMode) {
      print('[Firebase] Initialization error: $e');
    }
    // Handle initialization error gracefully
    runApp(const FirebaseErrorApp());
    return;
  }

  runApp(const EyeGuardApp());
}

/// Fallback app shown when Firebase fails to initialize
class FirebaseErrorApp extends StatelessWidget {
  const FirebaseErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EyeGuard app',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Failed to initialize app',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please check your internet connection and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // Restart app
                    main();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EyeGuardApp extends StatelessWidget {
  const EyeGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthService())],
      child: MaterialApp(
        title: 'EyeGuard',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const Wrapper(),
      ),
    );
  }
}
