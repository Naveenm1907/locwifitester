import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../models/wifi_router.dart';
import '../services/firebase_service.dart';

class AppState extends ChangeNotifier {
  User? _currentUser;
  List<Room> _rooms = [];
  List<WiFiRouter> _wifiRouters = [];
  bool _isLoading = false;
  String? _error;
  bool _isConnected = true;
  DateTime? _lastSuccessfulSync;

  User? get currentUser => _currentUser;
  List<Room> get rooms => _rooms;
  List<WiFiRouter> get wifiRouters => _wifiRouters;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAdmin => _currentUser?.role == UserRole.admin;
  bool get isConnected => _isConnected;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;

  final FirebaseService _firebaseService = FirebaseService.instance;

  /// Set current user
  void setCurrentUser(User user) {
    _currentUser = user;
    notifyListeners();
  }

  /// Check connectivity status
  Future<void> checkConnectivity() async {
    try {
      final status = await _firebaseService.getConnectionStatus();
      _isConnected = status['connected'] == true;
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      notifyListeners();
    }
  }

  /// Load all rooms with improved error handling
  Future<void> loadRooms({bool silent = false}) async {
    try {
      if (!silent) {
        _isLoading = true;
        _error = null;
        notifyListeners();
      }

      _rooms = await _firebaseService.getAllRooms();
      
      _isLoading = false;
      _error = null;
      _isConnected = true;
      _lastSuccessfulSync = DateTime.now();
      notifyListeners();
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      
      // Check if it's a network error
      final isNetworkError = errorMessage.toLowerCase().contains('network') ||
          errorMessage.toLowerCase().contains('timeout') ||
          errorMessage.toLowerCase().contains('connection');
      
      if (isNetworkError) {
        _isConnected = false;
        // If we have cached data, use it
        if (_rooms.isEmpty) {
          _error = 'No internet connection. Please check your network and try again.';
        } else {
          _error = 'Using cached data. Connection will resume when online.';
        }
      } else {
        _error = 'Failed to load rooms: $errorMessage';
      }
      
      _isLoading = false;
      notifyListeners();
      
      if (!silent) {
        rethrow; // Re-throw so callers can handle it
      }
    }
  }

  /// Load all WiFi routers with improved error handling
  Future<void> loadWiFiRouters({bool silent = false}) async {
    try {
      if (!silent) {
        _isLoading = true;
        _error = null;
        notifyListeners();
      }

      _wifiRouters = await _firebaseService.getAllWiFiRouters();
      
      _isLoading = false;
      _error = null;
      _isConnected = true;
      _lastSuccessfulSync = DateTime.now();
      notifyListeners();
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      
      // Check if it's a network error
      final isNetworkError = errorMessage.toLowerCase().contains('network') ||
          errorMessage.toLowerCase().contains('timeout') ||
          errorMessage.toLowerCase().contains('connection');
      
      if (isNetworkError) {
        _isConnected = false;
        // If we have cached data, use it
        if (_wifiRouters.isEmpty) {
          _error = 'No internet connection. Please check your network and try again.';
        } else {
          _error = 'Using cached data. Connection will resume when online.';
        }
      } else {
        _error = 'Failed to load WiFi routers: $errorMessage';
      }
      
      _isLoading = false;
      notifyListeners();
      
      if (!silent) {
        rethrow; // Re-throw so callers can handle it
      }
    }
  }

  /// Add a new room
  Future<bool> addRoom(Room room) async {
    try {
      await _firebaseService.createRoom(room);
      await loadRooms(silent: true);
      _isConnected = true;
      return true;
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      _error = errorMessage;
      _isConnected = !errorMessage.toLowerCase().contains('network') &&
                    !errorMessage.toLowerCase().contains('timeout');
      notifyListeners();
      return false;
    }
  }

  /// Update a room
  Future<bool> updateRoom(Room room) async {
    try {
      await _firebaseService.updateRoom(room);
      await loadRooms(silent: true);
      _isConnected = true;
      return true;
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      _error = errorMessage;
      _isConnected = !errorMessage.toLowerCase().contains('network') &&
                    !errorMessage.toLowerCase().contains('timeout');
      notifyListeners();
      return false;
    }
  }

  /// Delete a room
  Future<bool> deleteRoom(String roomId) async {
    try {
      await _firebaseService.deleteRoom(roomId);
      await loadRooms(silent: true);
      _isConnected = true;
      return true;
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      _error = errorMessage;
      _isConnected = !errorMessage.toLowerCase().contains('network') &&
                    !errorMessage.toLowerCase().contains('timeout');
      notifyListeners();
      return false;
    }
  }

  /// Add a new WiFi router
  Future<bool> addWiFiRouter(WiFiRouter router) async {
    try {
      await _firebaseService.createWiFiRouter(router);
      await loadWiFiRouters(silent: true);
      _isConnected = true;
      return true;
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      _error = errorMessage;
      _isConnected = !errorMessage.toLowerCase().contains('network') &&
                    !errorMessage.toLowerCase().contains('timeout');
      notifyListeners();
      return false;
    }
  }

  /// Update a WiFi router
  Future<bool> updateWiFiRouter(WiFiRouter router) async {
    try {
      await _firebaseService.updateWiFiRouter(router);
      await loadWiFiRouters(silent: true);
      _isConnected = true;
      return true;
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      _error = errorMessage;
      _isConnected = !errorMessage.toLowerCase().contains('network') &&
                    !errorMessage.toLowerCase().contains('timeout');
      notifyListeners();
      return false;
    }
  }

  /// Delete a WiFi router
  Future<bool> deleteWiFiRouter(String routerId) async {
    try {
      await _firebaseService.deleteWiFiRouter(routerId);
      await loadWiFiRouters(silent: true);
      _isConnected = true;
      return true;
    } catch (e) {
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      _error = errorMessage;
      _isConnected = !errorMessage.toLowerCase().contains('network') &&
                    !errorMessage.toLowerCase().contains('timeout');
      notifyListeners();
      return false;
    }
  }

  /// Get rooms by floor
  List<Room> getRoomsByFloor(int floor) {
    return _rooms.where((room) => room.floor == floor).toList();
  }

  /// Get WiFi routers by floor
  List<WiFiRouter> getWiFiRoutersByFloor(int floor) {
    return _wifiRouters.where((router) => router.floor == floor).toList();
  }

  /// Get unassigned WiFi routers
  List<WiFiRouter> getUnassignedRouters() {
    final assignedIds = _rooms
        .where((room) => room.assignedWifiId != null)
        .map((room) => room.assignedWifiId!)
        .toSet();
    
    return _wifiRouters
        .where((router) => !assignedIds.contains(router.id))
        .toList();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Logout
  Future<void> logout() async {
    // Sign out from Firebase Auth
    await _firebaseService.signOut();
    
    // Clear local state
    _currentUser = null;
    _rooms = [];
    _wifiRouters = [];
    notifyListeners();
  }
}

