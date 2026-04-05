import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:eye_strain/screens/history/history_screen.dart';
import 'package:eye_strain/screens/profile/profile_screen.dart';
import 'package:eye_strain/services/auth_service.dart';
import 'package:eye_strain/services/eye_strain_service.dart';

enum CameraAccessState {
  requestingPermission,
  permissionDenied,
  permissionPermanentlyDenied,
  unavailable,
  initializationFailed,
  ready,
}

/// HomeScreen is the main screen of the app where users can take photos
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  CameraAccessState _cameraState = CameraAccessState.requestingPermission;
  bool _isProcessing = false;
  bool _isAnalyzing = false;
  String? _result;
  String? _cameraMessage;
  File? _capturedImage;
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
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
      return;
    }

    if (state == AppLifecycleState.resumed &&
        _capturedImage == null &&
        !_isProcessing &&
        !_isAnalyzing) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (mounted) {
        setState(() {
          _cameraState = CameraAccessState.requestingPermission;
          _cameraMessage = null;
        });
      }

      final permissionStatus = await Permission.camera.request();
      if (!mounted) return;

      if (permissionStatus.isPermanentlyDenied || permissionStatus.isRestricted) {
        setState(() {
          _cameraState = CameraAccessState.permissionPermanentlyDenied;
          _cameraMessage =
              'Camera access is blocked. Turn it back on in Android settings.';
        });
        return;
      }

      if (!permissionStatus.isGranted) {
        setState(() {
          _cameraState = CameraAccessState.permissionDenied;
          _cameraMessage =
              'Camera permission is required before the app can analyze a selfie.';
        });
        return;
      }

      await _controller?.dispose();
      _controller = null;

      final cameras = await availableCameras();
      if (!mounted) return;

      if (cameras.isEmpty) {
        setState(() {
          _cameraState = CameraAccessState.unavailable;
          _cameraMessage = 'No camera is available on this device.';
        });
        return;
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup:
            Platform.isAndroid
                ? ImageFormatGroup.yuv420
                : ImageFormatGroup.bgra8888,
      );

      _controller = controller;
      await controller.initialize();

      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint('Focus mode not supported: $e');
      }

      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint('Exposure mode not supported: $e');
      }

      if (!mounted) return;
      setState(() {
        _cameraState = CameraAccessState.ready;
        _cameraMessage = null;
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (!mounted) return;
      setState(() {
        _cameraState = CameraAccessState.initializationFailed;
        _cameraMessage = 'The camera could not start. Please try again.';
      });
    }
  }

  Future<void> _analyzeEyeStrain() async {
    final authService = context.read<AuthService>();

    setState(() {
      _isAnalyzing = true;
      _result = 'Analyzing your eye strain...';
    });

    final userId = authService.currentUser?.uid;
    if (userId == null || _capturedImage == null) {
      setState(() {
        _result =
            'Your session ended before the scan could be saved. Please sign in again.';
        _isAnalyzing = false;
        _isProcessing = false;
      });
      return;
    }

    try {
      final analysisResult = await _eyeStrainService.analyzeEyeStrainWithMlKit(
        _capturedImage!.path,
      );

      if (!analysisResult['success']) {
        setState(() {
          _result = analysisResult['message'] as String;
          _isAnalyzing = false;
          _isProcessing = false;
        });
        return;
      }

      if (authService.currentUser == null) {
        setState(() {
          _result =
              'Your session expired. Please sign in again and retake the photo.';
          _isAnalyzing = false;
          _isProcessing = false;
        });
        return;
      }

      final saveResult = await _eyeStrainService.saveEyeCheckFromAnalysis(
        userId: userId,
        imagePath: _capturedImage!.path,
        analysisResult: analysisResult,
      );

      if (!mounted) return;
      setState(() {
        _result =
            saveResult.savedToCloud
                ? analysisResult['message'] as String
                : '${analysisResult['message']}\n\n${saveResult.cloudErrorMessage}';
        _capturedImage = File(saveResult.eyeCheck.localImagePath);
        _isAnalyzing = false;
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint('Error in eye strain analysis: $e');
      if (!mounted) return;
      setState(() {
        _result =
            'Something went wrong while analyzing your photo. Please try again.';
        _isAnalyzing = false;
        _isProcessing = false;
      });
    }
  }

  Future<void> _takePicture() async {
    if (!_canTakePhoto) return;

    setState(() {
      _isProcessing = true;
      _result = null;
    });

    try {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) {
        setState(() {
          _cameraState = CameraAccessState.initializationFailed;
          _cameraMessage = 'The camera is not ready yet. Please try again.';
          _isProcessing = false;
        });
        return;
      }

      final image = await controller.takePicture();

      if (!mounted) return;
      setState(() {
        _capturedImage = File(image.path);
      });

      await _analyzeEyeStrain();
    } catch (e) {
      debugPrint('Error taking picture: $e');
      if (!mounted) return;
      setState(() {
        _result = 'Could not take the photo. Please try again.';
        _isProcessing = false;
      });
    }
  }

  Future<void> _resetCapture() async {
    setState(() {
      _capturedImage = null;
      _result = null;
      _isProcessing = false;
      _isAnalyzing = false;
    });

    await _initializeCamera();
  }

  Widget _buildCameraFallback() {
    final isWaitingForPermission =
        _cameraState == CameraAccessState.requestingPermission;
    final canRetry =
        _cameraState == CameraAccessState.permissionDenied ||
        _cameraState == CameraAccessState.unavailable ||
        _cameraState == CameraAccessState.initializationFailed;
    final canOpenSettings =
        _cameraState == CameraAccessState.permissionPermanentlyDenied;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isWaitingForPermission ? Icons.camera_alt : Icons.camera_alt_outlined,
              size: 40,
              color: Colors.white70,
            ),
            const SizedBox(height: 16),
            Text(
              _cameraMessage ??
                  (isWaitingForPermission
                      ? 'Requesting camera permission...'
                      : 'Preparing the camera...'),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (isWaitingForPermission) const CircularProgressIndicator(),
            if (canRetry)
              FilledButton(
                onPressed: _initializeCamera,
                child: const Text('Try Again'),
              ),
            if (canOpenSettings)
              FilledButton(
                onPressed: openAppSettings,
                child: const Text('Open Settings'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraContent() {
    if (_capturedImage != null) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
        child: Image.file(_capturedImage!, fit: BoxFit.cover),
      );
    }

    final controller = _controller;
    if (_cameraState == CameraAccessState.ready &&
        controller != null &&
        controller.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 1,
        child: ClipRect(
          child: Transform.scale(
            scale: 1.0,
            child: Center(
              child: Transform(
                alignment: Alignment.center,
                transform:
                    Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
                child: CameraPreview(controller),
              ),
            ),
          ),
        ),
      );
    }

    return _buildCameraFallback();
  }

  bool get _canTakePhoto =>
      _cameraState == CameraAccessState.ready &&
      !_isProcessing &&
      !_isAnalyzing &&
      _capturedImage == null;

  bool get _canResetPhoto =>
      _capturedImage != null && !_isProcessing && !_isAnalyzing;

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
                          color: Colors.black.withAlpha(51),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _buildCameraContent(),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_capturedImage != null && !_isAnalyzing) ...[
                        OutlinedButton.icon(
                          onPressed: _canResetPhoto ? _resetCapture : null,
                          icon: const Icon(Icons.refresh),
                          label: const Text('New Photo'),
                        ),
                        const SizedBox(width: 16),
                      ],
                      FilledButton.icon(
                        onPressed: _canTakePhoto ? _takePicture : null,
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
                                : const Text('Take Photo'),
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
