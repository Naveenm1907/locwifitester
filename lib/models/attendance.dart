enum AttendanceStatus {
  present,
  absent,
  late,
}

enum LocationVerificationMethod {
  gps,
  wifi,
  both,
  manual, // For admin overrides
}

class Attendance {
  final String id;
  final String userId;
  final String roomId;
  final DateTime timestamp;
  final AttendanceStatus status;
  final LocationVerificationMethod verificationMethod;
  final double? latitude;
  final double? longitude;
  final double? accuracy; // GPS accuracy in meters
  final List<String>? detectedWifiSignals; // BSSIDs detected
  final int? strongestSignalStrength; // In dBm
  final bool isVerified;
  final String? notes;
  final DateTime createdAt;

  Attendance({
    required this.id,
    required this.userId,
    required this.roomId,
    required this.timestamp,
    required this.status,
    required this.verificationMethod,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.detectedWifiSignals,
    this.strongestSignalStrength,
    this.isVerified = false,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'roomId': roomId,
      'timestamp': timestamp.toIso8601String(),
      'status': status.toString().split('.').last,
      'verificationMethod': verificationMethod.toString().split('.').last,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'detectedWifiSignals': detectedWifiSignals?.join(','),
      'strongestSignalStrength': strongestSignalStrength,
      'isVerified': isVerified ? 1 : 0,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Attendance.fromMap(Map<String, dynamic> map) {
    return Attendance(
      id: map['id'],
      userId: map['userId'],
      roomId: map['roomId'],
      timestamp: DateTime.parse(map['timestamp']),
      status: AttendanceStatus.values.firstWhere(
        (e) => e.toString().split('.').last == map['status'],
      ),
      verificationMethod: LocationVerificationMethod.values.firstWhere(
        (e) => e.toString().split('.').last == map['verificationMethod'],
      ),
      latitude: map['latitude'],
      longitude: map['longitude'],
      accuracy: map['accuracy'],
      detectedWifiSignals: map['detectedWifiSignals'] != null
          ? (map['detectedWifiSignals'] as String).split(',')
          : null,
      strongestSignalStrength: map['strongestSignalStrength'],
      isVerified: map['isVerified'] == 1,
      notes: map['notes'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}

