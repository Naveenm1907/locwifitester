import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:wifi_scan/wifi_scan.dart';
import '../../models/room.dart';
import '../../providers/app_state.dart';
import '../../services/location_service.dart';
import '../../utils/coordinate_calculator.dart';
import '../../widgets/room_map_picker.dart';

class RoomSetupScreen extends StatefulWidget {
  final Room? roomToEdit;
  
  const RoomSetupScreen({super.key, this.roomToEdit});

  @override
  State<RoomSetupScreen> createState() => _RoomSetupScreenState();
}

class _RoomSetupScreenState extends State<RoomSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _buildingController = TextEditingController();
  final _floorController = TextEditingController();
  final _widthController = TextEditingController();
  final _lengthController = TextEditingController();

  double? _centerLatitude;
  double? _centerLongitude;
  double? _locationAccuracy;
  String? _selectedWifiId;
  bool _isGettingLocation = false;
  RoomCoordinates? _calculatedCoordinates;
  List<WiFiAccessPoint>? _detectedWifiNetworks;
  bool _useWifiAssist = false;

  @override
  void initState() {
    super.initState();
    // If editing, populate fields
    if (widget.roomToEdit != null) {
      _nameController.text = widget.roomToEdit!.name;
      _buildingController.text = widget.roomToEdit!.building;
      _floorController.text = widget.roomToEdit!.floor.toString();
      _widthController.text = widget.roomToEdit!.widthMeters.toString();
      _lengthController.text = widget.roomToEdit!.lengthMeters.toString();
      _centerLatitude = widget.roomToEdit!.centerLatitude;
      _centerLongitude = widget.roomToEdit!.centerLongitude;
      _selectedWifiId = widget.roomToEdit!.assignedWifiId;
      _calculatedCoordinates = widget.roomToEdit!.coordinates;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _buildingController.dispose();
    _floorController.dispose();
    _widthController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
    });

    final locationService = LocationService.instance;
    
    // Check permissions
    final hasPermission = await locationService.checkPermissions();
    if (!hasPermission) {
      if (mounted) {
        _showPermissionDialog();
      }
      setState(() {
        _isGettingLocation = false;
      });
      return;
    }

    // Check if location services are enabled
    final isEnabled = await locationService.isLocationServiceEnabled();
    if (!isEnabled) {
      if (mounted) {
        _showLocationServiceDialog();
      }
      setState(() {
        _isGettingLocation = false;
      });
      return;
    }

    // Show progress dialog
    if (mounted) {
      _showLocationProgressDialog();
    }

    // Get location with extended timeout for admin setup
    final position = await locationService.getCurrentLocation(
      maxAttempts: 8,  // More attempts for better accuracy
      timeLimit: const Duration(seconds: 30),  // Longer timeout
    );
    
    // Close progress dialog
    if (mounted) {
      Navigator.of(context).pop();
    }
    
    if (position != null) {
      setState(() {
        _centerLatitude = position.latitude;
        _centerLongitude = position.longitude;
        _locationAccuracy = position.accuracy;
        _isGettingLocation = false;
      });

      // Scan WiFi to improve accuracy if GPS is poor
      if (position.accuracy > 20) {
        await _scanWiFiForAccuracy();
      }

      // Calculate coordinates if width and length are provided
      _calculateCoordinates();

      if (mounted) {
        final accuracyLevel = position.accuracy <= 10 
            ? 'High' 
            : position.accuracy <= 30 
                ? 'Medium' 
                : 'Low';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Location captured successfully!\n'
              'Coordinates: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}\n'
              'Accuracy: ${position.accuracy.toStringAsFixed(2)}m ($accuracyLevel)',
            ),
            backgroundColor: position.accuracy <= 30 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      setState(() {
        _isGettingLocation = false;
      });
      
      if (mounted) {
        _showLocationFailedDialog();
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red),
            SizedBox(width: 8),
            Text('Permission Required'),
          ],
        ),
        content: const Text(
          'Location permission is required to capture room coordinates.\n\n'
          'Please grant location permission in the next screen to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await LocationService.instance.openAppSettings();
              // Ask user to try again after returning
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please try capturing location again after granting permission'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_disabled, color: Colors.orange),
            SizedBox(width: 8),
            Text('Location Service Disabled'),
          ],
        ),
        content: const Text(
          'Location services are turned off on your device.\n\n'
          'Please enable location services to capture GPS coordinates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await LocationService.instance.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showLocationProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text(
                'Acquiring GPS Location...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'This may take up to 30 seconds',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tips for better GPS:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    SizedBox(height: 4),
                    Text('• Move near a window', style: TextStyle(fontSize: 11)),
                    Text('• Make sure you\'re outdoors', style: TextStyle(fontSize: 11)),
                    Text('• Stay still during capture', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLocationFailedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Location Capture Failed'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Unable to acquire GPS location. This can happen due to:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildTroubleshootItem('Poor GPS signal (indoor location)'),
              _buildTroubleshootItem('Location services disabled'),
              _buildTroubleshootItem('Device in airplane mode'),
              _buildTroubleshootItem('GPS hardware issue'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 Solutions:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('1. Move near a window or go outdoors'),
                    Text('2. Check location services are ON'),
                    Text('3. Disable airplane mode'),
                    Text('4. Wait 1-2 minutes for GPS to warm up'),
                    Text('5. Try restarting the app'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _getCurrentLocation();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildTroubleshootItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 6, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Future<void> _scanWiFiForAccuracy() async {
    try {
      final locationService = LocationService.instance;
      final canScan = await locationService.canScanWiFi();
      
      if (canScan) {
        final networks = await locationService.scanWiFiNetworks();
        
        if (networks.isNotEmpty && mounted) {
          setState(() {
            _detectedWifiNetworks = networks;
            _useWifiAssist = true;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'WiFi detected: ${networks.length} networks found\n'
                'Room boundaries will be adjusted for better indoor accuracy',
              ),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      // WiFi scan failed, continue without it
    }
  }

  void _calculateCoordinates() {
    if (_centerLatitude == null || _centerLongitude == null) return;
    
    final widthText = _widthController.text.trim();
    final lengthText = _lengthController.text.trim();
    
    if (widthText.isEmpty || lengthText.isEmpty) return;

    try {
      final width = double.parse(widthText);
      final length = double.parse(lengthText);

      // Calculate base coordinates WITHOUT any safety margin
      // Attendance system must use exact room boundaries
      final coordinates = CoordinateCalculator.calculateRoomCoordinates(
        centerLat: _centerLatitude!,
        centerLng: _centerLongitude!,
        widthMeters: width,
        lengthMeters: length,
      );

      setState(() {
        _calculatedCoordinates = coordinates;
      });
    } catch (e) {
      // Invalid numbers, ignore
    }
  }

  Future<void> _saveRoom() async {
    if (!_formKey.currentState!.validate()) return;

    if (_centerLatitude == null || _centerLongitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture the room center location')),
      );
      return;
    }

    if (_calculatedCoordinates == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid width and length')),
      );
      return;
    }

    final isEditing = widget.roomToEdit != null;
    
    final room = Room(
      id: isEditing ? widget.roomToEdit!.id : const Uuid().v4(),
      name: _nameController.text.trim(),
      building: _buildingController.text.trim(),
      floor: int.parse(_floorController.text.trim()),
      centerLatitude: _centerLatitude!,
      centerLongitude: _centerLongitude!,
      widthMeters: double.parse(_widthController.text.trim()),
      lengthMeters: double.parse(_lengthController.text.trim()),
      coordinates: _calculatedCoordinates!,
      assignedWifiId: _selectedWifiId,
      createdAt: isEditing ? widget.roomToEdit!.createdAt : DateTime.now(),
      updatedAt: isEditing ? DateTime.now() : null,
    );

    final appState = Provider.of<AppState>(context, listen: false);
    final success = isEditing 
        ? await appState.updateRoom(room)
        : await appState.addRoom(room);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing ? 'Room updated successfully' : 'Room created successfully'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to ${isEditing ? 'update' : 'create'} room: ${appState.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomToEdit != null ? 'Edit Room' : 'Setup New Room'),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildInfoCard(),
            const SizedBox(height: 16),
            _buildBasicInfoSection(),
            const SizedBox(height: 16),
            _buildLocationSection(),
            const SizedBox(height: 16),
            _buildDimensionsSection(),
            const SizedBox(height: 16),
            _buildWiFiSection(),
            const SizedBox(height: 16),
            if (_calculatedCoordinates != null) _buildCoordinatesPreview(),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveRoom,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text(
                widget.roomToEdit != null ? 'Update Room' : 'Create Room',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Setup Instructions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Enter room details (name, building, floor)\n'
              '2. Get room center coordinates:\n'
              '   • Auto: Go outside/window and capture GPS\n'
              '   • Manual: Use Google Maps to get coordinates\n'
              '3. Measure room dimensions (width × length)\n'
              '4. System calculates all 4 corners automatically\n'
              '5. Assign WiFi router (recommended for accuracy)',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.green.shade700, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tip: You don\'t need to be inside the room to capture GPS. Just get the approximate center location!',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Basic Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Room Name',
                hintText: 'e.g., Room 101, Lab A, etc.',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.meeting_room),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter room name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _buildingController,
              decoration: const InputDecoration(
                labelText: 'Building Name',
                hintText: 'e.g., Main Building, Block A, etc.',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter building name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _floorController,
              decoration: const InputDecoration(
                labelText: 'Floor Number',
                hintText: 'e.g., 1, 2, 3, etc.',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.layers),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter floor number';
                }
                if (int.tryParse(value) == null) {
                  return 'Please enter a valid number';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Room Center Location',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Indoor GPS Issue? Read this!',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Capture GPS outside or near a window\n'
                    '• OR enter coordinates manually if known',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_centerLatitude != null && _centerLongitude != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Location Set',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _centerLatitude = null;
                              _centerLongitude = null;
                              _locationAccuracy = null;
                              _calculatedCoordinates = null;
                              _detectedWifiNetworks = null;
                              _useWifiAssist = false;
                            });
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Latitude: ${_centerLatitude!.toStringAsFixed(6)}'),
                    Text('Longitude: ${_centerLongitude!.toStringAsFixed(6)}'),
                    if (_locationAccuracy != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            _locationAccuracy! <= 10 
                                ? Icons.gps_fixed 
                                : _locationAccuracy! <= 30 
                                    ? Icons.gps_not_fixed 
                                    : Icons.gps_off,
                            size: 14,
                            color: _locationAccuracy! <= 10 
                                ? Colors.green 
                                : _locationAccuracy! <= 30 
                                    ? Colors.orange 
                                    : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'GPS Accuracy: ${_locationAccuracy!.toStringAsFixed(1)}m',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_useWifiAssist && _detectedWifiNetworks != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.wifi, size: 14, color: Colors.blue.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'WiFi Assist: ${_detectedWifiNetworks!.length} networks',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Google Maps Picker Button (Primary option)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openMapPicker(),
                icon: const Icon(Icons.map),
                label: const Text('Pick Location on Google Maps (Recommended)'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // OR divider
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),
            // Manual Entry Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showManualCoordinateEntry,
                icon: const Icon(Icons.edit_location_alt),
                label: const Text('Enter Coordinates Manually'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // OR divider
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),
            // Auto Capture (Last option)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isGettingLocation ? null : _getCurrentLocation,
                icon: _isGettingLocation
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(
                  _isGettingLocation ? 'Getting GPS...' : 'Try Auto GPS Capture',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMapPicker() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RoomMapPicker(
          initialLatitude: _centerLatitude,
          initialLongitude: _centerLongitude,
          onLocationSelected: (lat, lng) {
            setState(() {
              _centerLatitude = lat;
              _centerLongitude = lng;
              _locationAccuracy = 5.0; // Map selection assumed accurate
            });
            // Calculate coordinates if dimensions are available
            _calculateCoordinates();
          },
        ),
      ),
    ).then((_) {
      // When returning from map picker, recalculate if needed
      if (_centerLatitude != null && _centerLongitude != null) {
        _calculateCoordinates();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Location set from map!\n'
              'Lat: ${_centerLatitude!.toStringAsFixed(6)}, '
              'Lng: ${_centerLongitude!.toStringAsFixed(6)}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  void _showManualCoordinateEntry() {
    final latController = TextEditingController(
      text: _centerLatitude?.toStringAsFixed(6) ?? '',
    );
    final lngController = TextEditingController(
      text: _centerLongitude?.toStringAsFixed(6) ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_location_alt, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(child: Text('Enter Coordinates')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step-by-step guide
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.phone_android, color: Colors.blue, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Using Google Maps (Easy Method):',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Open Google Maps app\n'
                      '2. Search for your building/location\n'
                      '3. Long-press exactly on room center\n'
                      '4. A pin will drop - tap it\n'
                      '5. Coordinates appear at top (13.067439, 80.237617)\n'
                      '6. Tap to copy, paste below',
                      style: TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: Colors.green, size: 14),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Tip: Zoom in on the map for precise placement!',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Example box
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Example coordinates:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Latitude: 13.067439\nLongitude: 80.237617',
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Latitude field
              TextField(
                controller: latController,
                decoration: InputDecoration(
                  labelText: 'Latitude *',
                  hintText: '13.067439',
                  helperText: 'First number (between -90 and 90)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.north),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste, size: 20),
                    onPressed: () async {
                      // In a real app, you'd use clipboard package
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Paste the latitude value here'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    tooltip: 'Paste',
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              // Longitude field
              TextField(
                controller: lngController,
                decoration: InputDecoration(
                  labelText: 'Longitude *',
                  hintText: '80.237617',
                  helperText: 'Second number (between -180 and 180)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.east),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste, size: 20),
                    onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Paste the longitude value here'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    tooltip: 'Paste',
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final latText = latController.text.trim();
              final lngText = lngController.text.trim();

              if (latText.isEmpty || lngText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter both latitude and longitude'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              final lat = double.tryParse(latText);
              final lng = double.tryParse(lngText);

              if (lat == null || lng == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid number format. Use decimal numbers like 13.067439'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Validate coordinate ranges
              if (lat < -90 || lat > 90) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Latitude must be between -90 and 90'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (lng < -180 || lng > 180) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Longitude must be between -180 and 180'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              setState(() {
                _centerLatitude = lat;
                _centerLongitude = lng;
                _locationAccuracy = 5.0; // Manual entry assumed accurate
              });

              // Calculate coordinates if dimensions are available
              _calculateCoordinates();

              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '✓ Coordinates set successfully!\n'
                    'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}',
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            icon: const Icon(Icons.check),
            label: const Text('Set Coordinates'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Room Dimensions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the width and length of the room in meters',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _widthController,
                    decoration: const InputDecoration(
                      labelText: 'Width (meters)',
                      hintText: 'e.g., 10',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.straighten),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _calculateCoordinates(),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      if (double.tryParse(value) == null) {
                        return 'Invalid';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _lengthController,
                    decoration: const InputDecoration(
                      labelText: 'Length (meters)',
                      hintText: 'e.g., 15',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.straighten),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _calculateCoordinates(),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      if (double.tryParse(value) == null) {
                        return 'Invalid';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWiFiSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WiFi Assignment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Assign a WiFi router for improved location accuracy (optional)',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Consumer<AppState>(
              builder: (context, appState, child) {
                final unassignedRouters = appState.getUnassignedRouters();
                
                if (unassignedRouters.isEmpty) {
                  return const Text(
                    'No unassigned WiFi routers available. Please add routers first.',
                    style: TextStyle(color: Colors.orange),
                  );
                }

                return DropdownButtonFormField<String>(
                  value: _selectedWifiId,
                  decoration: const InputDecoration(
                    labelText: 'Select WiFi Router',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.wifi),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('None'),
                    ),
                    ...unassignedRouters.map((router) {
                      return DropdownMenuItem<String>(
                        value: router.id,
                        child: Text('${router.ssid} (Floor ${router.floor})'),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedWifiId = value;
                    });
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoordinatesPreview() {
    final coords = _calculatedCoordinates!;
    
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.map, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text(
                  'Calculated Boundaries',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Exact room boundaries - no safety margin applied',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildCoordinateRow('North-East', coords.northEast),
            _buildCoordinateRow('North-West', coords.northWest),
            _buildCoordinateRow('South-East', coords.southEast),
            _buildCoordinateRow('South-West', coords.southWest),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showMapPreview(),
                icon: const Icon(Icons.map),
                label: const Text('View on Map'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMapPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _RoomPreviewMap(
          roomCenter: LatLng(_centerLatitude!, _centerLongitude!),
          coordinates: _calculatedCoordinates!,
          roomName: _nameController.text.trim(),
          building: _buildingController.text.trim(),
          floor: _floorController.text.trim(),
        ),
      ),
    );
  }

  Widget _buildCoordinateRow(String label, GeoPoint point) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

// Room Preview Map Widget
class _RoomPreviewMap extends StatefulWidget {
  final LatLng roomCenter;
  final RoomCoordinates coordinates;
  final String roomName;
  final String building;
  final String floor;

  const _RoomPreviewMap({
    required this.roomCenter,
    required this.coordinates,
    required this.roomName,
    required this.building,
    required this.floor,
  });

  @override
  State<_RoomPreviewMap> createState() => __RoomPreviewMapState();
}

class __RoomPreviewMapState extends State<_RoomPreviewMap> {
  GoogleMapController? _mapController;
  MapType _mapType = MapType.satellite;

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    
    // Set map style
    _mapController!.setMapStyle('''
      [
        {
          "featureType": "all",
          "stylers": [{"saturation": -20}]
        }
      ]
    ''');
    
    // Move to room center
    _moveToRoom();
  }

  void _moveToRoom() {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: widget.roomCenter,
          zoom: 18.5,
          tilt: 0.0,
          bearing: 0.0,
        ),
      ),
    );
  }

  void _toggleMapType() {
    setState(() {
      if (_mapType == MapType.normal) {
        _mapType = MapType.satellite;
      } else if (_mapType == MapType.satellite) {
        _mapType = MapType.hybrid;
      } else {
        _mapType = MapType.normal;
      }
    });
  }

  Set<Marker> _buildMarkers() {
    return {
      Marker(
        markerId: const MarkerId('room_center'),
        position: widget.roomCenter,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(
          title: 'Room Center',
          snippet: widget.roomName.isNotEmpty 
              ? '${widget.roomName} - ${widget.building}' 
              : 'Center',
        ),
      ),
    };
  }

  Set<Polygon> _buildRoomPolygon() {
    return {
      Polygon(
        polygonId: const PolygonId('room_boundary'),
        points: [
          LatLng(widget.coordinates.northEast.latitude, widget.coordinates.northEast.longitude),
          LatLng(widget.coordinates.northWest.latitude, widget.coordinates.northWest.longitude),
          LatLng(widget.coordinates.southWest.latitude, widget.coordinates.southWest.longitude),
          LatLng(widget.coordinates.southEast.latitude, widget.coordinates.southEast.longitude),
        ],
        fillColor: Colors.blue.withOpacity(0.3),
        strokeColor: Colors.blue,
        strokeWidth: 3,
        geodesic: true,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final initialCamera = CameraPosition(
      target: widget.roomCenter,
      zoom: 18.5,
      tilt: 0.0,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Room Preview'),
        actions: [
          IconButton(
            icon: Icon(
              _mapType == MapType.satellite 
                  ? Icons.map 
                  : _mapType == MapType.hybrid 
                      ? Icons.satellite 
                      : Icons.map_outlined,
            ),
            tooltip: 'Toggle Map Type',
            onPressed: _toggleMapType,
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong),
            tooltip: 'Center on Room',
            onPressed: _moveToRoom,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: initialCamera,
            mapType: _mapType,
            myLocationButtonEnabled: true,
            myLocationEnabled: true,
            zoomControlsEnabled: true,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            onMapCreated: _onMapCreated,
            markers: _buildMarkers(),
            polygons: _buildRoomPolygon(),
          ),
          // Info overlay
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.meeting_room, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.roomName.isNotEmpty 
                                ? '${widget.roomName} - Floor ${widget.floor}' 
                                : 'Room Preview',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Room Boundaries Shown',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Students must be inside this area to mark attendance',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

