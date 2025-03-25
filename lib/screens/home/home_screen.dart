import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math';
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

  // Demo analysis results
  final List<String> _possibleResults = [
    'Take a Break! Your eyes show signs of strain.',
    'Continue Working. No significant eye strain detected.',
    'Mild eye strain detected. Consider a short break soon.',
  ];

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

  // Simulate eye strain analysis for demo purposes
  Future<void> _analyzeEyeStrain() async {
    setState(() {
      _isAnalyzing = true;
      _result = 'Analyzing your eye strain...';
    });

    // Simulate analysis delay (3 seconds)
    await Future.delayed(const Duration(seconds: 3));

    // Generate a random result for demo
    final random = Random();
    final resultIndex = random.nextInt(_possibleResults.length);
    final analysisResult = _possibleResults[resultIndex];

    // Save result to history using EyeStrainService
    final userId = context.read<AuthService>().currentUser?.uid;
    if (userId != null && _capturedImage != null) {
      try {
        await _eyeStrainService.saveDemoEyeCheck(
          userId: userId,
          result: analysisResult,
          imagePath: _capturedImage!.path,
        );
        debugPrint('Result saved to history');
      } catch (e) {
        debugPrint('Error saving to history: $e');
      }
    }

    if (mounted) {
      setState(() {
        _result = analysisResult;
        _isAnalyzing = false;
        _isProcessing = false;
      });
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
        title: const Text('EyeGuard Demo'),
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
                            Icons.info_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Demo Mode',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This is a simplified demo version. Take a photo and we\'ll analyze your eye strain in 3 seconds.',
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
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child:
                        _isCameraInitialized
                            ? _capturedImage != null
                                ? Image.file(_capturedImage!, fit: BoxFit.cover)
                                : AspectRatio(
                                  aspectRatio: 1,
                                  child: ClipRect(
                                    child: Transform.scale(
                                      scale: 1.0,
                                      child: Center(
                                        child: CameraPreview(_controller!),
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
                                      : _result!.contains('Continue Working')
                                      ? Colors.green
                                      : null,
                            ),
                            textAlign: TextAlign.center,
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
