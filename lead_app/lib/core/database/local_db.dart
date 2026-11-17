import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/lead_model.dart';
import '../constants/app_constants.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(AppConstants.offlineLeadsDb);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE leads (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT,
        googleMapsUrl TEXT,
        city TEXT,
        district TEXT,
        state TEXT,
        lat REAL,
        lng REAL,
        totalRooms INTEGER,
        roomPrice REAL,
        onlineRooms INTEGER,
        offlineRooms INTEGER,
        ownerName TEXT,
        phone TEXT,
        notes TEXT,
        agentNotes TEXT,
        meetingNotesAudioJson TEXT,
        agentNotesAudioJson TEXT,
        interest TEXT,
        meetingRequested INTEGER,
        meetingTime TEXT,
        meetingMode TEXT,
        imagesJson TEXT,
        status TEXT,
        fieldVerified INTEGER,
        documentVerified INTEGER,
        docVerificationStatus TEXT,
        capturedByName TEXT,
        createdAt TEXT,
        isSynced INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE tracking_pings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        accuracy REAL,
        speed REAL,
        heading REAL,
        batteryLevel INTEGER,
        isCharging INTEGER,
        recordedAt TEXT NOT NULL,
        isSynced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          'ALTER TABLE leads ADD COLUMN meetingNotesAudioJson TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE leads ADD COLUMN agentNotesAudioJson TEXT',
        );
      } catch (_) {}
    }
  }

  // Lead operations
  Future<void> insertOrUpdateLead(LeadModel lead) async {
    final db = await database;
    await db.insert(
      'leads',
      lead.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertLeadsBatch(List<LeadModel> leads) async {
    final db = await database;
    final batch = db.batch();
    for (final lead in leads) {
      batch.insert(
        'leads',
        lead.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<LeadModel>> getAllLeads() async {
    final db = await database;
    final result = await db.query('leads', orderBy: 'createdAt DESC');
    return result.map((json) => LeadModel.fromDbMap(json)).toList();
  }

  Future<List<LeadModel>> getUnsyncedLeads() async {
    final db = await database;
    final result = await db.query(
      'leads',
      where: 'isSynced = ?',
      whereArgs: [0],
    );
    return result.map((json) => LeadModel.fromDbMap(json)).toList();
  }

  Future<void> markLeadSynced(String id) async {
    final db = await database;
    await db.update('leads', {'isSynced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteLead(String id) async {
    final db = await database;
    await db.delete('leads', where: 'id = ?', whereArgs: [id]);
  }

  // Ping operations
  Future<void> queueTrackingPing(Map<String, dynamic> ping) async {
    final db = await database;
    await db.insert('tracking_pings', {
      'lat': ping['lat'],
      'lng': ping['lng'],
      'accuracy': ping['accuracy'],
      'speed': ping['speed'],
      'heading': ping['heading'],
      'batteryLevel': ping['batteryLevel'],
      'isCharging': ping['isCharging'] == true ? 1 : 0,
      'recordedAt': ping['recordedAt'] ?? DateTime.now().toIso8601String(),
      'isSynced': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getUnsyncedPings() async {
    final db = await database;
    return await db.query(
      'tracking_pings',
      where: 'isSynced = ?',
      whereArgs: [0],
      limit: 50,
    );
  }

  Future<void> markPingsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update(
      'tracking_pings',
      {'isSynced': 1},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<void> cleanOldPings() async {
    final db = await database;
    await db.delete('tracking_pings', where: 'isSynced = ?', whereArgs: [1]);
  }
}
