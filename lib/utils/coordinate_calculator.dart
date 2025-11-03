import 'dart:math';
import '../models/room.dart';

/// Utility class to calculate room boundary coordinates based on center point and dimensions
class CoordinateCalculator {
  // Earth's radius in meters
  static const double earthRadius = 6378137.0;

  /// Calculate the four corner coordinates of a room given its center and dimensions
  /// 
  /// [centerLat] - Latitude of the room center
  /// [centerLng] - Longitude of the room center
  /// [widthMeters] - Width of the room in meters (East-West direction)
  /// [lengthMeters] - Length of the room in meters (North-South direction)
  /// 
  /// Returns a [RoomCoordinates] object with all four corners
  static RoomCoordinates calculateRoomCoordinates({
    required double centerLat,
    required double centerLng,
    required double widthMeters,
    required double lengthMeters,
  }) {
    // Calculate half dimensions
    final halfWidth = widthMeters / 2;
    final halfLength = lengthMeters / 2;

    // Calculate offsets in degrees
    final latOffset = _metersToLatitude(halfLength);
    final lngOffset = _metersToLongitude(halfWidth, centerLat);

    // Calculate four corners
    final northEast = GeoPoint(
      centerLat + latOffset,
      centerLng + lngOffset,
    );

    final northWest = GeoPoint(
      centerLat + latOffset,
      centerLng - lngOffset,
    );

    final southEast = GeoPoint(
      centerLat - latOffset,
      centerLng + lngOffset,
    );

    final southWest = GeoPoint(
      centerLat - latOffset,
      centerLng - lngOffset,
    );

    return RoomCoordinates(
      northEast: northEast,
      northWest: northWest,
      southEast: southEast,
      southWest: southWest,
    );
  }

  /// Convert meters to latitude degrees
  static double _metersToLatitude(double meters) {
    return meters / earthRadius * (180 / pi);
  }

  /// Convert meters to longitude degrees at a given latitude
  static double _metersToLongitude(double meters, double latitude) {
    final radiusAtLatitude = earthRadius * cos(latitude * pi / 180);
    return meters / radiusAtLatitude * (180 / pi);
  }

  /// Calculate distance between two points using Haversine formula
  /// Returns distance in meters
  static double calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Check if a point is inside a room's boundaries using ray casting algorithm
  /// 
  /// [lat] - Latitude of the point to check
  /// [lng] - Longitude of the point to check
  /// [coordinates] - Room boundary coordinates
  /// 
  /// Returns true if the point is inside the room
  static bool isPointInsideRoom(
    double lat,
    double lng,
    RoomCoordinates coordinates,
  ) {
    // Create polygon from room coordinates (in clockwise order)
    final polygon = [
      coordinates.northWest,
      coordinates.northEast,
      coordinates.southEast,
      coordinates.southWest,
    ];

    return _isPointInPolygon(lat, lng, polygon);
  }

  /// Ray casting algorithm to determine if a point is inside a polygon
  static bool _isPointInPolygon(
    double lat,
    double lng,
    List<GeoPoint> polygon,
  ) {
    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      if (((polygon[i].latitude > lat) != (polygon[j].latitude > lat)) &&
          (lng <
              (polygon[j].longitude - polygon[i].longitude) *
                      (lat - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude)) {
        inside = !inside;
      }
      j = i;
    }

    return inside;
  }

  /// Calculate the center point of the room from its boundaries
  static GeoPoint calculateCenter(RoomCoordinates coordinates) {
    final centerLat = (coordinates.northEast.latitude +
            coordinates.northWest.latitude +
            coordinates.southEast.latitude +
            coordinates.southWest.latitude) /
        4;

    final centerLng = (coordinates.northEast.longitude +
            coordinates.northWest.longitude +
            coordinates.southEast.longitude +
            coordinates.southWest.longitude) /
        4;

    return GeoPoint(centerLat, centerLng);
  }

  /// Add a safety margin to room boundaries for better detection
  /// Returns new coordinates with expanded boundaries
  static RoomCoordinates expandBoundaries(
    RoomCoordinates coordinates,
    double marginMeters,
  ) {
    final center = calculateCenter(coordinates);
    
    // Calculate current dimensions
    final width = calculateDistance(
      coordinates.northWest.latitude,
      coordinates.northWest.longitude,
      coordinates.northEast.latitude,
      coordinates.northEast.longitude,
    );
    
    final length = calculateDistance(
      coordinates.northEast.latitude,
      coordinates.northEast.longitude,
      coordinates.southEast.latitude,
      coordinates.southEast.longitude,
    );

    // Add margin to both dimensions
    return calculateRoomCoordinates(
      centerLat: center.latitude,
      centerLng: center.longitude,
      widthMeters: width + (marginMeters * 2),
      lengthMeters: length + (marginMeters * 2),
    );
  }
}

