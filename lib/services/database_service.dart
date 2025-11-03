import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/room.dart';
import '../models/wifi_router.dart';
import '../models/attendance.dart';
import '../models/user.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('attendance_system.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2, // Incremented version for schema update
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns for floor detection
      await db.execute('ALTER TABLE wifi_routers ADD COLUMN sameFloorMinSignal INTEGER NOT NULL DEFAULT -55');
      await db.execute('ALTER TABLE wifi_routers ADD COLUMN differentFloorMaxSignal INTEGER NOT NULL DEFAULT -75');
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        studentId TEXT,
        role TEXT NOT NULL,
        department TEXT,
        year TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT
      )
    ''');

    // Rooms table
    await db.execute('''
      CREATE TABLE rooms (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        building TEXT NOT NULL,
        floor INTEGER NOT NULL,
        centerLatitude REAL NOT NULL,
        centerLongitude REAL NOT NULL,
        widthMeters REAL NOT NULL,
        lengthMeters REAL NOT NULL,
        ne_lat REAL NOT NULL,
        ne_lng REAL NOT NULL,
        nw_lat REAL NOT NULL,
        nw_lng REAL NOT NULL,
        se_lat REAL NOT NULL,
        se_lng REAL NOT NULL,
        sw_lat REAL NOT NULL,
        sw_lng REAL NOT NULL,
        assignedWifiId TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        FOREIGN KEY (assignedWifiId) REFERENCES wifi_routers(id)
      )
    ''');

    // WiFi Routers table
    await db.execute('''
      CREATE TABLE wifi_routers (
        id TEXT PRIMARY KEY,
        ssid TEXT NOT NULL,
        bssid TEXT NOT NULL UNIQUE,
        building TEXT NOT NULL,
        floor INTEGER NOT NULL,
        location TEXT,
        signalStrengthThreshold INTEGER NOT NULL DEFAULT -70,
        sameFloorMinSignal INTEGER NOT NULL DEFAULT -55,
        differentFloorMaxSignal INTEGER NOT NULL DEFAULT -75,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT
      )
    ''');

    // Attendance table
    await db.execute('''
      CREATE TABLE attendance (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        roomId TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL,
        verificationMethod TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        accuracy REAL,
        detectedWifiSignals TEXT,
        strongestSignalStrength INTEGER,
        isVerified INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (userId) REFERENCES users(id),
        FOREIGN KEY (roomId) REFERENCES rooms(id)
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_attendance_user ON attendance(userId)');
    await db.execute('CREATE INDEX idx_attendance_room ON attendance(roomId)');
    await db.execute('CREATE INDEX idx_attendance_timestamp ON attendance(timestamp)');
    await db.execute('CREATE INDEX idx_rooms_floor ON rooms(floor)');
    await db.execute('CREATE INDEX idx_wifi_floor ON wifi_routers(floor)');
  }

  // User CRUD operations
  Future<String> createUser(User user) async {
    final db = await database;
    await db.insert('users', user.toMap());
    return user.id;
  }

  Future<User?> getUser(String id) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  Future<User?> getUserByEmail(String email) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );

    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  Future<List<User>> getAllUsers() async {
    final db = await database;
    final maps = await db.query('users', orderBy: 'name ASC');
    return maps.map((map) => User.fromMap(map)).toList();
  }

  Future<int> updateUser(User user) async {
    final db = await database;
    return db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  // Room CRUD operations
  Future<String> createRoom(Room room) async {
    final db = await database;
    await db.insert('rooms', room.toMap());
    return room.id;
  }

  Future<Room?> getRoom(String id) async {
    final db = await database;
    final maps = await db.query(
      'rooms',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Room.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Room>> getAllRooms({bool activeOnly = true}) async {
    final db = await database;
    final maps = await db.query(
      'rooms',
      where: activeOnly ? 'isActive = ?' : null,
      whereArgs: activeOnly ? [1] : null,
      orderBy: 'floor ASC, name ASC',
    );
    return maps.map((map) => Room.fromMap(map)).toList();
  }

  Future<List<Room>> getRoomsByFloor(int floor) async {
    final db = await database;
    final maps = await db.query(
      'rooms',
      where: 'floor = ? AND isActive = ?',
      whereArgs: [floor, 1],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Room.fromMap(map)).toList();
  }

  Future<int> updateRoom(Room room) async {
    final db = await database;
    return db.update(
      'rooms',
      room.toMap(),
      where: 'id = ?',
      whereArgs: [room.id],
    );
  }

  Future<int> deleteRoom(String id) async {
    final db = await database;
    return db.delete(
      'rooms',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // WiFi Router CRUD operations
  Future<String> createWiFiRouter(WiFiRouter router) async {
    final db = await database;
    await db.insert('wifi_routers', router.toMap());
    return router.id;
  }

  Future<WiFiRouter?> getWiFiRouter(String id) async {
    final db = await database;
    final maps = await db.query(
      'wifi_routers',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return WiFiRouter.fromMap(maps.first);
    }
    return null;
  }

  Future<WiFiRouter?> getWiFiRouterByBSSID(String bssid) async {
    final db = await database;
    final maps = await db.query(
      'wifi_routers',
      where: 'bssid = ?',
      whereArgs: [bssid],
    );

    if (maps.isNotEmpty) {
      return WiFiRouter.fromMap(maps.first);
    }
    return null;
  }

  Future<List<WiFiRouter>> getAllWiFiRouters({bool activeOnly = true}) async {
    final db = await database;
    final maps = await db.query(
      'wifi_routers',
      where: activeOnly ? 'isActive = ?' : null,
      whereArgs: activeOnly ? [1] : null,
      orderBy: 'floor ASC',
    );
    return maps.map((map) => WiFiRouter.fromMap(map)).toList();
  }

  Future<List<WiFiRouter>> getWiFiRoutersByFloor(int floor) async {
    final db = await database;
    final maps = await db.query(
      'wifi_routers',
      where: 'floor = ? AND isActive = ?',
      whereArgs: [floor, 1],
    );
    return maps.map((map) => WiFiRouter.fromMap(map)).toList();
  }

  Future<int> updateWiFiRouter(WiFiRouter router) async {
    final db = await database;
    return db.update(
      'wifi_routers',
      router.toMap(),
      where: 'id = ?',
      whereArgs: [router.id],
    );
  }

  Future<int> deleteWiFiRouter(String id) async {
    final db = await database;
    return db.delete(
      'wifi_routers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Attendance CRUD operations
  Future<String> createAttendance(Attendance attendance) async {
    final db = await database;
    await db.insert('attendance', attendance.toMap());
    return attendance.id;
  }

  Future<Attendance?> getAttendance(String id) async {
    final db = await database;
    final maps = await db.query(
      'attendance',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Attendance.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Attendance>> getAttendanceByUser(String userId, {DateTime? startDate, DateTime? endDate}) async {
    final db = await database;
    String where = 'userId = ?';
    List<dynamic> whereArgs = [userId];

    if (startDate != null && endDate != null) {
      where += ' AND timestamp >= ? AND timestamp <= ?';
      whereArgs.addAll([startDate.toIso8601String(), endDate.toIso8601String()]);
    }

    final maps = await db.query(
      'attendance',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => Attendance.fromMap(map)).toList();
  }

  Future<List<Attendance>> getAttendanceByRoom(String roomId, {DateTime? date}) async {
    final db = await database;
    String where = 'roomId = ?';
    List<dynamic> whereArgs = [roomId];

    if (date != null) {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      where += ' AND timestamp >= ? AND timestamp < ?';
      whereArgs.addAll([startOfDay.toIso8601String(), endOfDay.toIso8601String()]);
    }

    final maps = await db.query(
      'attendance',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => Attendance.fromMap(map)).toList();
  }

  Future<Attendance?> getTodayAttendance(String userId, String roomId) async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      'attendance',
      where: 'userId = ? AND roomId = ? AND timestamp >= ? AND timestamp < ?',
      whereArgs: [
        userId,
        roomId,
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String(),
      ],
    );

    if (maps.isNotEmpty) {
      return Attendance.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateAttendance(Attendance attendance) async {
    final db = await database;
    return db.update(
      'attendance',
      attendance.toMap(),
      where: 'id = ?',
      whereArgs: [attendance.id],
    );
  }

  // Statistics and reports
  Future<Map<String, dynamic>> getAttendanceStats(String userId, {DateTime? startDate, DateTime? endDate}) async {
    final attendances = await getAttendanceByUser(userId, startDate: startDate, endDate: endDate);
    
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

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}

