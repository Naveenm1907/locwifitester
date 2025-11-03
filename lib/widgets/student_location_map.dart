import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/room.dart';

class StudentLocationMap extends StatefulWidget {
  final double studentLatitude;
  final double studentLongitude;
  final Room? room;
  final double? accuracy;

  const StudentLocationMap({
    super.key,
    required this.studentLatitude,
    required this.studentLongitude,
    this.room,
    this.accuracy,
  });

  @override
  State<StudentLocationMap> createState() => _StudentLocationMapState();
}

class _StudentLocationMapState extends State<StudentLocationMap> {
  GoogleMapController? _mapController;
  MapType _mapType = MapType.satellite;
  bool _is3DEnabled = false;

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    
    // Enable 3D buildings
    _mapController!.setMapStyle('''
      [
        {
          "featureType": "all",
          "stylers": [{"saturation": -20}]
        }
      ]
    ''');
    
    // Move to student location
    _moveToStudentLocation();
  }

  void _moveToStudentLocation() {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(widget.studentLatitude, widget.studentLongitude),
          zoom: widget.accuracy != null && widget.accuracy! < 50 
              ? 18.0 
              : 16.0,
          tilt: _is3DEnabled ? 45.0 : 0.0,
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

  void _toggle3D() {
    setState(() {
      _is3DEnabled = !_is3DEnabled;
      _moveToStudentLocation();
    });
  }

  Set<Marker> _buildMarkers() {
    Set<Marker> markers = {};

    // Student location marker
    markers.add(
      Marker(
        markerId: const MarkerId('student_location'),
        position: LatLng(widget.studentLatitude, widget.studentLongitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Your Location',
          snippet: widget.accuracy != null
              ? 'Accuracy: ${widget.accuracy!.toStringAsFixed(1)}m'
              : 'Student Location',
        ),
      ),
    );

    // Room location marker (if provided)
    if (widget.room != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('room_location'),
          position: LatLng(
            widget.room!.centerLatitude,
            widget.room!.centerLongitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: widget.room!.name,
            snippet: '${widget.room!.building}, Floor ${widget.room!.floor}',
          ),
        ),
      );
    }

    return markers;
  }

  Set<Polygon> _buildRoomPolygon() {
    if (widget.room == null) return {};

    return {
      Polygon(
        polygonId: const PolygonId('room_boundary'),
        points: [
          LatLng(
            widget.room!.coordinates.northEast.latitude,
            widget.room!.coordinates.northEast.longitude,
          ),
          LatLng(
            widget.room!.coordinates.northWest.latitude,
            widget.room!.coordinates.northWest.longitude,
          ),
          LatLng(
            widget.room!.coordinates.southWest.latitude,
            widget.room!.coordinates.southWest.longitude,
          ),
          LatLng(
            widget.room!.coordinates.southEast.latitude,
            widget.room!.coordinates.southEast.longitude,
          ),
        ],
        fillColor: Colors.blue.withOpacity(0.2),
        strokeColor: Colors.blue,
        strokeWidth: 2,
        geodesic: true,
      ),
    };
  }

  Circle? _buildAccuracyCircle() {
    if (widget.accuracy == null || widget.accuracy! > 100) return null;

    return Circle(
      circleId: const CircleId('accuracy_circle'),
      center: LatLng(widget.studentLatitude, widget.studentLongitude),
      radius: widget.accuracy!,
      fillColor: Colors.green.withOpacity(0.1),
      strokeColor: Colors.green.withOpacity(0.5),
      strokeWidth: 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialCamera = CameraPosition(
      target: LatLng(widget.studentLatitude, widget.studentLongitude),
      zoom: widget.accuracy != null && widget.accuracy! < 50 ? 18.0 : 16.0,
      tilt: _is3DEnabled ? 45.0 : 0.0,
    );

    final accuracyCircle = _buildAccuracyCircle();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Location'),
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
          IconButton(
            icon: const Icon(Icons.center_focus_strong),
            tooltip: 'Center on Location',
            onPressed: _moveToStudentLocation,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: initialCamera,
            mapType: _mapType,
            myLocationButtonEnabled: false,
            myLocationEnabled: true,
            zoomControlsEnabled: true,
            tiltGesturesEnabled: true,
            rotateGesturesEnabled: true,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            onMapCreated: _onMapCreated,
            markers: _buildMarkers(),
            polygons: _buildRoomPolygon(),
            circles: accuracyCircle != null ? {accuracyCircle} : {},
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
                        const Icon(Icons.location_on, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your Location',
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
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lat: ${widget.studentLatitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            'Lng: ${widget.studentLongitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (widget.accuracy != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Accuracy: ${widget.accuracy!.toStringAsFixed(1)}m',
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.accuracy! <= 10
                                    ? Colors.green.shade700
                                    : widget.accuracy! <= 30
                                        ? Colors.orange.shade700
                                        : Colors.red.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.room != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.meeting_room, 
                                color: Colors.blue, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${widget.room!.name}\n'
                                '${widget.room!.building}, Floor ${widget.room!.floor}',
                                style: const TextStyle(fontSize: 11),
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
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}


