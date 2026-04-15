import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Lightweight on-device store: cache KV + logged workouts (v2).
class LocalDatabase {
  LocalDatabase._();

  static const currentVersion = 2;

  static Database? _db;

  static Future<Database> instance() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'bp_workout.db');
    _db = await openDatabase(
      path,
      version: currentVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV1(db);
        await _createV2Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createV2Tables(db);
        }
      },
    );
    return _db!;
  }

  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE cache_kv (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createV2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE logged_workouts (
        id TEXT PRIMARY KEY NOT NULL,
        date_ms INTEGER NOT NULL,
        program_id TEXT,
        program_name TEXT,
        day_label TEXT,
        notes TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE logged_exercises (
        id TEXT PRIMARY KEY NOT NULL,
        workout_id TEXT NOT NULL,
        name TEXT NOT NULL,
        prescribed_name TEXT,
        sort_order INTEGER NOT NULL,
        FOREIGN KEY (workout_id) REFERENCES logged_workouts (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE logged_sets (
        id TEXT PRIMARY KEY NOT NULL,
        exercise_id TEXT NOT NULL,
        weight REAL NOT NULL,
        reps INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        FOREIGN KEY (exercise_id) REFERENCES logged_exercises (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_logged_workouts_date_ms ON logged_workouts (date_ms DESC)',
    );
  }
}
