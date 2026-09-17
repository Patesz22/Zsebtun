import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('zsebtun_calendar_v2.db'); // Changed DB name to force a fresh schema
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
        dtend TEXT
      )
    ''');
  }

  Future<void> saveEvents(List<Map<String, dynamic>> events) async {
    final db = await instance.database;
    await db.delete('events');

    Batch batch = db.batch();
    for (var event in events) {
      batch.insert('events', {
        'className': event['className'],
        'classType': event['classType'],
        'teachers': jsonEncode(event['teachers']), // Store lists as JSON strings
        'rooms': jsonEncode(event['rooms']),
        'eventType': event['eventType'],
        'dtstart': (event['dtstart'] as DateTime).toIso8601String(),
        'dtend': (event['dtend'] as DateTime).toIso8601String(),
      });
    }
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> getEvents() async {
    final db = await instance.database;
    final result = await db.query('events', orderBy: 'dtstart ASC');

    return result.map((json) => {
      'className': json['className'],
      'classType': json['classType'],
      'teachers': jsonDecode(json['teachers'] as String), // Decode back to List
      'rooms': jsonDecode(json['rooms'] as String),
      'eventType': json['eventType'],
      'dtstart': DateTime.parse(json['dtstart'] as String),
      'dtend': DateTime.parse(json['dtend'] as String),
    }).toList();
  }

  Future<void> clearEvents() async {
    final db = await instance.database;
    await db.delete('events');
  }
}