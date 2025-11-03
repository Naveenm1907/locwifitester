class WiFiRouter {
  final String id;
  final String ssid; // WiFi network name
  final String bssid; // MAC address (unique identifier)
  final String building;
  final int floor;
  final String? location; // Description of where router is located
  final int signalStrengthThreshold; // Minimum signal strength (dBm) for detection
  final int sameFloorMinSignal; // Minimum signal for same floor (-55 dBm typical)
  final int differentFloorMaxSignal; // Maximum signal for different floor (-75 dBm typical)
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  WiFiRouter({
    required this.id,
    required this.ssid,
    required this.bssid,
    required this.building,
    required this.floor,
    this.location,
    this.signalStrengthThreshold = -70, // Default threshold for detection
    this.sameFloorMinSignal = -55, // Must be >= -55 dBm to confirm same floor
    this.differentFloorMaxSignal = -75, // Must be <= -75 dBm if on different floor
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ssid': ssid,
      'bssid': bssid,
      'building': building,
      'floor': floor,
      'location': location,
      'signalStrengthThreshold': signalStrengthThreshold,
      'sameFloorMinSignal': sameFloorMinSignal,
      'differentFloorMaxSignal': differentFloorMaxSignal,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory WiFiRouter.fromMap(Map<String, dynamic> map) {
    return WiFiRouter(
      id: map['id'],
      ssid: map['ssid'],
      bssid: map['bssid'],
      building: map['building'],
      floor: map['floor'],
      location: map['location'],
      signalStrengthThreshold: map['signalStrengthThreshold'] ?? -70,
      sameFloorMinSignal: map['sameFloorMinSignal'] ?? -55,
      differentFloorMaxSignal: map['differentFloorMaxSignal'] ?? -75,
      isActive: map['isActive'] == 1,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
    );
  }

  WiFiRouter copyWith({
    String? id,
    String? ssid,
    String? bssid,
    String? building,
    int? floor,
    String? location,
    int? signalStrengthThreshold,
    int? sameFloorMinSignal,
    int? differentFloorMaxSignal,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WiFiRouter(
      id: id ?? this.id,
      ssid: ssid ?? this.ssid,
      bssid: bssid ?? this.bssid,
      building: building ?? this.building,
      floor: floor ?? this.floor,
      location: location ?? this.location,
      signalStrengthThreshold: signalStrengthThreshold ?? this.signalStrengthThreshold,
      sameFloorMinSignal: sameFloorMinSignal ?? this.sameFloorMinSignal,
      differentFloorMaxSignal: differentFloorMaxSignal ?? this.differentFloorMaxSignal,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

