import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/foundation.dart';
import '../models/room.dart';
import '../models/wifi_router.dart';
import '../models/attendance.dart';
import '../models/user.dart' as app_user;

class FirebaseService {
  static final FirebaseService instance = FirebaseService._init();
  FirebaseService._init();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;

  // Timeout durations for low network scenarios
  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const Duration _authTimeout = Duration(seconds: 20);
  static const Duration _queryTimeout = Duration(seconds: 25);
  
  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _initialRetryDelay = Duration(seconds: 2);

  // Collections
  static const String usersCollection = 'users';
  static const String roomsCollection = 'rooms';
  static const String wifiRoutersCollection = 'wifi_routers';
  static const String attendanceCollection = 'attendance';

  // ==================== HELPER METHODS ====================

  /// Execute a Firebase operation with retry logic
  Future<T> _executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = _maxRetries,
    Duration timeout = _defaultTimeout,
    String operationName = 'Firebase operation',
  }) async {
    int retryCount = 0;
    Duration retryDelay = _initialRetryDelay;

    while (true) {
      try {
        return await operation().timeout(
          timeout,
          onTimeout: () {
            throw TimeoutException(
              'Operation timed out after ${timeout.inSeconds}s. Please check your internet connection.',
              timeout,
            );
          },
        );
      } catch (e) {
        retryCount++;
        
        // Check if we should retry
        if (retryCount > maxRetries || !_shouldRetry(e)) {
          // Convert to user-friendly error message
          throw _handleFirebaseError(e, operationName);
        }

        // Log retry attempt
        debugPrint(
          '[$operationName] Attempt $retryCount failed: $e. Retrying in ${retryDelay.inSeconds}s...',
        );

        // Wait before retrying
        await Future.delayed(retryDelay);
        
        // Exponential backoff
        retryDelay = retryDelay * 2;
      }
    }
  }

  /// Check if an error is retryable
  bool _shouldRetry(dynamic error) {
    if (error is TimeoutException) return true;
    if (error is auth.FirebaseAuthException) {
      // Retry on network errors
      return error.code == 'network-request-failed' || 
             error.code == 'too-many-requests';
    }
    if (error is FirebaseException) {
      // Retry on network or unavailable errors
      return error.code == 'unavailable' || 
             error.code == 'deadline-exceeded' ||
             error.message?.contains('UNAVAILABLE') == true ||
             error.message?.contains('network') == true;
    }
    // For unknown errors, check the message
    return error.toString().toLowerCase().contains('network') ||
           error.toString().toLowerCase().contains('timeout') ||
           error.toString().toLowerCase().contains('unavailable');
  }

  /// Convert Firebase errors to user-friendly messages
  Exception _handleFirebaseError(dynamic error, String operationName) {
    if (error is TimeoutException) {
      return Exception(
        'Connection timeout. Please check your internet connection and try again.',
      );
    }
    
    if (error is auth.FirebaseAuthException) {
      switch (error.code) {
        case 'network-request-failed':
          return Exception(
            'Network error. Please check your internet connection.',
          );
        case 'too-many-requests':
          return Exception(
            'Too many requests. Please wait a moment and try again.',
          );
        case 'user-not-found':
          return Exception('Account not found.');
        case 'wrong-password':
          return Exception('Incorrect password.');
        case 'email-already-in-use':
          return Exception('Email is already registered.');
        case 'weak-password':
          return Exception('Password is too weak.');
        case 'invalid-email':
          return Exception('Invalid email address.');
        default:
          return Exception('Authentication error: ${error.message}');
      }
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
          return Exception(
            'Service temporarily unavailable. Please try again.',
          );
        case 'deadline-exceeded':
          return Exception(
            'Request took too long. Please check your connection.',
          );
        case 'permission-denied':
          return Exception(
            'Permission denied. Please check your access rights.',
          );
        case 'not-found':
          return Exception('Requested data not found.');
        default:
          return Exception('$operationName failed: ${error.message}');
      }
    }

    // For other errors, return a generic message
    return Exception(
      '$operationName failed. Please check your connection and try again.',
    );
  }

  // ==================== AUTHENTICATION ====================

  /// Sign in with email and password
  Future<auth.User?> signInWithEmailPassword(String email, String password) async {
    return await _executeWithRetry(
      () async {
        final credential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        return credential.user;
      },
      timeout: _authTimeout,
      operationName: 'Sign in',
    );
  }

  /// Sign up with email and password
  Future<auth.User?> signUpWithEmailPassword(String email, String password) async {
    return await _executeWithRetry(
      () async {
        final credential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        return credential.user;
      },
      timeout: _authTimeout,
      operationName: 'Sign up',
    );
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
    return await _executeWithRetry(
      () async {
        await _firestore.collection(usersCollection).doc(user.id).set(user.toMap());
        return user.id;
      },
      timeout: _queryTimeout,
      operationName: 'Create user',
    );
  }

  /// Get user by ID
  Future<app_user.User?> getUser(String id) async {
    return await _executeWithRetry(
      () async {
        final doc = await _firestore.collection(usersCollection).doc(id).get(
          const GetOptions(source: Source.serverAndCache),
        );
        if (doc.exists && doc.data() != null) {
          return app_user.User.fromMap(doc.data()!);
        }
        return null;
      },
      timeout: _queryTimeout,
      operationName: 'Get user',
    );
  }

  /// Get user by email
  Future<app_user.User?> getUserByEmail(String email) async {
    return await _executeWithRetry(
      () async {
        final querySnapshot = await _firestore
            .collection(usersCollection)
            .where('email', isEqualTo: email)
            .limit(1)
            .get(const GetOptions(source: Source.serverAndCache));

        if (querySnapshot.docs.isNotEmpty) {
          return app_user.User.fromMap(querySnapshot.docs.first.data());
        }
        return null;
      },
      timeout: _queryTimeout,
      operationName: 'Get user by email',
    );
  }

  /// Get all users
  Future<List<app_user.User>> getAllUsers() async {
    return await _executeWithRetry(
      () async {
        final querySnapshot = await _firestore
            .collection(usersCollection)
            .orderBy('name')
            .get(const GetOptions(source: Source.serverAndCache));

        return querySnapshot.docs
            .map((doc) => app_user.User.fromMap(doc.data()))
            .toList();
      },
      timeout: _queryTimeout,
      operationName: 'Get all users',
    );
  }

  /// Update user
  Future<void> updateUser(app_user.User user) async {
    return await _executeWithRetry(
      () async {
        await _firestore.collection(usersCollection).doc(user.id).update(user.toMap());
      },
      timeout: _queryTimeout,
      operationName: 'Update user',
    );
  }

  // ==================== ROOM CRUD ====================

  /// Create a new room
  Future<String> createRoom(Room room) async {
    return await _executeWithRetry(
      () async {
        await _firestore.collection(roomsCollection).doc(room.id).set(room.toMap());
        return room.id;
      },
      timeout: _queryTimeout,
      operationName: 'Create room',
    );
  }

  /// Get room by ID
  Future<Room?> getRoom(String id) async {
    return await _executeWithRetry(
      () async {
        final doc = await _firestore.collection(roomsCollection).doc(id).get(
          const GetOptions(source: Source.serverAndCache),
        );
        if (doc.exists && doc.data() != null) {
          return Room.fromMap(doc.data()!);
        }
        return null;
      },
      timeout: _queryTimeout,
      operationName: 'Get room',
    );
  }

  /// Get all rooms
  Future<List<Room>> getAllRooms({bool activeOnly = true}) async {
    return await _executeWithRetry(
      () async {
        // Get all documents without orderBy to avoid index issues
        // Use serverAndCache to work with cached data when offline
        final querySnapshot = await _firestore
            .collection(roomsCollection)
            .get(const GetOptions(source: Source.serverAndCache));

        var rooms = querySnapshot.docs
            .map((doc) {
              try {
                return Room.fromMap(doc.data());
              } catch (e) {
                // Skip documents that can't be parsed
                debugPrint('Error parsing room ${doc.id}: $e');
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
      },
      timeout: _queryTimeout,
      operationName: 'Get all rooms',
    );
  }

  /// Get rooms by floor
  Future<List<Room>> getRoomsByFloor(int floor) async {
    return await _executeWithRetry(
      () async {
        final querySnapshot = await _firestore
            .collection(roomsCollection)
            .where('floor', isEqualTo: floor)
            .where('isActive', isEqualTo: 1)
            .orderBy('name')
            .get(const GetOptions(source: Source.serverAndCache));

        return querySnapshot.docs
            .map((doc) => Room.fromMap(doc.data()))
            .toList();
      },
      timeout: _queryTimeout,
      operationName: 'Get rooms by floor',
    );
  }

  /// Update room
  Future<void> updateRoom(Room room) async {
    return await _executeWithRetry(
      () async {
        await _firestore.collection(roomsCollection).doc(room.id).update(room.toMap());
      },
      timeout: _queryTimeout,
      operationName: 'Update room',
    );
  }

  /// Delete room
  Future<void> deleteRoom(String id) async {
    return await _executeWithRetry(
      () async {
        await _firestore.collection(roomsCollection).doc(id).delete();
      },
      timeout: _queryTimeout,
      operationName: 'Delete room',
    );
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
    return await _executeWithRetry(
      () async {
        await _firestore.collection(wifiRoutersCollection).doc(router.id).set(router.toMap());
        return router.id;
      },
      timeout: _queryTimeout,
      operationName: 'Create WiFi router',
    );
  }

  /// Get WiFi router by ID
  Future<WiFiRouter?> getWiFiRouter(String id) async {
    return await _executeWithRetry(
      () async {
        final doc = await _firestore.collection(wifiRoutersCollection).doc(id).get(
          const GetOptions(source: Source.serverAndCache),
        );
        if (doc.exists && doc.data() != null) {
          return WiFiRouter.fromMap(doc.data()!);
        }
        return null;
      },
      timeout: _queryTimeout,
      operationName: 'Get WiFi router',
    );
  }

  /// Get WiFi router by BSSID
  Future<WiFiRouter?> getWiFiRouterByBSSID(String bssid) async {
    return await _executeWithRetry(
      () async {
        final querySnapshot = await _firestore
            .collection(wifiRoutersCollection)
            .where('bssid', isEqualTo: bssid)
            .limit(1)
            .get(const GetOptions(source: Source.serverAndCache));

        if (querySnapshot.docs.isNotEmpty) {
          return WiFiRouter.fromMap(querySnapshot.docs.first.data());
        }
        return null;
      },
      timeout: _queryTimeout,
      operationName: 'Get WiFi router by BSSID',
    );
  }

  /// Get all WiFi routers
  Future<List<WiFiRouter>> getAllWiFiRouters({bool activeOnly = true}) async {
    return await _executeWithRetry(
      () async {
        // Get all documents without filtering to avoid index issues
        final querySnapshot = await _firestore
            .collection(wifiRoutersCollection)
            .get(const GetOptions(source: Source.serverAndCache));

        var routers = querySnapshot.docs
            .map((doc) {
              try {
                return WiFiRouter.fromMap(doc.data());
              } catch (e) {
                // Skip documents that can't be parsed
                debugPrint('Error parsing WiFi router ${doc.id}: $e');
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
      },
      timeout: _queryTimeout,
      operationName: 'Get all WiFi routers',
    );
  }

  /// Get WiFi routers by floor
  Future<List<WiFiRouter>> getWiFiRoutersByFloor(int floor) async {
    return await _executeWithRetry(
      () async {
        final querySnapshot = await _firestore
            .collection(wifiRoutersCollection)
            .where('floor', isEqualTo: floor)
            .where('isActive', isEqualTo: 1)
            .get(const GetOptions(source: Source.serverAndCache));

        return querySnapshot.docs
            .map((doc) => WiFiRouter.fromMap(doc.data()))
            .toList();
      },
      timeout: _queryTimeout,
      operationName: 'Get WiFi routers by floor',
    );
  }

  /// Update WiFi router
  Future<void> updateWiFiRouter(WiFiRouter router) async {
    return await _executeWithRetry(
      () async {
        await _firestore.collection(wifiRoutersCollection).doc(router.id).update(router.toMap());
      },
      timeout: _queryTimeout,
      operationName: 'Update WiFi router',
    );
  }

  /// Delete WiFi router
  Future<void> deleteWiFiRouter(String id) async {
    return await _executeWithRetry(
      () async {
        await _firestore.collection(wifiRoutersCollection).doc(id).delete();
      },
      timeout: _queryTimeout,
      operationName: 'Delete WiFi router',
    );
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
    return await _executeWithRetry(
      () async {
        await _firestore.collection(attendanceCollection).doc(attendance.id).set(attendance.toMap());
        return attendance.id;
      },
      timeout: _queryTimeout,
      maxRetries: 5, // Higher retries for attendance - critical operation
      operationName: 'Mark attendance',
    );
  }

  /// Get attendance by ID
  Future<Attendance?> getAttendance(String id) async {
    return await _executeWithRetry(
      () async {
        final doc = await _firestore.collection(attendanceCollection).doc(id).get(
          const GetOptions(source: Source.serverAndCache),
        );
        if (doc.exists && doc.data() != null) {
          return Attendance.fromMap(doc.data()!);
        }
        return null;
      },
      timeout: _queryTimeout,
      operationName: 'Get attendance',
    );
  }

  /// Get attendance by user
  Future<List<Attendance>> getAttendanceByUser(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return await _executeWithRetry(
      () async {
        Query query = _firestore
            .collection(attendanceCollection)
            .where('userId', isEqualTo: userId);

        if (startDate != null && endDate != null) {
          query = query
              .where('timestamp', isGreaterThanOrEqualTo: startDate.toIso8601String())
              .where('timestamp', isLessThanOrEqualTo: endDate.toIso8601String());
        }

        final querySnapshot = await query
            .orderBy('timestamp', descending: true)
            .get(const GetOptions(source: Source.serverAndCache));

        return querySnapshot.docs
            .map((doc) => Attendance.fromMap(doc.data() as Map<String, dynamic>))
            .toList();
      },
      timeout: _queryTimeout,
      operationName: 'Get attendance by user',
    );
  }

  /// Get attendance by room
  Future<List<Attendance>> getAttendanceByRoom(
    String roomId, {
    DateTime? date,
  }) async {
    return await _executeWithRetry(
      () async {
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

        final querySnapshot = await query
            .orderBy('timestamp', descending: true)
            .get(const GetOptions(source: Source.serverAndCache));

        return querySnapshot.docs
            .map((doc) => Attendance.fromMap(doc.data() as Map<String, dynamic>))
            .toList();
      },
      timeout: _queryTimeout,
      operationName: 'Get attendance by room',
    );
  }

  /// Get today's attendance for a user in a room
  Future<Attendance?> getTodayAttendance(String userId, String roomId) async {
    return await _executeWithRetry(
      () async {
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
            .get(const GetOptions(source: Source.serverAndCache));

        if (querySnapshot.docs.isNotEmpty) {
          return Attendance.fromMap(querySnapshot.docs.first.data());
        }
        return null;
      },
      timeout: _queryTimeout,
      operationName: 'Check today attendance',
    );
  }

  /// Update attendance
  Future<void> updateAttendance(Attendance attendance) async {
    return await _executeWithRetry(
      () async {
        await _firestore.collection(attendanceCollection).doc(attendance.id).update(attendance.toMap());
      },
      timeout: _queryTimeout,
      operationName: 'Update attendance',
    );
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
      await _firestore.collection(usersCollection).limit(1).get().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Connection check timeout'),
      );
      return true;
    } catch (e) {
      debugPrint('Connection check failed: $e');
      return false;
    }
  }

  /// Check network connectivity and return status message
  Future<Map<String, dynamic>> getConnectionStatus() async {
    try {
      final startTime = DateTime.now();
      await _firestore.collection(usersCollection).limit(1).get(
        const GetOptions(source: Source.server),
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );
      final latency = DateTime.now().difference(startTime).inMilliseconds;
      
      String quality;
      if (latency < 500) {
        quality = 'Good';
      } else if (latency < 2000) {
        quality = 'Fair';
      } else {
        quality = 'Slow';
      }
      
      return {
        'connected': true,
        'latency': latency,
        'quality': quality,
      };
    } catch (e) {
      // Check if we can use cache
      try {
        await _firestore.collection(usersCollection).limit(1).get(
          const GetOptions(source: Source.cache),
        );
        return {
          'connected': false,
          'cacheAvailable': true,
          'message': 'Offline - using cached data',
        };
      } catch (_) {
        return {
          'connected': false,
          'cacheAvailable': false,
          'message': 'No connection and no cached data',
        };
      }
    }
  }

  /// Enable offline persistence with optimized settings (called during initialization)
  Future<void> enableOfflinePersistence() async {
    try {
      // Configure Firestore settings for optimal offline performance
      _firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED, // Unlimited cache for full offline support
      );
      
      // Enable network (in case it was disabled)
      await _firestore.enableNetwork();
      
      debugPrint('✓ Firebase offline persistence enabled');
    } catch (e) {
      // Settings might already be configured
      debugPrint('Offline persistence configuration: $e');
    }
  }

  /// Disable network (for testing offline scenarios)
  Future<void> disableNetwork() async {
    try {
      await _firestore.disableNetwork();
      debugPrint('Network disabled - using cache only');
    } catch (e) {
      debugPrint('Failed to disable network: $e');
    }
  }

  /// Enable network
  Future<void> enableNetwork() async {
    try {
      await _firestore.enableNetwork();
      debugPrint('Network enabled');
    } catch (e) {
      debugPrint('Failed to enable network: $e');
    }
  }

  /// Clear local cache (use cautiously)
  Future<void> clearCache() async {
    try {
      await _firestore.clearPersistence();
      debugPrint('Cache cleared successfully');
    } catch (e) {
      debugPrint('Failed to clear cache: $e');
      rethrow;
    }
  }
}












