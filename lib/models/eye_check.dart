import 'package:cloud_firestore/cloud_firestore.dart';

/// Model class for eye strain check results
class EyeCheck {
  final String id;
  final String userId;
  final DateTime timestamp;
  final double leftEyeOpenness;
  final double rightEyeOpenness;
  final bool needsBreak;
  final String localImagePath; // Local path to the image

  EyeCheck({
    required this.id,
    required this.userId,
    required this.timestamp,
    required this.leftEyeOpenness,
    required this.rightEyeOpenness,
    required this.needsBreak,
    required this.localImagePath,
  });

  // Create from Firestore document
  factory EyeCheck.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EyeCheck(
      id: doc.id,
      userId: data['userId'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      leftEyeOpenness: (data['leftEyeOpenness'] ?? 0.0).toDouble(),
      rightEyeOpenness: (data['rightEyeOpenness'] ?? 0.0).toDouble(),
      needsBreak: data['needsBreak'] ?? false,
      localImagePath: data['localImagePath'] ?? '',
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
    };
  }

  // Create from local storage
  factory EyeCheck.fromJson(Map<String, dynamic> json) {
    return EyeCheck(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      leftEyeOpenness: (json['leftEyeOpenness'] ?? 0.0).toDouble(),
      rightEyeOpenness: (json['rightEyeOpenness'] ?? 0.0).toDouble(),
      needsBreak: json['needsBreak'] ?? false,
      localImagePath: json['localImagePath'] ?? '',
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
    };
  }
}
