import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:wifi_scan/wifi_scan.dart';
import '../../models/wifi_router.dart';
import '../../providers/app_state.dart';
import '../../services/location_service.dart';

class WiFiRouterScreen extends StatefulWidget {
  const WiFiRouterScreen({super.key});

  @override
  State<WiFiRouterScreen> createState() => _WiFiRouterScreenState();
}

class _WiFiRouterScreenState extends State<WiFiRouterScreen> {
  bool _isScanning = false;
  List<WiFiAccessPoint> _scannedNetworks = [];

  @override
  void initState() {
    super.initState();
    _loadWiFiRouters();
  }

  Future<void> _loadWiFiRouters() async {
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.loadWiFiRouters();
  }

  /// Check if a WiFi access point is likely a mobile hotspot
  /// Returns true if it's a mobile hotspot (should be filtered out)
  bool _isMobileHotspot(WiFiAccessPoint ap) {
    final ssid = ap.ssid.toLowerCase().trim();
    
    // Empty or hidden SSID - not a hotspot, could be a router
    if (ssid.isEmpty) {
      return false;
    }
    
    // Very clear mobile hotspot patterns (high confidence)
    final clearHotspotPatterns = [
      "iphone",        // iPhone's hotspot
      "android",       // Android's default
      "direct-",       // WiFi Direct
      "p2p-",          // WiFi Direct P2P
      "'s iphone",     // "John's iPhone"
      "'s android",    // "John's Android"
      "'s phone",      // "John's Phone"
      "'s galaxy",     // "John's Galaxy"
      "'s pixel",      // "John's Pixel"
      "my iphone",     // "My iPhone"
      "my android",    // "My Android"
      "my phone",      // "My Phone"
    ];
    
    // Check for clear hotspot patterns
    for (var pattern in clearHotspotPatterns) {
      if (ssid.contains(pattern)) {
        return true;
      }
    }
    
    // Check if it starts with common phone model names (more specific)
    final phoneModelPrefixes = [
      'pixel ',      // "Pixel 6"
      'galaxy ',     // "Galaxy S21"
      'oneplus ',    // "OnePlus 9"
      'redmi ',      // "Redmi Note"
      'poco ',       // "POCO X3"
      'mi ',         // "Mi 11"
    ];
    
    for (var prefix in phoneModelPrefixes) {
      if (ssid.startsWith(prefix)) {
        return true;
      }
    }
    
    // Very short SSIDs (less than 4 chars) are often personal hotspots
    if (ssid.length < 4 && ssid.isNotEmpty) {
      return true;
    }
    
    // Contains numbers followed by model indicator (e.g., "5G", "4G", "Pro")
    // AND is short (likely a phone model like "Redmi9Pro")
    if (ssid.length < 15 && RegExp(r'\d+(pro|plus|lite|max|ultra|5g|4g)').hasMatch(ssid)) {
      // Check if it has common phone indicators
      if (ssid.contains('redmi') || ssid.contains('poco') || 
          ssid.contains('realme') || ssid.contains('oppo') || 
          ssid.contains('vivo')) {
        return true;
      }
    }
    
    // If SSID looks like a person's name + phone (e.g., "John")
    // This is tricky, so we'll be conservative and not filter these
    
    return false; // When in doubt, show it (less aggressive)
  }

  Future<void> _scanWiFiNetworks() async {
    setState(() {
      _isScanning = true;
    });

    final locationService = LocationService.instance;
    final canScan = await locationService.canScanWiFi();

    if (!canScan) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WiFi scanning is not available on this device'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      setState(() {
        _isScanning = false;
      });
      return;
    }

    final networks = await locationService.scanWiFiNetworks();
    
    // Filter out mobile hotspots - only show WiFi routers
    final filteredNetworks = networks.where((ap) => !_isMobileHotspot(ap)).toList();
    
    setState(() {
      _scannedNetworks = filteredNetworks;
      _isScanning = false;
    });

    if (filteredNetworks.isEmpty && mounted) {
      final totalFound = networks.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            totalFound > 0 
                ? 'Found $totalFound network(s) but filtered as mobile hotspots. If this seems wrong, add routers manually.'
                : 'No WiFi networks found. Make sure Location & WiFi are enabled.'
          ),
          backgroundColor: totalFound > 0 ? Colors.orange : null,
          duration: const Duration(seconds: 5),
          action: totalFound > 0 ? SnackBarAction(
            label: 'Show All',
            textColor: Colors.white,
            onPressed: () {
              setState(() {
                _scannedNetworks = networks; // Show unfiltered
              });
            },
          ) : null,
        ),
      );
    }
  }

  void _showAddRouterDialog({WiFiAccessPoint? preselected}) {
    showDialog(
      context: context,
      builder: (context) => AddWiFiRouterDialog(
        scannedNetworks: _scannedNetworks,
        preselected: preselected,
      ),
    );
  }

  void _showDeleteConfirmation(WiFiRouter router) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete WiFi Router'),
        content: Text('Are you sure you want to delete "${router.ssid}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final appState = Provider.of<AppState>(context, listen: false);
              final success = await appState.deleteWiFiRouter(router.id);
              
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('WiFi router deleted'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Router Management'),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildScanSection(),
          Expanded(
            child: Consumer<AppState>(
              builder: (context, appState, child) {
                if (appState.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Show error if any
                if (appState.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          'Error Loading Routers',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            appState.error!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadWiFiRouters,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (appState.wifiRouters.isEmpty) {
                  return _buildEmptyState();
                }

                return _buildRouterList(appState.wifiRouters);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRouterDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Router'),
      ),
    );
  }

  Widget _buildScanSection() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_find, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Scan for WiFi Networks',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Scans nearby WiFi networks. Mobile hotspots are filtered (tap "Show All" if needed)',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _scanWiFiNetworks,
                icon: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_isScanning ? 'Scanning...' : 'Scan WiFi'),
              ),
            ),
            if (_scannedNetworks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  'Found ${_scannedNetworks.length} networks',
                  style: TextStyle(color: Colors.green.shade700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.router, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No WiFi Routers',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add WiFi routers to improve\nlocation accuracy',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildRouterList(List<WiFiRouter> routers) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: routers.length,
      itemBuilder: (context, index) {
        final router = routers[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: router.isActive ? Colors.green : Colors.grey,
              child: const Icon(Icons.wifi, color: Colors.white),
            ),
            title: Text(
              router.ssid,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('BSSID: ${router.bssid}'),
                Text('Floor ${router.floor} - ${router.building}'),
                if (router.location != null)
                  Text('Location: ${router.location}'),
              ],
            ),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _showDeleteConfirmation(router),
            ),
          ),
        );
      },
    );
  }
}

class AddWiFiRouterDialog extends StatefulWidget {
  final List<WiFiAccessPoint> scannedNetworks;
  final WiFiAccessPoint? preselected;

  const AddWiFiRouterDialog({
    super.key,
    required this.scannedNetworks,
    this.preselected,
  });

  @override
  State<AddWiFiRouterDialog> createState() => _AddWiFiRouterDialogState();
}

class _AddWiFiRouterDialogState extends State<AddWiFiRouterDialog> {
  final _formKey = GlobalKey<FormState>();
  final _buildingController = TextEditingController();
  final _floorController = TextEditingController();
  final _locationController = TextEditingController();
  final _thresholdController = TextEditingController(text: '-70');
  final _sameFloorMinController = TextEditingController(text: '-55');
  final _differentFloorMaxController = TextEditingController(text: '-75');
  
  WiFiAccessPoint? _selectedNetwork;
  String? _manualSSID;
  String? _manualBSSID;

  @override
  void initState() {
    super.initState();
    if (widget.preselected != null) {
      _selectedNetwork = widget.preselected;
    }
  }

  @override
  void dispose() {
    _buildingController.dispose();
    _floorController.dispose();
    _locationController.dispose();
    _thresholdController.dispose();
    _sameFloorMinController.dispose();
    _differentFloorMaxController.dispose();
    super.dispose();
  }

  Future<void> _saveRouter() async {
    if (!_formKey.currentState!.validate()) return;

    String ssid;
    String bssid;

    if (_selectedNetwork != null) {
      ssid = _selectedNetwork!.ssid;
      bssid = _selectedNetwork!.bssid;
    } else {
      if (_manualSSID == null || _manualBSSID == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a network or enter details manually')),
        );
        return;
      }
      ssid = _manualSSID!;
      bssid = _manualBSSID!;
    }

    final router = WiFiRouter(
      id: const Uuid().v4(),
      ssid: ssid,
      bssid: bssid,
      building: _buildingController.text.trim(),
      floor: int.parse(_floorController.text.trim()),
      location: _locationController.text.trim().isEmpty 
          ? null 
          : _locationController.text.trim(),
      signalStrengthThreshold: int.parse(_thresholdController.text.trim()),
      sameFloorMinSignal: int.parse(_sameFloorMinController.text.trim()),
      differentFloorMaxSignal: int.parse(_differentFloorMaxController.text.trim()),
      createdAt: DateTime.now(),
    );

    final appState = Provider.of<AppState>(context, listen: false);
    final success = await appState.addWiFiRouter(router);

    if (success && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WiFi router added successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add WiFi Router',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                if (widget.scannedNetworks.isNotEmpty) ...[
                  const Text('Select Network:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<WiFiAccessPoint>(
                    value: _selectedNetwork,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Choose from scanned networks',
                    ),
                    items: widget.scannedNetworks.map((ap) {
                      return DropdownMenuItem(
                        value: ap,
                        child: Text('${ap.ssid} (${ap.level} dBm)'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedNetwork = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _buildingController,
                  decoration: const InputDecoration(
                    labelText: 'Building Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _floorController,
                  decoration: const InputDecoration(
                    labelText: 'Floor Number',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Required';
                    }
                    if (int.tryParse(value) == null) {
                      return 'Invalid number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location (Optional)',
                    hintText: 'e.g., Near staircase, End of corridor',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _thresholdController,
                  decoration: const InputDecoration(
                    labelText: 'Detection Threshold (dBm)',
                    hintText: '-70',
                    border: OutlineInputBorder(),
                    helperText: 'Minimum signal to detect WiFi',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Required';
                    }
                    final num = int.tryParse(value);
                    if (num == null || num > 0 || num < -100) {
                      return 'Enter value between -100 and 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
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
                      Row(
                        children: [
                          Icon(Icons.layers, color: Colors.blue.shade700, size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'Floor Detection Settings',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'These values help determine which floor a user is on based on signal strength:',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _sameFloorMinController,
                  decoration: const InputDecoration(
                    labelText: 'Same Floor Min Signal (dBm)',
                    hintText: '-55',
                    border: OutlineInputBorder(),
                    helperText: 'Strong signal confirms same floor',
                    prefixIcon: Icon(Icons.signal_wifi_4_bar, color: Colors.green),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Required';
                    }
                    final num = int.tryParse(value);
                    if (num == null || num > 0 || num < -100) {
                      return 'Enter value between -100 and 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _differentFloorMaxController,
                  decoration: const InputDecoration(
                    labelText: 'Different Floor Max Signal (dBm)',
                    hintText: '-75',
                    border: OutlineInputBorder(),
                    helperText: 'Weak signal suggests different floor',
                    prefixIcon: Icon(Icons.signal_wifi_0_bar, color: Colors.orange),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Required';
                    }
                    final num = int.tryParse(value);
                    if (num == null || num > 0 || num < -100) {
                      return 'Enter value between -100 and 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💡 How it works:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text('• Strong (≥-55 dBm): User on same floor', style: TextStyle(fontSize: 10)),
                      Text('• Weak (≤-75 dBm): User on different floor', style: TextStyle(fontSize: 10)),
                      Text('• Medium: Accepted if room floor matches', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saveRouter,
                      child: const Text('Add Router'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

