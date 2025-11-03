# Changelog

All notable changes to GeoAttendance will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-10-29

### Added
- Initial release of GeoAttendance system
- Admin functionality for room and WiFi router management
- Student attendance marking with location verification
- Dual verification system (GPS + WiFi)
- Room coordinate calculator based on center point and dimensions
- SQLite local database for data persistence
- Multi-floor and multi-building support
- Attendance statistics and history
- Permission handling for location and WiFi
- Real-time location verification (10-15 seconds)
- Three accuracy levels: High (≤10m), Medium (10-30m), Low (>30m)
- WiFi signal strength based verification
- Duplicate attendance prevention
- Material Design 3 UI
- Comprehensive error handling and user feedback

### Features

#### Admin Features
- **Room Management**: Add, view, and manage classrooms
- **Coordinate Calculator**: Automatic boundary calculation from center + dimensions
- **WiFi Router Management**: Scan, add, and assign routers to rooms
- **Multi-floor Support**: Up to 6 floors with 10 rooms per floor
- **Router Assignment**: Assign one router to two rooms

#### Student Features
- **Room Selection**: Browse available classrooms by floor
- **Location Verification**: Smart GPS + WiFi verification
- **Attendance Marking**: Quick 10-15 second verification process
- **Attendance History**: View past attendance records
- **Statistics**: View attendance percentage and metrics

#### Technical Features
- **Haversine Formula**: Accurate distance calculation
- **Ray Casting Algorithm**: Point-in-polygon detection
- **Safety Margins**: 5m buffer for room boundaries
- **Multiple GPS Attempts**: Up to 5 samples for best accuracy
- **WiFi Fallback**: Automatic fallback when GPS is unreliable
- **Signal Strength Filtering**: Configurable threshold (default: -70 dBm)
- **Location Caching**: Best position tracking during verification

### Architecture
- **Framework**: Flutter 3.9.2+
- **State Management**: Provider
- **Local Database**: SQLite (sqflite)
- **Location Services**: Geolocator 11.0.0+
- **WiFi Scanning**: wifi_scan 0.4.1+
- **Permissions**: permission_handler 11.3.1+

### Supported Platforms
- Android 10+ (API level 29+)
- iOS 14+

### Known Issues
None reported in initial release.

### Security
- Location data stored locally only
- No external data transmission
- Permission-based access control
- Secure SQLite database

---

## [Unreleased]

### Planned Features
- Cloud sync with Firebase
- Export attendance reports (PDF/Excel)
- Push notifications for class schedules
- QR code backup verification
- Biometric authentication
- Multi-institution support
- Advanced analytics dashboard
- Geofencing for auto check-in
- Offline mode improvements
- Batch attendance operations

### Under Consideration
- Student self-registration
- Email notifications
- Calendar integration
- Face recognition verification
- Bluetooth beacon support
- NFC tag verification
- REST API for integration
- Web admin dashboard

