import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:eye_strain/services/auth_service.dart';
import 'package:eye_strain/screens/history/history_screen.dart';
import 'package:eye_strain/screens/profile/profile_screen.dart';
import 'package:eye_strain/services/eye_strain_service.dart';

/// HomeScreen is the main screen of the app where users can take photos
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String? _result;
  File? _capturedImage;
  bool _isAnalyzing = false;
  final _eyeStrainService = EyeStrainService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _eyeStrainService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid
              ? ImageFormatGroup.yuv420
              : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();

      // Configure camera
      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint('Focus mode not supported: $e');
      }

      try {
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint('Exposure mode not supported: $e');
      }

      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing camera: $e')),
        );
      }
    }
  }

  // Analyze eye strain using ML Kit
  Future<void> _analyzeEyeStrain() async {
    final authService = context.read<AuthService>();

    setState(() {
      _isAnalyzing = true;
      _result = 'Analyzing your eye strain...';
    });

    final userId = authService.currentUser?.uid;
    if (userId == null || _capturedImage == null) {
      setState(() {
        _result = 'Error: User not logged in or image not captured';
        _isAnalyzing = false;
        _isProcessing = false;
      });
      return;
    }

    try {
      // Use ML Kit to analyze eye strain
      final analysisResult = await _eyeStrainService.analyzeEyeStrainWithMlKit(
        _capturedImage!.path,
      );

      if (!analysisResult['success']) {
        // Handle analysis failure
        setState(() {
          _result = analysisResult['message'];
          _isAnalyzing = false;
          _isProcessing = false;
        });
        return;
      }

      // Verify the user is still logged in before saving to Firestore
      final currentUser = authService.currentUser;
      if (currentUser == null) {
        setState(() {
          _result = 'Error: User session expired. Please log in again.';
          _isAnalyzing = false;
          _isProcessing = false;
        });
        return;
      }

      try {
        // Save the analysis result to history
        await _eyeStrainService.saveEyeCheckFromAnalysis(
          userId: userId,
          imagePath: _capturedImage!.path,
          analysisResult: analysisResult,
        );
      } catch (firestoreError) {
        // Handle Firestore errors but still show the analysis result
        if (kDebugMode) {
          print('Error saving to Firestore: $firestoreError');
        }

        if (mounted) {
          setState(() {
            _result =
                analysisResult['message'] +
                '\n\nNote: Could not save to history. ${firestoreError.toString().contains('permission-denied') ? 'Permission denied.' : ''}';
            _isAnalyzing = false;
            _isProcessing = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _result = analysisResult['message'];
          _isAnalyzing = false;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = 'Error analyzing eye strain: $e';
          _isAnalyzing = false;
          _isProcessing = false;
        });
      }
      debugPrint('Error in eye strain analysis: $e');
    }
  }

  Future<void> _takePicture() async {
    if (!_isCameraInitialized || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final image = await _controller!.takePicture();

      setState(() {
        _capturedImage = File(image.path);
      });

      // Start analysis after capturing image
      await _analyzeEyeStrain();
    } catch (e) {
      setState(() {
        _result = 'Error taking picture: $e';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EyeGuard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Instructions Card
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.remove_red_eye,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Eye Strain Detection',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Take a photo to analyze your eye strain using advanced face detection technology.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Camera Preview
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(51), // 0.2 * 255 = ~51
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child:
                        _isCameraInitialized
                            ? _capturedImage != null
                                ? Transform(
                                  alignment: Alignment.center,
                                  transform:
                                      Matrix4.identity()..scale(-1.0, 1.0, 1.0),
                                  child: Image.file(
                                    _capturedImage!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                                : AspectRatio(
                                  aspectRatio: 1,
                                  child: ClipRect(
                                    child: Transform.scale(
                                      scale: 1.0,
                                      child: Center(
                                        // Apply horizontal flip for front camera preview
                                        child: Transform(
                                          alignment: Alignment.center,
                                          transform:
                                              Matrix4.identity()
                                                ..scale(-1.0, 1.0, 1.0),
                                          child: CameraPreview(_controller!),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                            : const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),

            // Results and Controls
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Result Text
                  if (_result != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        children: [
                          if (_isAnalyzing)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12.0),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  _result!.contains('Take a Break')
                                      ? Colors.red.withAlpha(30)
                                      : _result!.contains('Continue Working')
                                      ? Colors.green.withAlpha(30)
                                      : Colors.orange.withAlpha(30),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _result!.contains('Take a Break')
                                      ? Icons.warning_rounded
                                      : _result!.contains('Continue Working')
                                      ? Icons.check_circle_outline
                                      : Icons.info_outline,
                                  color:
                                      _result!.contains('Take a Break')
                                          ? Colors.red
                                          : _result!.contains(
                                            'Continue Working',
                                          )
                                          ? Colors.green
                                          : Colors.orange,
                                  size: 32,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _result!,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.copyWith(
                                    fontWeight:
                                        _isAnalyzing
                                            ? FontWeight.normal
                                            : FontWeight.bold,
                                    color:
                                        _result!.contains('Take a Break')
                                            ? Colors.red
                                            : _result!.contains(
                                              'Continue Working',
                                            )
                                            ? Colors.green
                                            : Colors.orange,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Button Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_capturedImage != null && !_isAnalyzing) ...[
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _capturedImage = null;
                              _result = null;
                            });
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('New Photo'),
                        ),
                        const SizedBox(width: 16),
                      ],
                      FilledButton.icon(
                        onPressed:
                            (_isProcessing || _isAnalyzing)
                                ? null
                                : _takePicture,
                        icon: const Icon(Icons.camera_alt),
                        label:
                            (_isProcessing || _isAnalyzing)
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                                : Text(
                                  _capturedImage == null
                                      ? 'Take Photo'
                                      : 'Retake Photo',
                                ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
