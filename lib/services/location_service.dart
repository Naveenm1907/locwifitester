import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wifi_scan/wifi_scan.dart';
import '../models/room.dart';
import '../models/wifi_router.dart';
import '../utils/coordinate_calculator.dart';

enum GPSAccuracyLevel {
  high,
  medium,
  low,
}

class LocationResult {
  final bool isWithinRoom;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final GPSAccuracyLevel locationAccuracy;
  final List<WiFiAccessPoint>? detectedWifiSignals;
  final bool wifiVerified;
  final bool floorVerified;
  final int? detectedSignalStrength;
  final String? floorVerificationReason;
  final String? message;

  LocationResult({
    required this.isWithinRoom,
    this.latitude,
    this.longitude,
    this.accuracy,
    required this.locationAccuracy,
    this.detectedWifiSignals,
    this.wifiVerified = false,
    this.floorVerified = true, // Default to true if no WiFi configured
    this.detectedSignalStrength,
    this.floorVerificationReason,
    this.message,
  });
}

class LocationService {
  static final LocationService instance = LocationService._init();
  LocationService._init();

  // Accuracy thresholds in meters
  static const double highAccuracyThreshold = 10.0;
  static const double mediumAccuracyThreshold = 30.0;

  // GPS timeout settings
  static const Duration gpsTimeout = Duration(seconds: 15);
  static const Duration gpsCheckInterval = Duration(seconds: 2);

  /// Check if location permissions are granted
  Future<bool> checkPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check if WiFi scanning is available
  Future<bool> canScanWiFi() async {
    final can = await WiFiScan.instance.canGetScannedResults();
    return can == CanGetScannedResults.yes;
  }

  /// Get current location with retry mechanism
  Future<Position?> getCurrentLocation({
    int maxAttempts = 5,
    Duration timeLimit = gpsTimeout,
  }) async {
    Position? bestPosition;
    double bestAccuracy = double.infinity;

    try {
      final endTime = DateTime.now().add(timeLimit);

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (DateTime.now().isAfter(endTime)) {
          break;
        }

        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: gpsCheckInterval,
          );

          // Keep track of the most accurate position
          if (position.accuracy < bestAccuracy) {
            bestAccuracy = position.accuracy;
            bestPosition = position;
          }

          // If we have high accuracy, stop early
          if (position.accuracy <= highAccuracyThreshold) {
            return position;
          }
        } catch (e) {
          // Continue trying if we haven't reached max attempts
          if (attempt < maxAttempts - 1) {
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
        }
      }

      return bestPosition;
    } catch (e) {
      // Error getting location
      return null;
    }
  }

  /// Scan for WiFi networks
  Future<List<WiFiAccessPoint>> scanWiFiNetworks() async {
    try {
      // Check if we can get scan results
      final can = await WiFiScan.instance.canGetScannedResults();
      if (can != CanGetScannedResults.yes) {
        // Try to start scan if we can't get results yet
        final canStart = await WiFiScan.instance.canStartScan();
        if (canStart == CanStartScan.yes) {
          await WiFiScan.instance.startScan();
          // Wait a bit for scan to complete
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      // Get scan results
      final results = await WiFiScan.instance.getScannedResults();
      return results;
    } catch (e) {
      // Error scanning WiFi
      return [];
    }
  }

  /// Verify if user is in the room using GPS and WiFi
  /// System works offline - WiFi scanning doesn't require internet
  Future<LocationResult> verifyLocation({
    required Room room,
    WiFiRouter? assignedWifi,
  }) async {
    // Step 1: If WiFi is configured, try WiFi-first approach (works offline)
    if (assignedWifi != null) {
      final wifiResults = await scanWiFiNetworks();
      
      // Check if the specific configured WiFi is detected
      final isConfiguredWifiDetected = _verifyWiFiPresence(wifiResults, assignedWifi);
      
      if (isConfiguredWifiDetected) {
        // WiFi detected! Now verify floor using signal strength
        final floorCheck = _verifyFloorBySignalStrength(wifiResults, assignedWifi, room.floor);
        
        if (floorCheck['verified']) {
          // Floor matches! Try to get GPS for additional confirmation
          final position = await getCurrentLocation(maxAttempts: 3, timeLimit: const Duration(seconds: 10));
          
          // Only include the configured WiFi router signal, not all networks
          final configuredWifiSignal = _findConfiguredWifiSignal(wifiResults, assignedWifi);
          
          return LocationResult(
            isWithinRoom: true,
            latitude: position?.latitude,
            longitude: position?.longitude,
            accuracy: position?.accuracy,
            locationAccuracy: position != null ? _determineAccuracy(position.accuracy) : GPSAccuracyLevel.low,
            detectedWifiSignals: configuredWifiSignal != null ? [configuredWifiSignal] : null,
            wifiVerified: true,
            floorVerified: true,
            detectedSignalStrength: floorCheck['signalStrength'],
            floorVerificationReason: floorCheck['reason'],
            message: '✓ Verified via WiFi floor detection${position != null ? " + GPS" : " (offline mode)"}',
          );
        } else {
          // Floor doesn't match - reject
          // Only include the configured WiFi router signal
          final configuredWifiSignal = _findConfiguredWifiSignal(wifiResults, assignedWifi);
          
          return LocationResult(
            isWithinRoom: false,
            locationAccuracy: GPSAccuracyLevel.low,
            detectedWifiSignals: configuredWifiSignal != null ? [configuredWifiSignal] : null,
            wifiVerified: true,
            floorVerified: false,
            detectedSignalStrength: floorCheck['signalStrength'],
            floorVerificationReason: floorCheck['reason'],
            message: '❌ FLOOR MISMATCH: ${floorCheck['reason']}',
          );
        }
      }
    }
    
    // Step 2: Try GPS verification (fallback or when no WiFi configured)
    final position = await getCurrentLocation();
    
    if (position != null) {
      final accuracy = _determineAccuracy(position.accuracy);
      
      // Use exact room boundaries - no safety margin for attendance
      final isInside = CoordinateCalculator.isPointInsideRoom(
        position.latitude,
        position.longitude,
        room.coordinates,
      );

      // If GPS is highly accurate and confirms location, check floor if WiFi available
      if (accuracy == GPSAccuracyLevel.high && isInside) {
        // Check floor using WiFi signal strength if router is assigned
        if (assignedWifi != null) {
          final wifiResults = await scanWiFiNetworks();
          if (wifiResults.isNotEmpty) {
            final floorCheck = _verifyFloorBySignalStrength(wifiResults, assignedWifi, room.floor);
            
            // Only include the configured WiFi router signal
            final configuredWifiSignal = _findConfiguredWifiSignal(wifiResults, assignedWifi);
            
            // Reject if floor doesn't match
            if (!floorCheck['verified']) {
              return LocationResult(
                isWithinRoom: false,
                latitude: position.latitude,
                longitude: position.longitude,
                accuracy: position.accuracy,
                locationAccuracy: accuracy,
                detectedWifiSignals: configuredWifiSignal != null ? [configuredWifiSignal] : null,
                wifiVerified: true,
                floorVerified: false,
                detectedSignalStrength: floorCheck['signalStrength'],
                floorVerificationReason: floorCheck['reason'],
                message: '❌ FLOOR MISMATCH: ${floorCheck['reason']}',
              );
            }
            
            // Floor verified!
            return LocationResult(
              isWithinRoom: true,
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
              locationAccuracy: accuracy,
              detectedWifiSignals: configuredWifiSignal != null ? [configuredWifiSignal] : null,
              wifiVerified: true,
              floorVerified: true,
              detectedSignalStrength: floorCheck['signalStrength'],
              floorVerificationReason: floorCheck['reason'],
              message: '✓ Location verified via GPS + WiFi Floor Detection',
            );
          }
        }
        
        // No WiFi configured or not detected - GPS only
        return LocationResult(
          isWithinRoom: true,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          locationAccuracy: accuracy,
          message: 'Location verified via GPS',
        );
      }

      // If GPS shows user is inside but accuracy is medium, check floor with WiFi
      if (isInside && accuracy == GPSAccuracyLevel.medium) {
        // Check floor using WiFi signal strength if router is assigned
        if (assignedWifi != null) {
          final wifiResults = await scanWiFiNetworks();
          if (wifiResults.isNotEmpty) {
            final floorCheck = _verifyFloorBySignalStrength(wifiResults, assignedWifi, room.floor);
            
            // Only include the configured WiFi router signal
            final configuredWifiSignal = _findConfiguredWifiSignal(wifiResults, assignedWifi);
            
            // Reject if floor doesn't match
            if (!floorCheck['verified']) {
              return LocationResult(
                isWithinRoom: false,
                latitude: position.latitude,
                longitude: position.longitude,
                accuracy: position.accuracy,
                locationAccuracy: accuracy,
                detectedWifiSignals: configuredWifiSignal != null ? [configuredWifiSignal] : null,
                wifiVerified: true,
                floorVerified: false,
                detectedSignalStrength: floorCheck['signalStrength'],
                floorVerificationReason: floorCheck['reason'],
                message: '❌ FLOOR MISMATCH: ${floorCheck['reason']}',
              );
            }
            
            // Floor verified!
            return LocationResult(
              isWithinRoom: true,
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
              locationAccuracy: accuracy,
              detectedWifiSignals: configuredWifiSignal != null ? [configuredWifiSignal] : null,
              wifiVerified: true,
              floorVerified: true,
              detectedSignalStrength: floorCheck['signalStrength'],
              floorVerificationReason: floorCheck['reason'],
              message: '✓ Location verified (GPS + WiFi Floor Check)',
            );
          }
        }
        
        // No WiFi configured or not detected - GPS only
        return LocationResult(
          isWithinRoom: true,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          locationAccuracy: accuracy,
          message: 'Location verified via GPS (medium accuracy)',
        );
      }

      // If GPS shows user is inside but accuracy is low, require WiFi floor check
      if (isInside && accuracy == GPSAccuracyLevel.low) {
        // REQUIRE WiFi floor check for low GPS accuracy
        if (assignedWifi != null) {
          final wifiResults = await scanWiFiNetworks();
          if (wifiResults.isNotEmpty) {
            final floorCheck = _verifyFloorBySignalStrength(wifiResults, assignedWifi, room.floor);
            
            // Only include the configured WiFi router signal
            final configuredWifiSignal = _findConfiguredWifiSignal(wifiResults, assignedWifi);
            
            // Reject if floor doesn't match
            if (!floorCheck['verified']) {
              return LocationResult(
                isWithinRoom: false,
                latitude: position.latitude,
                longitude: position.longitude,
                accuracy: position.accuracy,
                locationAccuracy: accuracy,
                detectedWifiSignals: configuredWifiSignal != null ? [configuredWifiSignal] : null,
                wifiVerified: true,
                floorVerified: false,
                detectedSignalStrength: floorCheck['signalStrength'],
                floorVerificationReason: floorCheck['reason'],
                message: '❌ FLOOR MISMATCH: ${floorCheck['reason']}',
              );
            }
            
            // Floor verified!
            return LocationResult(
              isWithinRoom: true,
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
              locationAccuracy: accuracy,
              detectedWifiSignals: configuredWifiSignal != null ? [configuredWifiSignal] : null,
              wifiVerified: true,
              floorVerified: true,
              detectedSignalStrength: floorCheck['signalStrength'],
              floorVerificationReason: floorCheck['reason'],
              message: '✓ Location verified (GPS + WiFi Floor Check)',
            );
          }
        }
        
        // No WiFi configured or not detected - Accept with warning
        return LocationResult(
          isWithinRoom: true,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          locationAccuracy: accuracy,
          message: 'Location verified via GPS only (low accuracy, WiFi recommended)',
        );
      }

      // If GPS shows user is NOT inside, try WiFi fallback
      if (!isInside) {
        if (assignedWifi != null) {
          final wifiResults = await scanWiFiNetworks();
          debugPrint('GPS indicates outside. Scanning WiFi... Found ${wifiResults.length} networks');
          
          // Check if configured WiFi is detected (without threshold check for fallback)
          final configuredWifiSignal = _findConfiguredWifiSignal(wifiResults, assignedWifi);
          
          if (configuredWifiSignal != null) {
            // WiFi detected! Verify floor with signal strength
            final floorCheck = _verifyFloorBySignalStrength(wifiResults, assignedWifi, room.floor);
            
            // If floor matches, accept it even though GPS says outside (GPS can be inaccurate indoors)
            if (floorCheck['verified']) {
              debugPrint('WiFi verified with floor check. Signal: ${configuredWifiSignal.level} dBm');
              return LocationResult(
                isWithinRoom: true,
                latitude: position.latitude,
                longitude: position.longitude,
                accuracy: position.accuracy,
                locationAccuracy: accuracy,
                detectedWifiSignals: [configuredWifiSignal],
                wifiVerified: true,
                floorVerified: true,
                detectedSignalStrength: floorCheck['signalStrength'],
                floorVerificationReason: floorCheck['reason'],
                message: '✓ Location verified via WiFi floor detection (GPS inaccurate indoors)',
              );
            } else {
              debugPrint('WiFi detected but floor mismatch: ${floorCheck['reason']}');
              return LocationResult(
                isWithinRoom: false,
                latitude: position.latitude,
                longitude: position.longitude,
                accuracy: position.accuracy,
                locationAccuracy: accuracy,
                detectedWifiSignals: [configuredWifiSignal],
                wifiVerified: true,
                floorVerified: false,
                detectedSignalStrength: floorCheck['signalStrength'],
                floorVerificationReason: floorCheck['reason'],
                message: 'Floor mismatch: ${floorCheck['reason']}',
              );
            }
          } else {
            // WiFi not detected - likely wrong floor or router out of range
            debugPrint('Configured WiFi not detected. Expected: ${assignedWifi.ssid} (${assignedWifi.bssid})');
            return LocationResult(
              isWithinRoom: false,
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
              locationAccuracy: accuracy,
              detectedWifiSignals: null,
              wifiVerified: false,
              message: 'Please go to Floor ${room.floor} where the router "${assignedWifi.ssid}" is located.',
            );
          }
        }

        return LocationResult(
          isWithinRoom: false,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          locationAccuracy: accuracy,
          message: 'GPS indicates you are not in the room. WiFi verification not available (no router configured).',
        );
      }
    }

    // Step 2: GPS completely failed, try WiFi-only verification
    if (assignedWifi != null) {
      final wifiResults = await scanWiFiNetworks();
      debugPrint('GPS unavailable. Trying WiFi-only verification. Found ${wifiResults.length} networks');
      
      // Check if configured WiFi is detected
      final configuredWifiSignal = _findConfiguredWifiSignal(wifiResults, assignedWifi);
      
      if (configuredWifiSignal != null) {
        // WiFi detected! Verify floor with signal strength
        final floorCheck = _verifyFloorBySignalStrength(wifiResults, assignedWifi, room.floor);
        
        if (floorCheck['verified']) {
          debugPrint('WiFi-only verification successful. Signal: ${configuredWifiSignal.level} dBm');
          return LocationResult(
            isWithinRoom: true,
            locationAccuracy: GPSAccuracyLevel.low,
            detectedWifiSignals: [configuredWifiSignal],
            wifiVerified: true,
            floorVerified: true,
            detectedSignalStrength: floorCheck['signalStrength'],
            floorVerificationReason: floorCheck['reason'],
            message: '✓ Location verified via WiFi floor detection (GPS unavailable)',
          );
        } else {
          debugPrint('WiFi detected but floor mismatch: ${floorCheck['reason']}');
          return LocationResult(
            isWithinRoom: false,
            locationAccuracy: GPSAccuracyLevel.low,
            detectedWifiSignals: [configuredWifiSignal],
            wifiVerified: true,
            floorVerified: false,
            detectedSignalStrength: floorCheck['signalStrength'],
            floorVerificationReason: floorCheck['reason'],
            message: '❌ WiFi detected but floor mismatch: ${floorCheck['reason']}',
          );
        }
      } else {
        debugPrint('Configured WiFi not detected. Expected: ${assignedWifi.ssid} (${assignedWifi.bssid})');
        return LocationResult(
          isWithinRoom: false,
          locationAccuracy: GPSAccuracyLevel.low,
          detectedWifiSignals: null,
          wifiVerified: false,
          message: 'Please go to Floor ${room.floor} where the router "${assignedWifi.ssid}" is located.',
        );
      }
    }

    // Complete failure
    return LocationResult(
      isWithinRoom: false,
      locationAccuracy: GPSAccuracyLevel.low,
      message: 'Location verification failed. GPS unavailable and no WiFi configured',
    );
  }

  /// Determine location accuracy level
  GPSAccuracyLevel _determineAccuracy(double accuracyMeters) {
    if (accuracyMeters <= highAccuracyThreshold) {
      return GPSAccuracyLevel.high;
    } else if (accuracyMeters <= mediumAccuracyThreshold) {
      return GPSAccuracyLevel.medium;
    } else {
      return GPSAccuracyLevel.low;
    }
  }

  /// Verify if the assigned WiFi is present in scan results
  bool _verifyWiFiPresence(
    List<WiFiAccessPoint> scanResults,
    WiFiRouter assignedWifi,
  ) {
    for (var ap in scanResults) {
      // Match by BSSID (most reliable) - case insensitive
      final apBssid = ap.bssid.toLowerCase().trim();
      final routerBssid = assignedWifi.bssid.toLowerCase().trim();
      
      if (apBssid == routerBssid) {
        // If signal is detected, accept it even if below threshold
        // Threshold check is done in floor verification
        // This allows WiFi to be used as fallback when GPS fails
        debugPrint('WiFi router detected: ${assignedWifi.ssid} at ${ap.level} dBm (threshold: ${assignedWifi.signalStrengthThreshold} dBm)');
        return true;
      }
      
      // Also check SSID as fallback (in case BSSID has formatting differences)
      final apSsid = ap.ssid.toLowerCase().trim();
      final routerSsid = assignedWifi.ssid.toLowerCase().trim();
      
      if (apSsid == routerSsid && apSsid.isNotEmpty) {
        debugPrint('WiFi router detected by SSID: ${assignedWifi.ssid} at ${ap.level} dBm');
        return true;
      }
    }
    
    debugPrint('WiFi router not found. Looking for BSSID: ${assignedWifi.bssid}, SSID: ${assignedWifi.ssid}');
    debugPrint('Detected networks: ${scanResults.map((ap) => '${ap.ssid} (${ap.bssid})').join(", ")}');
    
    // Log floor information for debugging
    if (scanResults.isNotEmpty) {
      debugPrint('Note: Room router is on Floor ${assignedWifi.floor}, but you may be on a different floor.');
      debugPrint('Detected networks are likely from your current floor.');
    }
    
    return false;
  }

  /// Verify floor based on WiFi signal strength
  /// Returns Map with: verified (bool), signalStrength (int), reason (String)
  Map<String, dynamic> _verifyFloorBySignalStrength(
    List<WiFiAccessPoint> scanResults,
    WiFiRouter assignedWifi,
    int expectedFloor,
  ) {
    // Find the assigned WiFi router's signal
    WiFiAccessPoint? detectedRouter;
    
    for (var ap in scanResults) {
      if (ap.bssid.toLowerCase() == assignedWifi.bssid.toLowerCase()) {
        detectedRouter = ap;
        break;
      }
    }

    // WiFi not detected at all
    if (detectedRouter == null) {
      return {
        'verified': false,
        'signalStrength': null,
        'reason': 'WiFi router not detected',
      };
    }

    final signalStrength = detectedRouter.level;

    // STRONG SIGNAL: >= sameFloorMinSignal (e.g., -55 dBm)
    // User is definitely on the same floor as the router
    if (signalStrength >= assignedWifi.sameFloorMinSignal) {
      if (assignedWifi.floor == expectedFloor) {
        return {
          'verified': true,
          'signalStrength': signalStrength,
          'reason': 'Strong signal ($signalStrength dBm) confirms Floor ${assignedWifi.floor}',
        };
      } else {
        return {
          'verified': false,
          'signalStrength': signalStrength,
          'reason': 'Strong signal ($signalStrength dBm) indicates Floor ${assignedWifi.floor}, but room is on Floor $expectedFloor',
        };
      }
    }

    // WEAK SIGNAL: <= differentFloorMaxSignal (e.g., -75 dBm)
    // Signal is too weak - user is likely on a different floor
    if (signalStrength <= assignedWifi.differentFloorMaxSignal) {
      return {
        'verified': false,
        'signalStrength': signalStrength,
        'reason': 'Weak signal ($signalStrength dBm) suggests you are on a different floor. Expected Floor $expectedFloor.',
      };
    }

    // MEDIUM SIGNAL: Between -75 and -55 dBm
    // Ambiguous - could be same floor (far from router) or different floor (close to it)
    // In this case, we'll be lenient and allow if room's floor matches router's floor
    if (assignedWifi.floor == expectedFloor) {
      return {
        'verified': true,
        'signalStrength': signalStrength,
        'reason': 'Medium signal ($signalStrength dBm) on Floor ${expectedFloor} (acceptable)',
      };
    } else {
      return {
        'verified': false,
        'signalStrength': signalStrength,
        'reason': 'Signal strength ($signalStrength dBm) is ambiguous. Room is on Floor $expectedFloor, but router is on Floor ${assignedWifi.floor}.',
      };
    }
  }

  /// Find the configured WiFi router's signal from scan results
  /// Returns only the configured router's signal, not other networks
  WiFiAccessPoint? _findConfiguredWifiSignal(
    List<WiFiAccessPoint> scanResults,
    WiFiRouter assignedWifi,
  ) {
    final routerBssid = assignedWifi.bssid.toLowerCase().trim();
    final routerSsid = assignedWifi.ssid.toLowerCase().trim();
    
    for (var ap in scanResults) {
      final apBssid = ap.bssid.toLowerCase().trim();
      final apSsid = ap.ssid.toLowerCase().trim();
      
      // Match by BSSID (most reliable)
      if (apBssid == routerBssid) {
        debugPrint('Found configured router by BSSID: ${ap.ssid} at ${ap.level} dBm');
        return ap;
      }
      
      // Fallback: Match by SSID if BSSID doesn't match (in case of formatting differences)
      if (apSsid == routerSsid && apSsid.isNotEmpty) {
        debugPrint('Found configured router by SSID: ${ap.ssid} at ${ap.level} dBm (BSSID mismatch: expected $routerBssid, got $apBssid)');
        return ap;
      }
    }
    
    debugPrint('Configured router not found. Looking for BSSID: $routerBssid or SSID: $routerSsid');
    return null;
  }

  /// Get the strongest WiFi signal from scan results
  WiFiAccessPoint? getStrongestSignal(List<WiFiAccessPoint> scanResults) {
    if (scanResults.isEmpty) return null;

    WiFiAccessPoint strongest = scanResults.first;
    for (var ap in scanResults) {
      if (ap.level > strongest.level) {
        strongest = ap;
      }
    }
    return strongest;
  }

  /// Stream location updates for real-time tracking
  Stream<Position> getLocationStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // Update every 5 meters
      ),
    );
  }

  /// Calculate distance from room center
  double getDistanceFromRoom(Position position, Room room) {
    return CoordinateCalculator.calculateDistance(
      position.latitude,
      position.longitude,
      room.centerLatitude,
      room.centerLongitude,
    );
  }

  /// Open location settings
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Open app settings
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }
}

