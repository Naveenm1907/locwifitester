# Network Resilience - Quick Reference Guide

## 🚀 Quick Start

Your app now automatically handles low network conditions! Here's what you need to know:

## ✅ What's Already Working

### Automatic Features (No Code Changes Needed)
1. **All Firebase operations** have 30s timeout + 3 retries
2. **Offline caching** is enabled (unlimited cache)
3. **Connection banner** shows when offline
4. **Smart error messages** for network issues
5. **Exponential backoff** retry logic

## 📱 User Experience Flow

```
User Action → Loading (with timeout feedback)
             ↓
             Network Call (30s timeout)
             ↓
         Failed? → Retry #1 (2s delay)
             ↓
         Failed? → Retry #2 (4s delay)  
             ↓
         Failed? → Retry #3 (8s delay)
             ↓
         Failed? → Clear error message
             
         OR
             
         Success → Cache data → Update UI
```

## 🛠️ Adding Network Awareness to New Features

### When Adding New Firebase Operations

```dart
// ✅ GOOD - Uses retry logic automatically
Future<void> myNewOperation() async {
  return await _executeWithRetry(
    () async {
      await _firestore.collection('myCollection').get(
        const GetOptions(source: Source.serverAndCache),  // Use cache!
      );
    },
    timeout: _queryTimeout,
    operationName: 'My operation',  // Shows in error messages
  );
}

// ❌ BAD - No retry, no timeout, no cache
Future<void> myNewOperation() async {
  await _firestore.collection('myCollection').get();
}
```

### When Adding New Screens

```dart
// Add connection banner at top
import '../../widgets/connection_status_banner.dart';

Widget build(BuildContext context) {
  return Scaffold(
    body: Column(
      children: [
        const ConnectionStatusBanner(),  // ← Add this
        Expanded(
          child: YourContent(),
        ),
      ],
    ),
  );
}
```

### When Showing Loading States

```dart
// Use LoadingWithTimeout for better UX
import '../../widgets/connection_status_banner.dart';

if (isLoading) {
  return const LoadingWithTimeout(
    message: 'Loading your data...',
    slowThreshold: Duration(seconds: 5),  // Shows warning after 5s
  );
}
```

## 🔍 Testing Network Issues

### Simulate Slow Network

**Android Studio:**
```
Tools → AVD Manager → Edit Device → 
Show Advanced Settings → Network Speed → EDGE (237/14kbps)
```

**Chrome DevTools (for web):**
```
F12 → Network Tab → Throttling → Slow 3G
```

**iOS Simulator:**
```
Settings → Developer → Network Link Conditioner → 3G
```

### Simulate Offline

```dart
// In code (for testing)
await FirebaseService.instance.disableNetwork();  // Go offline
// ... test offline functionality ...
await FirebaseService.instance.enableNetwork();   // Go online
```

## 📊 Connection Status

### Check Connection in Code

```dart
// Quick boolean check
bool connected = await FirebaseService.instance.checkConnection();

// Detailed status
Map<String, dynamic> status = await FirebaseService.instance.getConnectionStatus();
/*
Returns:
{
  'connected': true/false,
  'latency': 234,  // milliseconds
  'quality': 'Good' / 'Fair' / 'Slow',
  'cacheAvailable': true/false,
  'message': '...'
}
*/
```

### Display Connection Status

```dart
// Already available in AppState
Consumer<AppState>(
  builder: (context, appState, child) {
    if (!appState.isConnected) {
      return Text('Offline');
    }
    if (appState.lastSuccessfulSync != null) {
      return Text('Synced ${timeAgo(appState.lastSuccessfulSync)}');
    }
    return Text('Online');
  },
)
```

## 🎯 Common Scenarios

### Scenario 1: Student Marks Attendance (Slow Network)

**What Happens:**
1. Loading spinner shows
2. After 15s, countdown timer shows  
3. System retries 5 times (critical operation)
4. If fails, shows: "Connection timeout. Check your network."
5. User can retry manually

### Scenario 2: Admin Loads Rooms (Offline)

**What Happens:**
1. Connection banner appears (orange)
2. Rooms load from cache instantly
3. Banner shows: "Using cached data from 10m ago"
4. User can click refresh when online
5. Auto-sync when connection restored

### Scenario 3: Login (Poor Connection)

**What Happens:**
1. Loading spinner starts
2. After 10s, shows: "Taking longer than usual..."
3. System retries 3 times automatically
4. Success or clear error message
5. User sees what went wrong

## ⚙️ Configuration Cheat Sheet

### File: `lib/services/firebase_service.dart`

```dart
// Timeouts
_defaultTimeout = Duration(seconds: 30)  // General operations
_authTimeout = Duration(seconds: 20)     // Login/signup
_queryTimeout = Duration(seconds: 25)    // Database queries

// Retries  
_maxRetries = 3                          // Normal operations
_initialRetryDelay = Duration(seconds: 2) // First retry wait

// Cache
cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED  // Offline storage
persistenceEnabled: true                       // Enable caching
```

## 🐛 Debugging Network Issues

### Enable Network Logging

Firebase automatically logs to console:
```
[Get all rooms] Attempt 1 failed: Network error. Retrying in 2s...
[Get all rooms] Attempt 2 failed: Network error. Retrying in 4s...
✓ Firebase offline persistence enabled
Connection check failed: TimeoutException
```

### Check What's Cached

```dart
// Force cache-only read (for debugging)
final snapshot = await _firestore
  .collection('rooms')
  .get(const GetOptions(source: Source.cache));
print('Cached rooms: ${snapshot.docs.length}');
```

## 🚨 Error Messages Reference

| Error Message | Meaning | User Action |
|--------------|---------|-------------|
| "Connection timeout" | Network request took > 30s | Check internet |
| "Service temporarily unavailable" | Firebase backend issue | Wait & retry |
| "Request took too long" | Slow network | Be patient or retry |
| "Network error" | No connection | Check WiFi/mobile data |
| "Using cached data" | Offline but have cache | Continue working |

## 💡 Best Practices

### DO ✅
- Always use `Source.serverAndCache` for reads
- Let `_executeWithRetry` handle operations  
- Show connection banner on all screens
- Use `LoadingWithTimeout` for long operations
- Test with throttled network
- Provide clear error messages

### DON'T ❌
- Don't bypass retry logic for convenience
- Don't use `Source.server` (forces network)
- Don't show generic "Error" messages
- Don't forget offline caching
- Don't make network calls without timeouts
- Don't ignore connection status

## 📞 Quick Commands

```dart
// Check connection
await FirebaseService.instance.checkConnection()

// Get connection details  
await FirebaseService.instance.getConnectionStatus()

// Clear cache (caution!)
await FirebaseService.instance.clearCache()

// Test offline mode
await FirebaseService.instance.disableNetwork()

// Resume network
await FirebaseService.instance.enableNetwork()

// Refresh data
await appState.loadRooms()
await appState.loadWiFiRouters()

// Check connectivity
await appState.checkConnectivity()
```

## 🔗 Files Changed

Core files with network resilience:
- ✅ `lib/services/firebase_service.dart` - Retry logic & timeouts
- ✅ `lib/providers/app_state.dart` - Connection tracking
- ✅ `lib/widgets/connection_status_banner.dart` - UI feedback
- ✅ `lib/screens/admin/admin_home_screen.dart` - Connection banner
- ✅ `lib/screens/student/student_home_screen.dart` - Connection banner  
- ✅ `lib/screens/auth/login_screen.dart` - Timeout feedback

## 📚 Additional Resources

- [Firebase Offline Persistence](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
- [Flutter Connectivity](https://pub.dev/packages/connectivity_plus) (optional package)
- See `LOW_NETWORK_IMPROVEMENTS.md` for detailed documentation

---

**Need Help?** Check `LOW_NETWORK_IMPROVEMENTS.md` for comprehensive documentation!

