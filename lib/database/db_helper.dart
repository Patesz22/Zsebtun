import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('zsebtun_calendar_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
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
  Future<void> _checkZhColumns(Database db) async {
    try {
      await db.execute('ALTER TABLE events ADD COLUMN isZh INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE events ADD COLUMN color INTEGER');
    } catch (_) {}
  }

  /// @description Safely decodes stored JSON strings or returns an empty list.
  List<dynamic> _safeDecodeList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value;
    try {
      final decoded = jsonDecode(value.toString());
      return decoded is List ? decoded : [decoded];
    } catch (_) {
      return [{'raw': value.toString()}];
    }
  }

  /// @description Saves synchronized Neptun ICS events without overwriting manual ZHs.
  Future<void> saveEvents(List<Map<String, dynamic>> events) async {
    final db = await instance.database;
    await _checkZhColumns(db);

    // Only delete synchronized class events; preserve user-created ZHs
    await db.delete(
      'events',
      where: "(isZh IS NULL OR isZh = 0) AND (classType IS NULL OR classType != 'ZH')",
    );

    final batch = db.batch();
    for (var event in events) {
      batch.insert('events', {
        'className': event['className'],
        'classType': event['classType'],
        'teachers': jsonEncode(event['teachers'] ?? []),
        'rooms': jsonEncode(event['rooms'] ?? []),
        'eventType': event['eventType'],
        'dtstart': event['dtstart'] is DateTime
            ? (event['dtstart'] as DateTime).toIso8601String()
            : event['dtstart'].toString(),
        'dtend': event['dtend'] is DateTime
            ? (event['dtend'] as DateTime).toIso8601String()
            : event['dtend'].toString(),
        'isZh': event['isZh'] ?? 0,
        'color': event['color'],
      });
    }
    await batch.commit();
  }

  /// @description Fetches all calendar items (classes and exams) ordered by start time.
  Future<List<Map<String, dynamic>>> getEvents() async {
    final db = await instance.database;
    await _checkZhColumns(db);
    final result = await db.query('events', orderBy: 'dtstart ASC');

    return result.map((json) => {
      'id': json['id'],
      'className': json['className'],
      'classType': json['classType'],
      'teachers': _safeDecodeList(json['teachers']),
      'rooms': _safeDecodeList(json['rooms']),
      'eventType': json['eventType'],
      'dtstart': DateTime.parse(json['dtstart'] as String),
      'dtend': DateTime.parse(json['dtend'] as String),
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
  Future<int> insertZhEvent(Map<String, dynamic> event) async {
    final db = await instance.database;
    await _checkZhColumns(db);

    return await db.insert('events', {
      'className': event['className'],
      'classType': event['classType'] ?? 'ZH',
      'teachers': event['teachers'] != null
          ? (event['teachers'] is String ? event['teachers'] : jsonEncode(event['teachers']))
          : '[]',
      'rooms': event['rooms'] != null
          ? (event['rooms'] is String ? event['rooms'] : jsonEncode(event['rooms']))
          : '[]',
      'eventType': event['eventType'] ?? 'ZH',
      'dtstart': event['dtstart'] is DateTime
          ? (event['dtstart'] as DateTime).toIso8601String()
          : event['dtstart'].toString(),
      'dtend': event['dtend'] is DateTime
          ? (event['dtend'] as DateTime).toIso8601String()
          : event['dtend'].toString(),
      'isZh': 1,
      'color': event['color'],
    });
  }

  /// @description Updates an existing custom midterm by its ID.
  Future<int> updateZhEvent(int id, Map<String, dynamic> event) async {
    final db = await instance.database;
    await _checkZhColumns(db);

    return await db.update(
      'events',
      {
        'className': event['className'],
        'classType': event['classType'] ?? 'ZH',
        'teachers': event['teachers'] != null
            ? (event['teachers'] is String ? event['teachers'] : jsonEncode(event['teachers']))
            : '[]',
        'rooms': event['rooms'] != null
            ? (event['rooms'] is String ? event['rooms'] : jsonEncode(event['rooms']))
            : '[]',
        'eventType': event['eventType'] ?? 'ZH',
        'dtstart': event['dtstart'] is DateTime
            ? (event['dtstart'] as DateTime).toIso8601String()
            : event['dtstart'].toString(),
        'dtend': event['dtend'] is DateTime
            ? (event['dtend'] as DateTime).toIso8601String()
            : event['dtend'].toString(),
        'isZh': 1,
        'color': event['color'],
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// @description Deletes a single ZH event by ID.
  Future<int> deleteZhEvent(int id) async {
    final db = await instance.database;
    return await db.delete(
      'events',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// @description Retrieves all stored ZH and exam events ordered chronologically.
  Future<List<Map<String, dynamic>>> getZhEvents() async {
    final db = await instance.database;
    await _checkZhColumns(db);

    final result = await db.query(
      'events',
      where: "classType = 'ZH' OR isZh = 1",
      orderBy: 'dtstart ASC',
    );

    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// @description Deletes only ZH and exam entries from the database.
  Future<int> clearZhEvents() async {
    final db = await instance.database;
    await _checkZhColumns(db);
    return await db.delete(
      'events',
      where: "classType = 'ZH' OR isZh = 1",
    );
  }

  /// @description Extracts distinct enrolled course names for the active academic semester using SQL filtering.
  Future<List<String>> getCurrentSemesterSubjects() async {
    final db = await instance.database;
    await _checkZhColumns(db);

    final now = DateTime.now();
    DateTime semStart;
    DateTime semEnd;

    // Autumn semester: Sept 1 - Jan 31; Spring semester: Feb 1 - July 31
    if (now.month >= 9) {
      semStart = DateTime(now.year, 9, 1);
      semEnd = DateTime(now.year + 1, 1, 31, 23, 59, 59);
    } else if (now.month == 1) {
      semStart = DateTime(now.year - 1, 9, 1);
      semEnd = DateTime(now.year, 1, 31, 23, 59, 59);
    } else {
      semStart = DateTime(now.year, 2, 1);
      semEnd = DateTime(now.year, 7, 31, 23, 59, 59);
    }

    final res = await db.rawQuery('''
      SELECT DISTINCT className FROM events
      WHERE (isZh IS NULL OR isZh = 0)
        AND (classType IS NULL OR classType != 'ZH')
        AND dtstart >= ? AND dtstart <= ?
        AND className IS NOT NULL AND TRIM(className) != ''
      ORDER BY className ASC
    ''', [semStart.toIso8601String(), semEnd.toIso8601String()]);

    return res.map((r) => (r['className'] as String).trim()).toList();
  }
}