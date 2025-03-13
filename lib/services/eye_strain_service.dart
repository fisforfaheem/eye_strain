import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:eye_strain/models/eye_check.dart';
import 'package:uuid/uuid.dart';

/// Service to handle eye strain detection and history
class EyeStrainService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  // Constants for eye strain detection
  static const double _severeStrainThreshold = 0.4;
  static const double _moderateStrainThreshold = 0.6;
  static const double _minConfidenceThreshold = 0.7;
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
            (last3Checks[i].leftEyeOpenness + last3Checks[i].rightEyeOpenness) /
            2;
        final next =
            (last3Checks[i + 1].leftEyeOpenness +
                last3Checks[i + 1].rightEyeOpenness) /
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
  Future<void> saveEyeCheck({
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
      );

      // Save to Firestore
      await _firestore
          .collection('eye_checks')
          .doc(id)
          .set(eyeCheck.toFirestore());

      // Save to local storage
      await _saveLocalEyeCheck(eyeCheck);

      // Delete temp image
      await File(tempImagePath).delete();
    } catch (e) {
      if (kDebugMode) {
        print('[EyeStrainService] Save eye check error: $e');
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
  Future<void> deleteEyeCheck(EyeCheck eyeCheck) async {
    try {
      // Delete from Firestore
      await _firestore.collection('eye_checks').doc(eyeCheck.id).delete();

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
}
