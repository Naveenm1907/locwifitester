import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../models/room.dart';
import '../models/wifi_router.dart';
import '../models/attendance.dart';
import '../models/user.dart' as app_user;

class FirebaseService {
  static final FirebaseService instance = FirebaseService._init();
  FirebaseService._init();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;

  // Collections
  static const String usersCollection = 'users';
  static const String roomsCollection = 'rooms';
  static const String wifiRoutersCollection = 'wifi_routers';
  static const String attendanceCollection = 'attendance';

  // ==================== AUTHENTICATION ====================

  /// Sign in with email and password
  Future<auth.User?> signInWithEmailPassword(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } catch (e) {
      throw Exception('Sign in failed: $e');
    }
  }

  /// Sign up with email and password
  Future<auth.User?> signUpWithEmailPassword(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } catch (e) {
      throw Exception('Sign up failed: $e');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Get current Firebase user
  auth.User? get currentFirebaseUser => _auth.currentUser;

  /// Listen to auth state changes
  Stream<auth.User?> get authStateChanges => _auth.authStateChanges();

  // ==================== USER CRUD ====================

  /// Create a new user document
  Future<String> createUser(app_user.User user) async {
    try {
      await _firestore.collection(usersCollection).doc(user.id).set(user.toMap());
      return user.id;
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  /// Get user by ID
  Future<app_user.User?> getUser(String id) async {
    try {
      final doc = await _firestore.collection(usersCollection).doc(id).get();
      if (doc.exists && doc.data() != null) {
        return app_user.User.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get user: $e');
    }
  }

  /// Get user by email
  Future<app_user.User?> getUserByEmail(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection(usersCollection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return app_user.User.fromMap(querySnapshot.docs.first.data());
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get user by email: $e');
    }
  }

  /// Get all users
  Future<List<app_user.User>> getAllUsers() async {
    try {
      final querySnapshot = await _firestore
          .collection(usersCollection)
          .orderBy('name')
          .get();

      return querySnapshot.docs
          .map((doc) => app_user.User.fromMap(doc.data()))
          .toList();
    } catch (e) {
      throw Exception('Failed to get users: $e');
    }
  }

  /// Update user
  Future<void> updateUser(app_user.User user) async {
    try {
      await _firestore.collection(usersCollection).doc(user.id).update(user.toMap());
    } catch (e) {
      throw Exception('Failed to update user: $e');
    }
  }

  // ==================== ROOM CRUD ====================

  /// Create a new room
  Future<String> createRoom(Room room) async {
    try {
      await _firestore.collection(roomsCollection).doc(room.id).set(room.toMap());
      return room.id;
    } catch (e) {
      throw Exception('Failed to create room: $e');
    }
  }

  /// Get room by ID
  Future<Room?> getRoom(String id) async {
    try {
      final doc = await _firestore.collection(roomsCollection).doc(id).get();
      if (doc.exists && doc.data() != null) {
        return Room.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get room: $e');
    }
  }

  /// Get all rooms
  Future<List<Room>> getAllRooms({bool activeOnly = true}) async {
    try {
      // Get all documents without orderBy to avoid index issues
      final querySnapshot = await _firestore.collection(roomsCollection).get();

      var rooms = querySnapshot.docs
          .map((doc) {
            try {
              return Room.fromMap(doc.data());
            } catch (e) {
              // Skip documents that can't be parsed
              print('Error parsing room ${doc.id}: $e');
              return null;
            }
          })
          .whereType<Room>()
          .toList();
      
      // Filter by active status in memory
      if (activeOnly) {
        rooms = rooms.where((room) => room.isActive).toList();
      }
      
      // Sort by floor, then by name in memory
      rooms.sort((a, b) {
        final floorCompare = a.floor.compareTo(b.floor);
        if (floorCompare != 0) return floorCompare;
        return a.name.compareTo(b.name);
      });
      
      return rooms;
    } catch (e) {
      throw Exception('Failed to get rooms: $e');
    }
  }

  /// Get rooms by floor
  Future<List<Room>> getRoomsByFloor(int floor) async {
    try {
      final querySnapshot = await _firestore
          .collection(roomsCollection)
          .where('floor', isEqualTo: floor)
          .where('isActive', isEqualTo: 1)
          .orderBy('name')
          .get();

      return querySnapshot.docs
          .map((doc) => Room.fromMap(doc.data()))
          .toList();
    } catch (e) {
      throw Exception('Failed to get rooms by floor: $e');
    }
  }

  /// Update room
  Future<void> updateRoom(Room room) async {
    try {
      await _firestore.collection(roomsCollection).doc(room.id).update(room.toMap());
    } catch (e) {
      throw Exception('Failed to update room: $e');
    }
  }

  /// Delete room
  Future<void> deleteRoom(String id) async {
    try {
      await _firestore.collection(roomsCollection).doc(id).delete();
    } catch (e) {
      throw Exception('Failed to delete room: $e');
    }
  }

  /// Get rooms stream (real-time updates)
  Stream<List<Room>> getRoomsStream({bool activeOnly = true}) {
    Query query = _firestore.collection(roomsCollection);
    
    if (activeOnly) {
      query = query.where('isActive', isEqualTo: 1);
    }
    
    return query.orderBy('floor').orderBy('name').snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => Room.fromMap(doc.data() as Map<String, dynamic>))
          .toList(),
    );
  }

  // ==================== WIFI ROUTER CRUD ====================

  /// Create a new WiFi router
  Future<String> createWiFiRouter(WiFiRouter router) async {
    try {
      await _firestore.collection(wifiRoutersCollection).doc(router.id).set(router.toMap());
      return router.id;
    } catch (e) {
      throw Exception('Failed to create WiFi router: $e');
    }
  }

  /// Get WiFi router by ID
  Future<WiFiRouter?> getWiFiRouter(String id) async {
    try {
      final doc = await _firestore.collection(wifiRoutersCollection).doc(id).get();
      if (doc.exists && doc.data() != null) {
        return WiFiRouter.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get WiFi router: $e');
    }
  }

  /// Get WiFi router by BSSID
  Future<WiFiRouter?> getWiFiRouterByBSSID(String bssid) async {
    try {
      final querySnapshot = await _firestore
          .collection(wifiRoutersCollection)
          .where('bssid', isEqualTo: bssid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return WiFiRouter.fromMap(querySnapshot.docs.first.data());
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get WiFi router by BSSID: $e');
    }
  }

  /// Get all WiFi routers
  Future<List<WiFiRouter>> getAllWiFiRouters({bool activeOnly = true}) async {
    try {
      // Get all documents without filtering to avoid index issues
      final querySnapshot = await _firestore.collection(wifiRoutersCollection).get();

      var routers = querySnapshot.docs
          .map((doc) {
            try {
              return WiFiRouter.fromMap(doc.data());
            } catch (e) {
              // Skip documents that can't be parsed
              print('Error parsing WiFi router ${doc.id}: $e');
              return null;
            }
          })
          .whereType<WiFiRouter>()
          .toList();
      
      // Filter by active status in memory
      if (activeOnly) {
        routers = routers.where((router) => router.isActive).toList();
      }
      
      // Sort by floor, then by SSID in memory
      routers.sort((a, b) {
        final floorCompare = a.floor.compareTo(b.floor);
        if (floorCompare != 0) return floorCompare;
        return a.ssid.compareTo(b.ssid);
      });
      
      return routers;
    } catch (e) {
      throw Exception('Failed to get WiFi routers: $e');
    }
  }

  /// Get WiFi routers by floor
  Future<List<WiFiRouter>> getWiFiRoutersByFloor(int floor) async {
    try {
      final querySnapshot = await _firestore
          .collection(wifiRoutersCollection)
          .where('floor', isEqualTo: floor)
          .where('isActive', isEqualTo: 1)
          .get();

      return querySnapshot.docs
          .map((doc) => WiFiRouter.fromMap(doc.data()))
          .toList();
    } catch (e) {
      throw Exception('Failed to get WiFi routers by floor: $e');
    }
  }

  /// Update WiFi router
  Future<void> updateWiFiRouter(WiFiRouter router) async {
    try {
      await _firestore.collection(wifiRoutersCollection).doc(router.id).update(router.toMap());
    } catch (e) {
      throw Exception('Failed to update WiFi router: $e');
    }
  }

  /// Delete WiFi router
  Future<void> deleteWiFiRouter(String id) async {
    try {
      await _firestore.collection(wifiRoutersCollection).doc(id).delete();
    } catch (e) {
      throw Exception('Failed to delete WiFi router: $e');
    }
  }

  /// Get WiFi routers stream (real-time updates)
  Stream<List<WiFiRouter>> getWiFiRoutersStream({bool activeOnly = true}) {
    Query query = _firestore.collection(wifiRoutersCollection);
    
    if (activeOnly) {
      query = query.where('isActive', isEqualTo: 1);
    }
    
    return query.orderBy('floor').snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => WiFiRouter.fromMap(doc.data() as Map<String, dynamic>))
          .toList(),
    );
  }

  // ==================== ATTENDANCE CRUD ====================

  /// Create attendance record
  Future<String> createAttendance(Attendance attendance) async {
    try {
      await _firestore.collection(attendanceCollection).doc(attendance.id).set(attendance.toMap());
      return attendance.id;
    } catch (e) {
      throw Exception('Failed to create attendance: $e');
    }
  }

  /// Get attendance by ID
  Future<Attendance?> getAttendance(String id) async {
    try {
      final doc = await _firestore.collection(attendanceCollection).doc(id).get();
      if (doc.exists && doc.data() != null) {
        return Attendance.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get attendance: $e');
    }
  }

  /// Get attendance by user
  Future<List<Attendance>> getAttendanceByUser(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _firestore
          .collection(attendanceCollection)
          .where('userId', isEqualTo: userId);

      if (startDate != null && endDate != null) {
        query = query
            .where('timestamp', isGreaterThanOrEqualTo: startDate.toIso8601String())
            .where('timestamp', isLessThanOrEqualTo: endDate.toIso8601String());
      }

      final querySnapshot = await query.orderBy('timestamp', descending: true).get();

      return querySnapshot.docs
          .map((doc) => Attendance.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to get attendance by user: $e');
    }
  }

  /// Get attendance by room
  Future<List<Attendance>> getAttendanceByRoom(
    String roomId, {
    DateTime? date,
  }) async {
    try {
      Query query = _firestore
          .collection(attendanceCollection)
          .where('roomId', isEqualTo: roomId);

      if (date != null) {
        final startOfDay = DateTime(date.year, date.month, date.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));
        query = query
            .where('timestamp', isGreaterThanOrEqualTo: startOfDay.toIso8601String())
            .where('timestamp', isLessThan: endOfDay.toIso8601String());
      }

      final querySnapshot = await query.orderBy('timestamp', descending: true).get();

      return querySnapshot.docs
          .map((doc) => Attendance.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to get attendance by room: $e');
    }
  }

  /// Get today's attendance for a user in a room
  Future<Attendance?> getTodayAttendance(String userId, String roomId) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final querySnapshot = await _firestore
          .collection(attendanceCollection)
          .where('userId', isEqualTo: userId)
          .where('roomId', isEqualTo: roomId)
          .where('timestamp', isGreaterThanOrEqualTo: startOfDay.toIso8601String())
          .where('timestamp', isLessThan: endOfDay.toIso8601String())
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return Attendance.fromMap(querySnapshot.docs.first.data());
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get today attendance: $e');
    }
  }

  /// Update attendance
  Future<void> updateAttendance(Attendance attendance) async {
    try {
      await _firestore.collection(attendanceCollection).doc(attendance.id).update(attendance.toMap());
    } catch (e) {
      throw Exception('Failed to update attendance: $e');
    }
  }

  /// Get attendance statistics
  Future<Map<String, dynamic>> getAttendanceStats(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final attendances = await getAttendanceByUser(
      userId,
      startDate: startDate,
      endDate: endDate,
    );

    int present = 0;
    int absent = 0;
    int late = 0;

    for (var attendance in attendances) {
      switch (attendance.status) {
        case AttendanceStatus.present:
          present++;
          break;
        case AttendanceStatus.absent:
          absent++;
          break;
        case AttendanceStatus.late:
          late++;
          break;
      }
    }

    return {
      'total': attendances.length,
      'present': present,
      'absent': absent,
      'late': late,
      'percentage': attendances.isEmpty ? 0.0 : (present / attendances.length * 100),
    };
  }

  /// Get attendance stream (real-time updates) for a room
  Stream<List<Attendance>> getAttendanceStreamByRoom(String roomId) {
    return _firestore
        .collection(attendanceCollection)
        .where('roomId', isEqualTo: roomId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Attendance.fromMap(doc.data()))
              .toList(),
        );
  }

  // ==================== UTILITY METHODS ====================

  /// Check if Firestore is accessible
  Future<bool> checkConnection() async {
    try {
      await _firestore.collection(usersCollection).limit(1).get();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Enable offline persistence (called during initialization)
  Future<void> enableOfflinePersistence() async {
    try {
      _firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      // Offline persistence might already be enabled
    }
  }
}












