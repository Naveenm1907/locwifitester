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

  User? get currentUser => _currentUser;
  List<Room> get rooms => _rooms;
  List<WiFiRouter> get wifiRouters => _wifiRouters;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAdmin => _currentUser?.role == UserRole.admin;

  final FirebaseService _firebaseService = FirebaseService.instance;

  /// Set current user
  void setCurrentUser(User user) {
    _currentUser = user;
    notifyListeners();
  }

  /// Load all rooms
  Future<void> loadRooms() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _rooms = await _firebaseService.getAllRooms();
      
      _isLoading = false;
      _error = null; // Clear any previous errors
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load rooms: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow; // Re-throw so callers can handle it
    }
  }

  /// Load all WiFi routers
  Future<void> loadWiFiRouters() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _wifiRouters = await _firebaseService.getAllWiFiRouters();
      
      _isLoading = false;
      _error = null; // Clear any previous errors
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load WiFi routers: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      rethrow; // Re-throw so callers can handle it
    }
  }

  /// Add a new room
  Future<bool> addRoom(Room room) async {
    try {
      await _firebaseService.createRoom(room);
      await loadRooms();
      return true;
    } catch (e) {
      _error = 'Failed to add room: $e';
      notifyListeners();
      return false;
    }
  }

  /// Update a room
  Future<bool> updateRoom(Room room) async {
    try {
      await _firebaseService.updateRoom(room);
      await loadRooms();
      return true;
    } catch (e) {
      _error = 'Failed to update room: $e';
      notifyListeners();
      return false;
    }
  }

  /// Delete a room
  Future<bool> deleteRoom(String roomId) async {
    try {
      await _firebaseService.deleteRoom(roomId);
      await loadRooms();
      return true;
    } catch (e) {
      _error = 'Failed to delete room: $e';
      notifyListeners();
      return false;
    }
  }

  /// Add a new WiFi router
  Future<bool> addWiFiRouter(WiFiRouter router) async {
    try {
      await _firebaseService.createWiFiRouter(router);
      await loadWiFiRouters();
      return true;
    } catch (e) {
      _error = 'Failed to add WiFi router: $e';
      notifyListeners();
      return false;
    }
  }

  /// Update a WiFi router
  Future<bool> updateWiFiRouter(WiFiRouter router) async {
    try {
      await _firebaseService.updateWiFiRouter(router);
      await loadWiFiRouters();
      return true;
    } catch (e) {
      _error = 'Failed to update WiFi router: $e';
      notifyListeners();
      return false;
    }
  }

  /// Delete a WiFi router
  Future<bool> deleteWiFiRouter(String routerId) async {
    try {
      await _firebaseService.deleteWiFiRouter(routerId);
      await loadWiFiRouters();
      return true;
    } catch (e) {
      _error = 'Failed to delete WiFi router: $e';
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

