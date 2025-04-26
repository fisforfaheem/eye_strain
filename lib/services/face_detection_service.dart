import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;

/// Service to handle face detection and eye strain analysis using ML Kit
class FaceDetectionService {
  final FaceDetector _faceDetector = GoogleMlKit.vision.faceDetector(
    FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableTracking: false,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  /// Analyzes an image for eye strain indicators
  /// Returns a map with eye metrics and analysis results
  Future<Map<String, dynamic>> analyzeEyeStrain(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      // No faces detected
      if (faces.isEmpty) {
        return {
          'success': false,
          'message': 'No face detected. Please try again.',
        };
      }

      // Get the first detected face
      final face = faces.first;

      // Check if eye contours are available
      if (!face.contours.containsKey(FaceContourType.leftEye) ||
          !face.contours.containsKey(FaceContourType.rightEye)) {
        return {
          'success': false,
          'message': 'Eye contours not detected clearly. Please try again.',
        };
      }

      // Calculate eye openness
      final leftEyeOpenness = _calculateEyeOpenness(face, true);
      final rightEyeOpenness = _calculateEyeOpenness(face, false);

      // Check if eyes are closed
      final leftEyeClosed =
          face.leftEyeOpenProbability != null
              ? face.leftEyeOpenProbability! < 0.3
              : false;
      final rightEyeClosed =
          face.rightEyeOpenProbability != null
              ? face.rightEyeOpenProbability! < 0.3
              : false;

      // Calculate redness in eyes (optional, requires image processing)
      final eyeRedness = await _calculateEyeRedness(imagePath, face);

      // Determine if the person needs a break
      final needsBreak = _determineEyeStrain(
        leftEyeOpenness: leftEyeOpenness,
        rightEyeOpenness: rightEyeOpenness,
        leftEyeClosed: leftEyeClosed,
        rightEyeClosed: rightEyeClosed,
        eyeRedness: eyeRedness,
      );

      // Generate result message
      final resultMessage = _generateResultMessage(
        needsBreak: needsBreak,
        leftEyeOpenness: leftEyeOpenness,
        rightEyeOpenness: rightEyeOpenness,
        eyeRedness: eyeRedness,
      );

      return {
        'success': true,
        'leftEyeOpenness': leftEyeOpenness,
        'rightEyeOpenness': rightEyeOpenness,
        'leftEyeClosed': leftEyeClosed,
        'rightEyeClosed': rightEyeClosed,
        'eyeRedness': eyeRedness,
        'needsBreak': needsBreak,
        'message': resultMessage,
      };
    } catch (e) {
      if (kDebugMode) {
        print('[FaceDetectionService] Error analyzing eye strain: $e');
      }
      return {'success': false, 'message': 'Error analyzing image: $e'};
    }
  }

  /// Calculate eye openness based on contours
  double _calculateEyeOpenness(Face face, bool isLeft) {
    try {
      final eyeContour =
          isLeft
              ? face.contours[FaceContourType.leftEye]
              : face.contours[FaceContourType.rightEye];

      if (eyeContour == null || eyeContour.points.length < 4) {
        // Use the probability if contour isn't detailed enough
        return isLeft
            ? (face.leftEyeOpenProbability ?? 0.5)
            : (face.rightEyeOpenProbability ?? 0.5);
      }

      // Calculate the height and width of the eye
      double minY = double.infinity;
      double maxY = -double.infinity;
      double minX = double.infinity;
      double maxX = -double.infinity;

      for (final point in eyeContour.points) {
        if (point.y < minY) minY = point.y.toDouble();
        if (point.y > maxY) maxY = point.y.toDouble();
        if (point.x < minX) minX = point.x.toDouble();
        if (point.x > maxX) maxX = point.x.toDouble();
      }

      final height = maxY - minY;
      final width = maxX - minX;

      // Calculate aspect ratio (height/width)
      // A smaller ratio indicates more closed eyes
      if (width == 0) return 0.5; // Avoid division by zero

      final aspectRatio = height / width;

      // Normalize to a 0-1 scale where 1 is fully open
      // Typical values range from 0.2 (closed) to 0.5 (open)
      final normalizedOpenness = (aspectRatio - 0.2) / 0.3;

      // Clamp to 0-1 range
      return normalizedOpenness.clamp(0.0, 1.0);
    } catch (e) {
      // Fallback to the probability
      return isLeft
          ? (face.leftEyeOpenProbability ?? 0.5)
          : (face.rightEyeOpenProbability ?? 0.5);
    }
  }

  /// Calculate redness in eyes (simplified version)
  Future<double> _calculateEyeRedness(String imagePath, Face face) async {
    try {
      // Load the image
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) return 0.0;

      // Get eye regions
      final leftEyeContour = face.contours[FaceContourType.leftEye];
      final rightEyeContour = face.contours[FaceContourType.rightEye];

      if (leftEyeContour == null || rightEyeContour == null) {
        return 0.0;
      }

      // Calculate bounding boxes for eyes
      int leftMinX = image.width,
          leftMaxX = 0,
          leftMinY = image.height,
          leftMaxY = 0;
      int rightMinX = image.width,
          rightMaxX = 0,
          rightMinY = image.height,
          rightMaxY = 0;

      for (final point in leftEyeContour.points) {
        final x = point.x.toInt().clamp(0, image.width - 1);
        final y = point.y.toInt().clamp(0, image.height - 1);
        if (x < leftMinX) leftMinX = x;
        if (x > leftMaxX) leftMaxX = x;
        if (y < leftMinY) leftMinY = y;
        if (y > leftMaxY) leftMaxY = y;
      }

      for (final point in rightEyeContour.points) {
        final x = point.x.toInt().clamp(0, image.width - 1);
        final y = point.y.toInt().clamp(0, image.height - 1);
        if (x < rightMinX) rightMinX = x;
        if (x > rightMaxX) rightMaxX = x;
        if (y < rightMinY) rightMinY = y;
        if (y > rightMaxY) rightMaxY = y;
      }

      // Expand the regions slightly
      final expandBy = 5;
      leftMinX = (leftMinX - expandBy).clamp(0, image.width - 1);
      leftMaxX = (leftMaxX + expandBy).clamp(0, image.width - 1);
      leftMinY = (leftMinY - expandBy).clamp(0, image.height - 1);
      leftMaxY = (leftMaxY + expandBy).clamp(0, image.height - 1);

      rightMinX = (rightMinX - expandBy).clamp(0, image.width - 1);
      rightMaxX = (rightMaxX + expandBy).clamp(0, image.width - 1);
      rightMinY = (rightMinY - expandBy).clamp(0, image.height - 1);
      rightMaxY = (rightMaxY + expandBy).clamp(0, image.height - 1);

      // Calculate redness in both eye regions
      double leftRedness = 0;
      double rightRedness = 0;
      int leftPixelCount = 0;
      int rightPixelCount = 0;

      // Process left eye
      for (int y = leftMinY; y <= leftMaxY; y++) {
        for (int x = leftMinX; x <= leftMaxX; x++) {
          final pixel = image.getPixel(x, y);
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();

          // Calculate redness (r - (g+b)/2)
          final redness = r - ((g + b) / 2);
          if (redness > 0) {
            leftRedness += redness;
            leftPixelCount++;
          }
        }
      }

      // Process right eye
      for (int y = rightMinY; y <= rightMaxY; y++) {
        for (int x = rightMinX; x <= rightMaxX; x++) {
          final pixel = image.getPixel(x, y);
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();

          // Calculate redness (r - (g+b)/2)
          final redness = r - ((g + b) / 2);
          if (redness > 0) {
            rightRedness += redness;
            rightPixelCount++;
          }
        }
      }

      // Calculate average redness
      final avgLeftRedness =
          leftPixelCount > 0 ? leftRedness / leftPixelCount : 0;
      final avgRightRedness =
          rightPixelCount > 0 ? rightRedness / rightPixelCount : 0;

      // Normalize to 0-1 scale (assuming max redness is around 50)
      final normalizedRedness = ((avgLeftRedness + avgRightRedness) / 2) / 50;

      return normalizedRedness.clamp(0.0, 1.0);
    } catch (e) {
      if (kDebugMode) {
        print('[FaceDetectionService] Error calculating eye redness: $e');
      }
      return 0.0;
    }
  }

  /// Determine if the person needs a break based on eye metrics
  bool _determineEyeStrain({
    required double leftEyeOpenness,
    required double rightEyeOpenness,
    required bool leftEyeClosed,
    required bool rightEyeClosed,
    required double eyeRedness,
  }) {
    // Calculate average eye openness
    final avgEyeOpenness = (leftEyeOpenness + rightEyeOpenness) / 2;

    // Check for severe eye strain indicators
    if (avgEyeOpenness < 0.3) {
      return true; // Eyes are significantly closed
    }

    if (leftEyeClosed && rightEyeClosed) {
      return true; // Both eyes are closed
    }

    // Check for moderate eye strain
    if (avgEyeOpenness < 0.5 && eyeRedness > 0.4) {
      return true; // Moderately closed eyes with significant redness
    }

    // Check for asymmetry (one eye more strained than other)
    if ((leftEyeOpenness - rightEyeOpenness).abs() > 0.2) {
      return true; // Asymmetric eye strain
    }

    // Check for high redness
    if (eyeRedness > 0.6) {
      return true; // Very red eyes
    }

    return false; // No significant eye strain detected
  }

  /// Generate a detailed result message based on eye metrics
  String _generateResultMessage({
    required bool needsBreak,
    required double leftEyeOpenness,
    required double rightEyeOpenness,
    required double eyeRedness,
  }) {
    final avgEyeOpenness = (leftEyeOpenness + rightEyeOpenness) / 2;
    final eyeAsymmetry = (leftEyeOpenness - rightEyeOpenness).abs();

    if (needsBreak) {
      if (avgEyeOpenness < 0.3) {
        return 'Take a Break! Your eyes are significantly closed, indicating fatigue.';
      } else if (eyeAsymmetry > 0.2) {
        return 'Take a Break! Uneven eye strain detected - one eye appears more strained than the other.';
      } else if (eyeRedness > 0.6) {
        return 'Take a Break! Your eyes show significant redness, indicating strain.';
      } else {
        return 'Take a Break! Your eyes show signs of strain.';
      }
    } else {
      if (avgEyeOpenness > 0.7 && eyeRedness < 0.3) {
        return 'Continue Working. Your eyes look healthy and alert.';
      } else if (avgEyeOpenness > 0.5 && eyeRedness < 0.4) {
        return 'Continue Working. No significant eye strain detected.';
      } else {
        return 'Continue Working, but consider a short break soon. Early signs of eye fatigue detected.';
      }
    }
  }

  /// Dispose of resources
  void dispose() {
    _faceDetector.close();
  }
}
