class Room {
  final String id;
  final String name;
  final String building;
  final int floor;
  final double centerLatitude;
  final double centerLongitude;
  final double widthMeters; // Width of the room in meters
  final double lengthMeters; // Length of the room in meters
  final RoomCoordinates coordinates;
  final String? assignedWifiId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Room({
    required this.id,
    required this.name,
    required this.building,
    required this.floor,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.widthMeters,
    required this.lengthMeters,
    required this.coordinates,
    this.assignedWifiId,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'building': building,
      'floor': floor,
      'centerLatitude': centerLatitude,
      'centerLongitude': centerLongitude,
      'widthMeters': widthMeters,
      'lengthMeters': lengthMeters,
      'ne_lat': coordinates.northEast.latitude,
      'ne_lng': coordinates.northEast.longitude,
      'nw_lat': coordinates.northWest.latitude,
      'nw_lng': coordinates.northWest.longitude,
      'se_lat': coordinates.southEast.latitude,
      'se_lng': coordinates.southEast.longitude,
      'sw_lat': coordinates.southWest.latitude,
      'sw_lng': coordinates.southWest.longitude,
      'assignedWifiId': assignedWifiId,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory Room.fromMap(Map<String, dynamic> map) {
    return Room(
      id: map['id'],
      name: map['name'],
      building: map['building'],
      floor: map['floor'],
      centerLatitude: map['centerLatitude'],
      centerLongitude: map['centerLongitude'],
      widthMeters: map['widthMeters'],
      lengthMeters: map['lengthMeters'],
      coordinates: RoomCoordinates(
        northEast: GeoPoint(map['ne_lat'], map['ne_lng']),
        northWest: GeoPoint(map['nw_lat'], map['nw_lng']),
        southEast: GeoPoint(map['se_lat'], map['se_lng']),
        southWest: GeoPoint(map['sw_lat'], map['sw_lng']),
      ),
      assignedWifiId: map['assignedWifiId'],
      isActive: map['isActive'] == 1,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
    );
  }

  Room copyWith({
    String? id,
    String? name,
    String? building,
    int? floor,
    double? centerLatitude,
    double? centerLongitude,
    double? widthMeters,
    double? lengthMeters,
    RoomCoordinates? coordinates,
    String? assignedWifiId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      building: building ?? this.building,
      floor: floor ?? this.floor,
      centerLatitude: centerLatitude ?? this.centerLatitude,
      centerLongitude: centerLongitude ?? this.centerLongitude,
      widthMeters: widthMeters ?? this.widthMeters,
      lengthMeters: lengthMeters ?? this.lengthMeters,
      coordinates: coordinates ?? this.coordinates,
      assignedWifiId: assignedWifiId ?? this.assignedWifiId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class RoomCoordinates {
  final GeoPoint northEast;
  final GeoPoint northWest;
  final GeoPoint southEast;
  final GeoPoint southWest;

  RoomCoordinates({
    required this.northEast,
    required this.northWest,
    required this.southEast,
    required this.southWest,
  });
}

class GeoPoint {
  final double latitude;
  final double longitude;

  GeoPoint(this.latitude, this.longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

