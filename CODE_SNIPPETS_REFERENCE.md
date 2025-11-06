# Code Snippets Reference

Quick reference for all critical code blocks needed to replicate the app.

---

## 🔥 Firebase Service - Critical Code Blocks

### 1. Imports & Constants

```dart
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
```

### 2. Retry Logic Method (CRITICAL)

```dart
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
```

### 3. Retry Detection Method

```dart
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
```

### 4. Error Handling Method

```dart
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
```

### 5. Authentication Methods Pattern

```dart
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
```

### 6. Firestore Read Pattern (ALWAYS USE THIS)

```dart
  /// Get room by ID
  Future<Room?> getRoom(String id) async {
    return await _executeWithRetry(
      () async {
        final doc = await _firestore.collection(roomsCollection).doc(id).get(
          const GetOptions(source: Source.serverAndCache),  // CRITICAL: Use cache!
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
```

### 7. Firestore Write Pattern

```dart
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
```

### 8. Query with Filters Pattern

```dart
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
```

### 9. Offline Persistence Setup

```dart
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
```

### 10. Connection Status Check

```dart
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
```

---

## 🎯 App State Provider - Critical Code Blocks

### 1. Class Structure

```dart
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
```

### 2. Load Method with Error Handling

```dart
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
```

### 3. Connectivity Check

```dart
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
```

---

## 🎨 UI Components - Critical Code Blocks

### 1. Connection Status Banner

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// A banner that shows connection status at the top of screens
class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // Don't show banner if connected
        if (appState.isConnected) {
          return const SizedBox.shrink();
        }

        // Show offline banner
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange.shade100,
            border: Border(
              bottom: BorderSide(
                color: Colors.orange.shade300,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off,
                color: Colors.orange.shade900,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No Internet Connection',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    if (appState.lastSuccessfulSync != null)
                      Text(
                        'Using cached data from ${_formatTime(appState.lastSuccessfulSync!)}',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 11,
                        ),
                      )
                    else
                      Text(
                        'Some features may be limited',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: Colors.orange.shade900,
                  size: 20,
                ),
                onPressed: () async {
                  await appState.checkConnectivity();
                  if (appState.isConnected) {
                    // Refresh data
                    await Future.wait([
                      appState.loadRooms(silent: true),
                      appState.loadWiFiRouters(silent: true),
                    ]);
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Check connection',
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
```

### 2. Loading with Timeout Widget

```dart
/// A loading indicator with timeout message for slow networks
class LoadingWithTimeout extends StatefulWidget {
  final String message;
  final Duration slowThreshold;

  const LoadingWithTimeout({
    super.key,
    this.message = 'Loading...',
    this.slowThreshold = const Duration(seconds: 5),
  });

  @override
  State<LoadingWithTimeout> createState() => _LoadingWithTimeoutState();
}

class _LoadingWithTimeoutState extends State<LoadingWithTimeout> {
  bool _isSlow = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.slowThreshold, () {
      if (mounted) {
        setState(() {
          _isSlow = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            widget.message,
            style: const TextStyle(fontSize: 16),
          ),
          if (_isSlow) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.slow_motion_video,
                    color: Colors.orange.shade700,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Taking longer than usual...',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Please check your internet connection',
                    style: TextStyle(
                      color: Colors.orange.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

---

## 📱 Main App - Critical Code Blocks

### 1. Main Function

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'providers/app_state.dart';
import 'screens/auth/login_screen.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Enable offline persistence for Firestore (CRITICAL!)
  await FirebaseService.instance.enableOfflinePersistence();
  
  runApp(const MyApp());
}
```

### 2. App Widget with Provider

```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'GeoAttendance',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: _getInitialScreen(),
      ),
    );
  }

  Widget _getInitialScreen() {
    return StreamBuilder<auth.User?>(
      stream: FirebaseService.instance.authStateChanges,
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If user is logged in, show home screen based on role
        if (snapshot.hasData && snapshot.data != null) {
          return const LoginScreen(); // Login screen handles navigation
        }

        // User is not logged in
        return const LoginScreen();
      },
    );
  }
}
```

---

## 🎯 Screen Integration Pattern

### How to Add Connection Banner to Any Screen

```dart
import '../../widgets/connection_status_banner.dart';

Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Your Screen'),
    ),
    body: Column(
      children: [
        const ConnectionStatusBanner(),  // Add this line
        Expanded(
          child: YourContent(),
        ),
      ],
    ),
  );
}
```

### How to Use Loading with Timeout

```dart
if (appState.isLoading) {
  return const LoadingWithTimeout(
    message: 'Loading your data...',
    slowThreshold: Duration(seconds: 5),
  );
}
```

### How to Use App State in Widgets

```dart
Consumer<AppState>(
  builder: (context, appState, child) {
    if (!appState.isConnected) {
      // Handle offline state
    }
    return YourWidget();
  },
)
```

---

## ⚙️ Android Configuration

### build.gradle.kts (Project level)

```kotlin
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.0")
        // Add this:
        classpath("com.google.gms:google-services:4.4.0")
    }
}
```

### build.gradle.kts (App level)

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // Add this:
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.locwifitester"
    compileSdk = 34
    
    defaultConfig {
        applicationId = "com.example.locwifitester"
        minSdk = 21  // IMPORTANT: Minimum 21 for WiFi scanning
        targetSdk = 34
    }
}
```

---

## 📝 Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Rooms collection
    match /rooms/{roomId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    
    // WiFi routers collection
    match /wifi_routers/{routerId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    
    // Attendance collection
    match /attendance/{attendanceId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if false;
      allow delete: if false;
    }
  }
}
```

---

## ✅ Quick Copy Checklist

When copying code, ensure you copy:

1. ✅ All imports
2. ✅ All constants
3. ✅ Retry logic methods
4. ✅ Error handling methods
5. ✅ Offline persistence setup
6. ✅ Connection status checking
7. ✅ UI components (banner, loading)
8. ✅ App state structure
9. ✅ Main app initialization
10. ✅ Screen integration patterns

---

**Note**: These are the critical code blocks. For complete implementations, refer to the actual files in the project.

**Last Updated**: 2024  
**Version**: 1.0.0

