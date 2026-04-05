import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:eye_strain/models/eye_check.dart';
import 'package:eye_strain/services/face_detection_service.dart';
import 'package:uuid/uuid.dart';

class EyeCheckSaveResult {
  final EyeCheck eyeCheck;
  final bool savedToCloud;
  final String? cloudErrorMessage;

  const EyeCheckSaveResult({
    required this.eyeCheck,
    required this.savedToCloud,
    this.cloudErrorMessage,
  });
}

class EyeCheckDeleteResult {
  final bool deletedFromCloud;
  final String? cloudErrorMessage;

  const EyeCheckDeleteResult({
    required this.deletedFromCloud,
    this.cloudErrorMessage,
  });
}

/// Service to handle eye strain detection and history
class EyeStrainService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _uuid = const Uuid();
  final _faceDetectionService = FaceDetectionService();

  // Constants for eye strain detection
  static const double _severeStrainThreshold = 0.4;
  static const double _moderateStrainThreshold = 0.6;
  static const int _minSampleCount = 3;

  /// Analyze eye strain based on multiple factors
  bool analyzeEyeStrain({
    required double leftEyeOpenness,
    required double rightEyeOpenness,
    required List<EyeCheck> recentChecks,
  }) {
    // 1. Current eye openness check
    final currentAverageOpenness = (leftEyeOpenness + rightEyeOpenness) / 2;

    // If eyes are severely closed, immediate break needed
    if (currentAverageOpenness < _severeStrainThreshold) {
      return true;
    }

    // 2. Check recent history pattern
    if (recentChecks.length >= _minSampleCount) {
      final last3Checks = recentChecks.take(_minSampleCount).toList();

      // Calculate trend of eye openness
      double averageDecline = 0;
      for (int i = 0; i < last3Checks.length - 1; i++) {
        final current =
            ((last3Checks[i].leftEyeOpenness ?? 0.5) +
                (last3Checks[i].rightEyeOpenness ?? 0.5)) /
            2;
        final next =
            ((last3Checks[i + 1].leftEyeOpenness ?? 0.5) +
                (last3Checks[i + 1].rightEyeOpenness ?? 0.5)) /
            2;
        averageDecline += current - next;
      }
      averageDecline /= (_minSampleCount - 1);

      // If there's a consistent decline in eye openness
      if (averageDecline > 0.1) {
        return true;
      }
    }

    // 3. Check asymmetry (one eye more strained than other)
    final asymmetry = (leftEyeOpenness - rightEyeOpenness).abs();
    if (asymmetry > 0.2) {
      return true;
    }

    // 4. Moderate strain check
    return currentAverageOpenness < _moderateStrainThreshold;
  }

  /// Get the application documents directory
  Future<Directory> get _localDir async {
    final directory = await getApplicationDocumentsDirectory();
    final eyeChecksDir = Directory('${directory.path}/eye_checks');
    if (!await eyeChecksDir.exists()) {
      await eyeChecksDir.create(recursive: true);
    }
    return eyeChecksDir;
  }

  /// Save eye check result to Firestore and local storage
  Future<EyeCheckSaveResult> saveEyeCheck({
    required String userId,
    required double leftEyeOpenness,
    required double rightEyeOpenness,
    required bool needsBreak,
    required String tempImagePath,
  }) async {
    try {
      final directory = await _localDir;
      final timestamp = DateTime.now();
      final id = _uuid.v4();

      // Copy image to local storage
      final imageName = '${timestamp.millisecondsSinceEpoch}.jpg';
      final localImagePath = '${directory.path}/$imageName';
      await File(tempImagePath).copy(localImagePath);

      // Create eye check
      final eyeCheck = EyeCheck(
        id: id,
        userId: userId,
        timestamp: timestamp,
        leftEyeOpenness: leftEyeOpenness,
        rightEyeOpenness: rightEyeOpenness,
        needsBreak: needsBreak,
        localImagePath: localImagePath,
        result:
            needsBreak
                ? 'Take a Break! Your eyes show signs of strain.'
                : 'Continue Working. No significant eye strain detected.',
      );

      // Save to local storage
      await _saveLocalEyeCheck(eyeCheck);

      bool savedToCloud = false;
      String? cloudErrorMessage;

      try {
        await _firestore
            .collection('eye_checks')
            .doc(id)
            .set(eyeCheck.toFirestore());
        savedToCloud = true;
      } catch (e) {
        cloudErrorMessage = _formatCloudError(e);
        if (kDebugMode) {
          print('[EyeStrainService] Cloud save error: $e');
        }
      }

      // Delete temp image
      await File(tempImagePath).delete();

      return EyeCheckSaveResult(
        eyeCheck: eyeCheck,
        savedToCloud: savedToCloud,
        cloudErrorMessage: cloudErrorMessage,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[EyeStrainService] Save eye check error: $e');
      }
      rethrow;
    }
  }

  /// Analyze eye strain using ML Kit face detection
  Future<Map<String, dynamic>> analyzeEyeStrainWithMlKit(
    String imagePath,
  ) async {
    try {
      // Use the face detection service to analyze the image
      final analysisResult = await _faceDetectionService.analyzeEyeStrain(
        imagePath,
      );

      if (!analysisResult['success']) {
        return analysisResult;
      }

      return analysisResult;
    } catch (e) {
      if (kDebugMode) {
        print('[EyeStrainService] ML Kit analysis error: $e');
      }
      return {'success': false, 'message': 'Error analyzing eye strain: $e'};
    }
  }

  /// Save eye check result from ML Kit analysis to Firestore and local storage
  Future<EyeCheckSaveResult> saveEyeCheckFromAnalysis({
    required String userId,
    required String imagePath,
    required Map<String, dynamic> analysisResult,
  }) async {
    try {
      final directory = await _localDir;
      final timestamp = DateTime.now();
      final id = _uuid.v4();

      // Copy image to local storage
      final imageName = '${timestamp.millisecondsSinceEpoch}.jpg';
      final localImagePath = '${directory.path}/$imageName';
      await File(imagePath).copy(localImagePath);

      // Create eye check
      final eyeCheck = EyeCheck(
        id: id,
        userId: userId,
        timestamp: timestamp,
        leftEyeOpenness: analysisResult['leftEyeOpenness'],
        rightEyeOpenness: analysisResult['rightEyeOpenness'],
        needsBreak: analysisResult['needsBreak'],
        localImagePath: localImagePath,
        result: analysisResult['message'],
      );

      // Save to local storage
      await _saveLocalEyeCheck(eyeCheck);

      bool savedToCloud = false;
      String? cloudErrorMessage;

      try {
        await _firestore
            .collection('eye_checks')
            .doc(id)
            .set(eyeCheck.toFirestore());
        savedToCloud = true;
      } catch (e) {
        cloudErrorMessage = _formatCloudError(e);
        if (kDebugMode) {
          print('[EyeStrainService] Cloud save error: $e');
        }
      }

      // Delete temp image
      await File(imagePath).delete();

      return EyeCheckSaveResult(
        eyeCheck: eyeCheck,
        savedToCloud: savedToCloud,
        cloudErrorMessage: cloudErrorMessage,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[EyeStrainService] Save eye check error: $e');
      }
      rethrow;
    }
  }

  /// Save demo eye check result to Firestore and local storage
  Future<EyeCheckSaveResult> saveDemoEyeCheck({
    required String userId,
    required String result,
    required String imagePath,
  }) async {
    try {
      final directory = await _localDir;
      final timestamp = DateTime.now();
      final id = _uuid.v4();

      // Copy image to local storage if it exists
      String localImagePath = '';
      if (imagePath.isNotEmpty) {
        final imageName = '${timestamp.millisecondsSinceEpoch}.jpg';
        localImagePath = '${directory.path}/$imageName';
        await File(imagePath).copy(localImagePath);
      }

      // Determine if break is needed based on result text
      final needsBreak =
          result.contains('Take a Break') || result.contains('break soon');

      // Create eye check
      final eyeCheck = EyeCheck(
        id: id,
        userId: userId,
        timestamp: timestamp,
        needsBreak: needsBreak,
        localImagePath: localImagePath,
        result: result,
      );

      // Save to local storage
      await _saveLocalEyeCheck(eyeCheck);

      bool savedToCloud = false;
      String? cloudErrorMessage;

      try {
        await _firestore
            .collection('eye_checks')
            .doc(id)
            .set(eyeCheck.toFirestore());
        savedToCloud = true;
      } catch (e) {
        cloudErrorMessage = _formatCloudError(e);
        if (kDebugMode) {
          print('[EyeStrainService] Cloud save error: $e');
        }
      }

      return EyeCheckSaveResult(
        eyeCheck: eyeCheck,
        savedToCloud: savedToCloud,
        cloudErrorMessage: cloudErrorMessage,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[EyeStrainService] Save demo eye check error: $e');
      }
      rethrow;
    }
  }

  /// Save eye check to local storage
  Future<void> _saveLocalEyeCheck(EyeCheck eyeCheck) async {
    try {
      final directory = await _localDir;
      final file = File('${directory.path}/eye_checks.json');

      List<Map<String, dynamic>> checks = [];
      if (await file.exists()) {
        final contents = await file.readAsString();
        checks = List<Map<String, dynamic>>.from(jsonDecode(contents));
      }

      checks.insert(0, eyeCheck.toJson());
      await file.writeAsString(jsonEncode(checks));
    } catch (e) {
      if (kDebugMode) {
        print('[EyeStrainService] Save local eye check error: $e');
      }
      rethrow;
    }
  }

  /// Get eye check history for a user
  Stream<List<EyeCheck>> getEyeCheckHistory(String userId) {
    return _firestore
        .collection('eye_checks')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => EyeCheck.fromFirestore(doc)).toList(),
        );
  }

  /// Delete eye check from both Firestore and local storage
  Future<EyeCheckDeleteResult> deleteEyeCheck(EyeCheck eyeCheck) async {
    try {
      // Delete image file
      final imageFile = File(eyeCheck.localImagePath);
      if (await imageFile.exists()) {
        await imageFile.delete();
      }

      // Remove from local storage
      final directory = await _localDir;
      final file = File('${directory.path}/eye_checks.json');
      if (await file.exists()) {
        final contents = await file.readAsString();
        final checks = List<Map<String, dynamic>>.from(jsonDecode(contents));
        checks.removeWhere((check) => check['id'] == eyeCheck.id);
        await file.writeAsString(jsonEncode(checks));
      }

      bool deletedFromCloud = false;
      String? cloudErrorMessage;

      try {
        await _firestore.collection('eye_checks').doc(eyeCheck.id).delete();
        deletedFromCloud = true;
      } catch (e) {
        cloudErrorMessage = _formatCloudError(e);
        if (kDebugMode) {
          print('[EyeStrainService] Cloud delete error: $e');
        }
      }

      return EyeCheckDeleteResult(
        deletedFromCloud: deletedFromCloud,
        cloudErrorMessage: cloudErrorMessage,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[EyeStrainService] Delete eye check error: $e');
      }
      rethrow;
    }
  }

  /// Get local eye check history
  Future<List<EyeCheck>> getLocalEyeCheckHistory(String userId) async {
    try {
      final directory = await _localDir;
      final file = File('${directory.path}/eye_checks.json');

      if (!await file.exists()) {
        return [];
      }

      final contents = await file.readAsString();
      final checks = List<Map<String, dynamic>>.from(jsonDecode(contents));
      return checks
          .where((check) => check['userId'] == userId)
          .map((check) => EyeCheck.fromJson(check))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('[EyeStrainService] Get local eye check history error: $e');
      }
      return [];
    }
  }

  /// Dispose of resources
  void dispose() {
    _faceDetectionService.dispose();
  }

  String _formatCloudError(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Saved on this device, but the cloud save was denied.';
    }

    return 'Saved on this device, but the cloud sync failed.';
  }
}
