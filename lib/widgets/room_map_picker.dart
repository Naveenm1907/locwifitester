import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RoomMapPicker extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final Function(double latitude, double longitude) onLocationSelected;

  const RoomMapPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    required this.onLocationSelected,
  });

  @override
  State<RoomMapPicker> createState() => _RoomMapPickerState();
}

class _RoomMapPickerState extends State<RoomMapPicker> {
  GoogleMapController? _mapController;
  MapType _mapType = MapType.satellite;
  double? _selectedLatitude;
  double? _selectedLongitude;
  bool _is3DEnabled = false;
  double _cameraTilt = 0.0;

  @override
  void initState() {
    super.initState();
    _selectedLatitude = widget.initialLatitude;
    _selectedLongitude = widget.initialLongitude;
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    
    // Enable 3D buildings
    _mapController!.setMapStyle('''
      [
        {
          "featureType": "all",
          "stylers": [{"saturation": -20}]
        },
        {
          "featureType": "poi",
          "elementType": "labels",
          "stylers": [{"visibility": "off"}]
        }
      ]
    ''');
    
    // If initial location is provided, move to it
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _moveToLocation(widget.initialLatitude!, widget.initialLongitude!);
    }
  }

  void _moveToLocation(double lat, double lng) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lng),
          zoom: 18.0,
          tilt: _is3DEnabled ? 45.0 : 0.0,
          bearing: 0.0,
        ),
      ),
    );
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _selectedLatitude = position.latitude;
      _selectedLongitude = position.longitude;
    });
    widget.onLocationSelected(position.latitude, position.longitude);
    
    // Show snackbar with coordinates
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Location selected: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        ),
        duration: const Duration(seconds: 2),
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

  void _toggle3D() {
    setState(() {
      _is3DEnabled = !_is3DEnabled;
      _cameraTilt = _is3DEnabled ? 45.0 : 0.0;
      
      if (_selectedLatitude != null && _selectedLongitude != null) {
        _moveToLocation(_selectedLatitude!, _selectedLongitude!);
      }
    });
  }

  void _resetView() {
    if (_selectedLatitude != null && _selectedLongitude != null) {
      _moveToLocation(_selectedLatitude!, _selectedLongitude!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialCamera = CameraPosition(
      target: LatLng(
        _selectedLatitude ?? widget.initialLatitude ?? 0.0,
        _selectedLongitude ?? widget.initialLongitude ?? 0.0,
      ),
      zoom: _selectedLatitude != null ? 18.0 : 2.0,
      tilt: _cameraTilt,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Room Location'),
        actions: [
          IconButton(
            icon: Icon(_is3DEnabled ? Icons.view_in_ar : Icons.view_in_ar_outlined),
            tooltip: _is3DEnabled ? 'Disable 3D' : 'Enable 3D',
            onPressed: _toggle3D,
          ),
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
          if (_selectedLatitude != null)
            IconButton(
              icon: const Icon(Icons.center_focus_strong),
              tooltip: 'Reset View',
              onPressed: _resetView,
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
            tiltGesturesEnabled: true,
            rotateGesturesEnabled: true,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            onMapCreated: _onMapCreated,
            onTap: _onMapTap,
            markers: _selectedLatitude != null && _selectedLongitude != null
                ? {
                    Marker(
                      markerId: const MarkerId('room_location'),
                      position: LatLng(_selectedLatitude!, _selectedLongitude!),
                      draggable: true,
                      onDragEnd: (LatLng newPosition) {
                        setState(() {
                          _selectedLatitude = newPosition.latitude;
                          _selectedLongitude = newPosition.longitude;
                        });
                        widget.onLocationSelected(
                          newPosition.latitude,
                          newPosition.longitude,
                        );
                      },
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueBlue,
                      ),
                      infoWindow: InfoWindow(
                        title: 'Room Location',
                        snippet: '${_selectedLatitude!.toStringAsFixed(6)}, ${_selectedLongitude!.toStringAsFixed(6)}',
                      ),
                    ),
                  }
                : {},
          ),
          // Instructions overlay
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
                        Icon(
                          _is3DEnabled 
                              ? Icons.view_in_ar 
                              : Icons.location_on,
                          color: Colors.blue,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedLatitude != null
                                ? 'Location selected! Tap map to change.'
                                : 'Tap on the map to select room location',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_selectedLatitude != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, 
                                color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Lat: ${_selectedLatitude!.toStringAsFixed(6)}\n'
                                'Lng: ${_selectedLongitude!.toStringAsFixed(6)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${_mapType == MapType.satellite ? "Satellite" : _mapType == MapType.hybrid ? "Hybrid" : "Normal"} view • ${_is3DEnabled ? "3D enabled" : "2D"}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedLatitude != null
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check),
              label: const Text('Confirm Location'),
              backgroundColor: Colors.green,
            )
          : null,
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}


