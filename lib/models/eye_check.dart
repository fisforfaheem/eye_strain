import 'package:cloud_firestore/cloud_firestore.dart';

/// Model class for eye strain check results
class EyeCheck {
  final String id;
  final String userId;
  final DateTime timestamp;
  final double? leftEyeOpenness;
  final double? rightEyeOpenness;
  final bool needsBreak;
  final String localImagePath; // Local path to the image
  final String result; // Text result from analysis

  EyeCheck({
    required this.id,
    required this.userId,
    required this.timestamp,
    this.leftEyeOpenness,
    this.rightEyeOpenness,
    required this.needsBreak,
    required this.localImagePath,
    required this.result,
  });

  // Create from Firestore document
  factory EyeCheck.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Determine if break is needed based on result text if needsBreak is not available
    bool needsBreak = data['needsBreak'] ?? false;
    String result = data['result'] ?? '';

    if (!data.containsKey('needsBreak') && result.isNotEmpty) {
      needsBreak =
          result.contains('Take a Break') || result.contains('break soon');
    }

    return EyeCheck(
      id: doc.id,
      userId: data['userId'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      leftEyeOpenness: (data['leftEyeOpenness'] as num?)?.toDouble(),
      rightEyeOpenness: (data['rightEyeOpenness'] as num?)?.toDouble(),
      needsBreak: needsBreak,
      localImagePath: data['localImagePath'] ?? data['imagePath'] ?? '',
      result: result,
    );
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'timestamp': Timestamp.fromDate(timestamp),
      'leftEyeOpenness': leftEyeOpenness,
      'rightEyeOpenness': rightEyeOpenness,
      'needsBreak': needsBreak,
      'localImagePath': localImagePath,
      'result': result,
    };
  }

  // Create from local storage
  factory EyeCheck.fromJson(Map<String, dynamic> json) {
    // Determine if break is needed based on result text if needsBreak is not available
    bool needsBreak = json['needsBreak'] ?? false;
    String result = json['result'] ?? '';

    if (!json.containsKey('needsBreak') && result.isNotEmpty) {
      needsBreak =
          result.contains('Take a Break') || result.contains('break soon');
    }

    return EyeCheck(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      leftEyeOpenness: (json['leftEyeOpenness'] as num?)?.toDouble(),
      rightEyeOpenness: (json['rightEyeOpenness'] as num?)?.toDouble(),
      needsBreak: needsBreak,
      localImagePath: json['localImagePath'] ?? json['imagePath'] ?? '',
      result: result,
    );
  }

  // Convert to JSON for local storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'timestamp': timestamp.toIso8601String(),
      'leftEyeOpenness': leftEyeOpenness,
      'rightEyeOpenness': rightEyeOpenness,
      'needsBreak': needsBreak,
      'localImagePath': localImagePath,
      'result': result,
    };
  }
}
