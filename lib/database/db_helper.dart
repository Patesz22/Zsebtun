import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// @description Singleton helper class managing the local SQLite database for classes and exams.
class DatabaseHelper {

  DatabaseHelper._init();
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  /// @description Returns the active database instance, initializing it if necessary.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('zsebtun_calendar_v2.db');
    return _database!;
  }

  /// @description Opens or creates the SQLite database file at the system database path.
  /// @param filePath The name of the database file.
  /// @returns The opened Database instance.
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return openDatabase(path, version: 1, onCreate: _createDB);
  }

  /// @description Creates the initial database schema with all required columns.
  /// @param db The SQLite database instance.
  /// @param version The schema version number.
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        className TEXT,
        classType TEXT,
        teachers TEXT, 
        rooms TEXT,
        eventType TEXT,
        dtstart TEXT,
        dtend TEXT,
        isZh INTEGER DEFAULT 0,
        color INTEGER
      )
    ''');
  }

  /// @description Ensures the isZh and color columns exist on legacy tables.
  /// @param db The SQLite database instance.
  Future<void> _checkZhColumns(Database db) async {
    try {
      await db.execute('ALTER TABLE events ADD COLUMN isZh INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE events ADD COLUMN color INTEGER');
    } catch (_) {}
  }

  /// @description Safely decodes stored JSON strings into a dynamic list.
  /// @param value The raw database value to decode.
  /// @returns A decoded list of items.
  List<dynamic> _safeDecodeList(dynamic value) {
    if (value == null) return <dynamic>[];
    if (value is List<dynamic>) return value;
    try {
      final decoded = jsonDecode(value.toString());
      return decoded is List<dynamic> ? decoded : <dynamic>[decoded];
    } catch (_) {
      return <Map<String, String>>[
        {'raw': value.toString()},
      ];
    }
  }

  /// @description Saves synchronized Neptun ICS events without overwriting manual ZHs.
  /// @param events List of parsed ICS event maps.
  Future<void> saveEvents(List<Map<String, dynamic>> events) async {
    final db = await instance.database;
    await _checkZhColumns(db);

    await db.delete(
      'events',
      where: "(isZh IS NULL OR isZh = 0) AND (classType IS NULL OR classType != 'ZH')",
    );

    final batch = db.batch();
    for (final event in events) {
      batch.insert('events', <String, Object?>{
        'className': event['className']?.toString(),
        'classType': event['classType']?.toString(),
        'teachers': jsonEncode(event['teachers'] ?? <dynamic>[]),
        'rooms': jsonEncode(event['rooms'] ?? <dynamic>[]),
        'eventType': event['eventType']?.toString(),
        'dtstart': event['dtstart'] is DateTime
            ? (event['dtstart'] as DateTime).toIso8601String()
            : event['dtstart'].toString(),
        'dtend': event['dtend'] is DateTime
            ? (event['dtend'] as DateTime).toIso8601String()
            : event['dtend'].toString(),
        'isZh': (event['isZh'] as int?) ?? 0,
        'color': event['color'] as int?,
      });
    }
    await batch.commit();
  }

  /// @description Fetches all calendar items (classes and exams) ordered by start time.
  /// @returns List of event maps with parsed DateTime and list fields.
  Future<List<Map<String, dynamic>>> getEvents() async {
    final db = await instance.database;
    await _checkZhColumns(db);
    final result = await db.query('events', orderBy: 'dtstart ASC');

    return result.map((json) => <String, dynamic>{
      'id': json['id'],
      'className': json['className'],
      'classType': json['classType'],
      'teachers': _safeDecodeList(json['teachers']),
      'rooms': _safeDecodeList(json['rooms']),
      'eventType': json['eventType'],
      'dtstart': DateTime.parse(json['dtstart'].toString()),
      'dtend': DateTime.parse(json['dtend'].toString()),
      'isZh': json['isZh'] ?? 0,
      'color': json['color'],
    }).toList();
  }

  /// @description Clears all events in the database.
  Future<void> clearEvents() async {
    final db = await instance.database;
    await db.delete('events');
  }

  /// @description Inserts a new custom midterm or exam.
  /// @param event Map containing the new exam details.
  /// @returns The row ID of the newly inserted exam.
  Future<int> insertZhEvent(Map<String, dynamic> event) async {
    final db = await instance.database;
    await _checkZhColumns(db);

    return db.insert('events', <String, Object?>{
      'className': event['className']?.toString(),
      'classType': event['classType']?.toString() ?? 'ZH',
      'teachers': event['teachers'] != null
          ? (event['teachers'] is String
          ? event['teachers'] as String
          : jsonEncode(event['teachers']))
          : '[]',
      'rooms': event['rooms'] != null
          ? (event['rooms'] is String
          ? event['rooms'] as String
          : jsonEncode(event['rooms']))
          : '[]',
      'eventType': event['eventType']?.toString() ?? 'ZH',
      'dtstart': event['dtstart'] is DateTime
          ? (event['dtstart'] as DateTime).toIso8601String()
          : event['dtstart'].toString(),
      'dtend': event['dtend'] is DateTime
          ? (event['dtend'] as DateTime).toIso8601String()
          : event['dtend'].toString(),
      'isZh': 1,
      'color': event['color'] as int?,
    });
  }

  /// @description Updates an existing custom midterm by its ID.
  /// @param id The primary key ID of the exam to update.
  /// @param event Map containing the updated exam fields.
  /// @returns The number of rows affected.
  Future<int> updateZhEvent(int id, Map<String, dynamic> event) async {
    final db = await instance.database;
    await _checkZhColumns(db);

    return db.update(
      'events',
      <String, Object?>{
        'className': event['className']?.toString(),
        'classType': event['classType']?.toString() ?? 'ZH',
        'teachers': event['teachers'] != null
            ? (event['teachers'] is String
            ? event['teachers'] as String
            : jsonEncode(event['teachers']))
            : '[]',
        'rooms': event['rooms'] != null
            ? (event['rooms'] is String
            ? event['rooms'] as String
            : jsonEncode(event['rooms']))
            : '[]',
        'eventType': event['eventType']?.toString() ?? 'ZH',
        'dtstart': event['dtstart'] is DateTime
            ? (event['dtstart'] as DateTime).toIso8601String()
            : event['dtstart'].toString(),
        'dtend': event['dtend'] is DateTime
            ? (event['dtend'] as DateTime).toIso8601String()
            : event['dtend'].toString(),
        'isZh': 1,
        'color': event['color'] as int?,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// @description Deletes a single ZH event by ID.
  /// @param id The primary key ID of the exam to delete.
  /// @returns The number of rows deleted.
  Future<int> deleteZhEvent(int id) async {
    final db = await instance.database;
    return db.delete(
      'events',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// @description Retrieves all stored ZH and exam events ordered chronologically.
  /// @returns List of exam event maps.
  Future<List<Map<String, dynamic>>> getZhEvents() async {
    final db = await instance.database;
    await _checkZhColumns(db);

    final result = await db.query(
      'events',
      where: "classType = 'ZH' OR isZh = 1",
      orderBy: 'dtstart ASC',
    );

    return result.map(Map<String, dynamic>.from).toList();
  }

  /// @description Deletes only ZH and exam entries from the database.
  /// @returns The number of exam rows deleted.
  Future<int> clearZhEvents() async {
    final db = await instance.database;
    await _checkZhColumns(db);
    return db.delete(
      'events',
      where: "classType = 'ZH' OR isZh = 1",
    );
  }

  /// @description Extracts distinct enrolled course names for the active academic semester using SQL filtering.
  /// @returns Alphabetically sorted list of distinct subject names.
  Future<List<String>> getCurrentSemesterSubjects() async {
    final db = await instance.database;
    await _checkZhColumns(db);

    final now = DateTime.now();
    DateTime semStart;
    DateTime semEnd;

    if (now.month >= 9) {
      semStart = DateTime(now.year, 9);
      semEnd = DateTime(now.year + 1, 1, 31, 23, 59, 59);
    } else if (now.month == 1) {
      semStart = DateTime(now.year - 1, 9);
      semEnd = DateTime(now.year, 1, 31, 23, 59, 59);
    } else {
      semStart = DateTime(now.year, 2);
      semEnd = DateTime(now.year, 7, 31, 23, 59, 59);
    }

    final res = await db.rawQuery(
      '''
      SELECT DISTINCT className FROM events
      WHERE (isZh IS NULL OR isZh = 0)
        AND (classType IS NULL OR classType != 'ZH')
        AND dtstart >= ? AND dtstart <= ?
        AND className IS NOT NULL AND TRIM(className) != ''
      ORDER BY className ASC
      ''',
      <Object?>[semStart.toIso8601String(), semEnd.toIso8601String()],
    );

    return res
        .map((r) => (r['className']?.toString() ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
