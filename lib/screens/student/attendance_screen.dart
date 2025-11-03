import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:wifi_scan/wifi_scan.dart';
import '../../models/room.dart';
import '../../models/wifi_router.dart';
import '../../models/attendance.dart';
import '../../providers/app_state.dart';
import '../../services/location_service.dart';
import '../../services/firebase_service.dart';
import '../../widgets/student_location_map.dart';

enum VerificationState {
  initial,
  checkingPermissions,
  verifyingLocation,
  success,
  failed,
  alreadyMarked,
}

class AttendanceScreen extends StatefulWidget {
  final Room room;

  const AttendanceScreen({super.key, required this.room});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  VerificationState _state = VerificationState.initial;
  WiFiRouter? _assignedWifi;
  String? _statusMessage;
  double? _latitude;
  double? _longitude;
  double? _accuracy;
  List<WiFiAccessPoint>? _detectedWifi;
  int _secondsRemaining = 15;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _checkExistingAttendance();
    _loadWiFiRouter();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkExistingAttendance() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUser?.id;
    
    if (userId != null) {
      final existing = await FirebaseService.instance.getTodayAttendance(
        userId,
        widget.room.id,
      );
      
      if (existing != null && mounted) {
        setState(() {
          _state = VerificationState.alreadyMarked;
          _statusMessage = 'You have already marked attendance for this room today';
        });
      }
    }
  }

  Future<void> _loadWiFiRouter() async {
    if (widget.room.assignedWifiId != null) {
      final router = await FirebaseService.instance.getWiFiRouter(
        widget.room.assignedWifiId!,
      );
      
      if (router != null && mounted) {
        setState(() {
          _assignedWifi = router;
        });
      }
    }
  }

  Future<void> _startVerification() async {
    try {
      setState(() {
        _state = VerificationState.checkingPermissions;
        _statusMessage = 'Checking permissions...';
        _secondsRemaining = 15;
      });

      final locationService = LocationService.instance;

      // Check permissions
      final hasPermission = await locationService.checkPermissions();
      if (!hasPermission) {
        if (mounted) {
          setState(() {
            _state = VerificationState.failed;
            _statusMessage = 'Location permission denied. Please enable it in settings.';
          });
        }
        return;
      }

      // Check if location services are enabled
      final isEnabled = await locationService.isLocationServiceEnabled();
      if (!isEnabled) {
        if (mounted) {
          setState(() {
            _state = VerificationState.failed;
            _statusMessage = 'Location services are disabled. Please enable them.';
          });
        }
        return;
      }

      // Start verification
      if (mounted) {
        setState(() {
          _state = VerificationState.verifyingLocation;
          _statusMessage = 'Verifying your location...';
        });
      }

      // Start countdown timer
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _secondsRemaining > 0) {
          setState(() {
            _secondsRemaining--;
          });
        } else {
          timer.cancel();
        }
      });

      // Verify location with timeout
      final result = await locationService.verifyLocation(
        room: widget.room,
        assignedWifi: _assignedWifi,
      ).timeout(
        const Duration(seconds: 20), // 20 second hard timeout
        onTimeout: () {
          // Return a failed result on timeout
          return LocationResult(
            isWithinRoom: false,
            locationAccuracy: GPSAccuracyLevel.low,
            message: 'Verification timed out. Please try again or move to a location with better GPS signal.',
          );
        },
      );

      _countdownTimer?.cancel();

      if (!mounted) return;

      setState(() {
        _latitude = result.latitude;
        _longitude = result.longitude;
        _accuracy = result.accuracy;
        _detectedWifi = result.detectedWifiSignals;
      });

      if (result.isWithinRoom) {
        await _markAttendance(result);
        if (mounted) {
          setState(() {
            _state = VerificationState.success;
            _statusMessage = result.message ?? 'Attendance marked successfully!';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _state = VerificationState.failed;
            _statusMessage = result.message ?? 'Location verification failed. Please ensure you are inside the classroom.';
          });
        }
      }
    } catch (e) {
      // Handle any unexpected errors
      _countdownTimer?.cancel();
      
      if (mounted) {
        setState(() {
          _state = VerificationState.failed;
          _statusMessage = 'An error occurred during verification: ${e.toString()}\n\nPlease try again.';
        });
      }
    }
  }

  Future<void> _markAttendance(result) async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUser?.id;

      if (userId == null) {
        throw Exception('User not logged in');
      }

      LocationVerificationMethod method;
      if (result.latitude != null && result.wifiVerified) {
        method = LocationVerificationMethod.both;
      } else if (result.wifiVerified) {
        method = LocationVerificationMethod.wifi;
      } else {
        method = LocationVerificationMethod.gps;
      }

      final attendance = Attendance(
        id: const Uuid().v4(),
        userId: userId,
        roomId: widget.room.id,
        timestamp: DateTime.now(),
        status: AttendanceStatus.present,
        verificationMethod: method,
        latitude: result.latitude,
        longitude: result.longitude,
        accuracy: result.accuracy,
        // Only store the configured WiFi router's BSSID if detected
        detectedWifiSignals: result.detectedWifiSignals?.map((ap) => ap.bssid).toList(),
        // Use the signal strength from the configured router
        strongestSignalStrength: result.detectedSignalStrength,
        isVerified: true,
        createdAt: DateTime.now(),
      );

      await FirebaseService.instance.createAttendance(attendance);
    } catch (e) {
      // Log error but don't fail the whole process
      debugPrint('Error marking attendance: $e');
      // Could show a warning that attendance was verified but not saved
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.room.name),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRoomInfoCard(),
            const SizedBox(height: 16),
            _buildStatusCard(),
            const SizedBox(height: 16),
            if (_state == VerificationState.verifyingLocation) _buildVerificationProgress(),
            if (_state == VerificationState.success) _buildSuccessDetails(),
            if (_state == VerificationState.failed) _buildFailureDetails(),
            const SizedBox(height: 24),
            _buildActionButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.meeting_room, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.room.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Building', widget.room.building),
            _buildInfoRow('Floor', 'Floor ${widget.room.floor}'),
            _buildInfoRow('Dimensions', '${widget.room.widthMeters}m × ${widget.room.lengthMeters}m'),
            if (_assignedWifi != null)
              _buildInfoRow('WiFi', _assignedWifi!.ssid, icon: Icons.wifi)
            else
              _buildInfoRow(
                'WiFi',
                'Not configured',
                icon: Icons.wifi_off,
                color: Colors.orange,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color ?? Colors.grey),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (_state) {
      case VerificationState.initial:
        backgroundColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        icon = Icons.info_outline;
        break;
      case VerificationState.checkingPermissions:
      case VerificationState.verifyingLocation:
        backgroundColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        icon = Icons.access_time;
        break;
      case VerificationState.success:
        backgroundColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        icon = Icons.check_circle;
        break;
      case VerificationState.failed:
        backgroundColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        icon = Icons.error_outline;
        break;
      case VerificationState.alreadyMarked:
        backgroundColor = Colors.amber.shade50;
        textColor = Colors.amber.shade900;
        icon = Icons.done_all;
        break;
    }

    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _statusMessage ?? 'Ready to mark attendance',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationProgress() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      strokeWidth: 8,
                      value: _secondsRemaining > 0 ? (_secondsRemaining / 15) : null,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _secondsRemaining > 5 
                            ? Colors.blue.shade400 
                            : Colors.orange.shade400,
                      ),
                    ),
                  ),
                  Text(
                    '$_secondsRemaining',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _secondsRemaining > 5 
                          ? Colors.blue.shade700 
                          : Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _secondsRemaining > 0 ? 'Verifying Location' : 'Finalizing...',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _secondsRemaining > 5 
                  ? 'Please wait while we verify your location using GPS and WiFi signals'
                  : 'Almost done! Processing results...',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            if (_secondsRemaining <= 5 && _secondsRemaining > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(
                      'Taking longer than usual...',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verification Details',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_latitude != null && _longitude != null) ...[
              _buildDetailRow('GPS Location', 'Verified ✓', Colors.green),
              _buildDetailRow(
                'Coordinates',
                '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
              ),
              if (_accuracy != null)
                _buildDetailRow('Accuracy', '${_accuracy!.toStringAsFixed(1)}m'),
            ],
            // Floor verification status - MOST IMPORTANT!
            if (_assignedWifi != null && _detectedWifi != null && _detectedWifi!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.layers_outlined, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Floor ${widget.room.floor} Confirmed ✓',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    if (_statusMessage != null && _statusMessage!.contains('dBm')) ...[
                      const SizedBox(height: 4),
                      Text(
                        _statusMessage!.split(':').last.trim(),
                        style: TextStyle(fontSize: 12, color: Colors.green.shade600),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (_latitude != null && _longitude != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StudentLocationMap(
                          studentLatitude: _latitude!,
                          studentLongitude: _longitude!,
                          room: widget.room,
                          accuracy: _accuracy,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('View on Google Maps'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(12),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
            // Only show configured WiFi router signal strength
            if (_assignedWifi != null && 
                _detectedWifi != null && 
                _detectedWifi!.isNotEmpty &&
                _detectedWifi!.any((ap) => ap.bssid.toLowerCase() == _assignedWifi!.bssid.toLowerCase())) ...[
              const SizedBox(height: 8),
              _buildDetailRow(
                'WiFi Signal',
                _detectedWifi!.firstWhere(
                  (ap) => ap.bssid.toLowerCase() == _assignedWifi!.bssid.toLowerCase()
                ).level.toString() + ' dBm',
                Colors.blue,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFailureDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Troubleshooting',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Check if failure is due to floor mismatch or WiFi not detected on wrong floor
            if (_statusMessage != null && 
                (_statusMessage!.contains('FLOOR MISMATCH') || 
                 _statusMessage!.contains('Please go to Floor'))) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.layers_clear, color: Colors.red.shade700, size: 28),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'WRONG FLOOR DETECTED!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage!.split(':').last.trim(),
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📍 What to do:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text('1. Go to Floor ${widget.room.floor}', style: const TextStyle(fontSize: 13)),
                    const Text('2. Move closer to the room', style: TextStyle(fontSize: 13)),
                    const Text('3. Try marking attendance again', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ] else ...[
              _buildTroubleshootItem(
                'Make sure you are inside the classroom',
                Icons.location_on,
              ),
              _buildTroubleshootItem(
                'Ensure you are on Floor ${widget.room.floor}',
                Icons.layers,
              ),
              _buildTroubleshootItem(
                'Check if location services are enabled',
                Icons.gps_fixed,
              ),
              _buildTroubleshootItem(
                'Try moving closer to a window for better GPS signal',
                Icons.window,
              ),
              if (_assignedWifi != null)
                _buildTroubleshootItem(
                  'Ensure WiFi is turned on (no need to connect)',
                  Icons.wifi,
                ),
            ],
            if (_latitude != null && _longitude != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Debug Information',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Your Location',
                '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
              ),
              if (_accuracy != null)
                _buildDetailRow('GPS Accuracy', '${_accuracy!.toStringAsFixed(1)}m'),
              if (_assignedWifi != null && 
                  _detectedWifi != null && 
                  _detectedWifi!.isNotEmpty &&
                  _detectedWifi!.any((ap) => ap.bssid.toLowerCase() == _assignedWifi!.bssid.toLowerCase()))
                _buildDetailRow(
                  'WiFi Router',
                  '${_assignedWifi!.ssid} (${_detectedWifi!.firstWhere((ap) => ap.bssid.toLowerCase() == _assignedWifi!.bssid.toLowerCase()).level} dBm)',
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StudentLocationMap(
                          studentLatitude: _latitude!,
                          studentLongitude: _longitude!,
                          room: widget.room,
                          accuracy: _accuracy,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('View Location on Map'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTroubleshootItem(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (_state == VerificationState.alreadyMarked) {
      return ElevatedButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back),
        label: const Text('Go Back'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          backgroundColor: Colors.grey,
          foregroundColor: Colors.white,
        ),
      );
    }

    if (_state == VerificationState.success) {
      return ElevatedButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.check),
        label: const Text('Done'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      );
    }

    if (_state == VerificationState.verifyingLocation ||
        _state == VerificationState.checkingPermissions) {
      return const ElevatedButton(
        onPressed: null,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Verifying...'),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: _startVerification,
      icon: const Icon(Icons.location_searching),
      label: Text(
        _state == VerificationState.failed ? 'Try Again' : 'Mark Attendance',
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(16),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }
}

