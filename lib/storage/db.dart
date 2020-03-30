import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

Future<String> _dataBasePath(String path) async {
  return join(await getDatabasesPath(), path);
}

Future<Database> _initDatabase() async {
  var dbPath = await _dataBasePath('locations.db');
  print(dbPath);

  Future<Database> database =
      openDatabase(dbPath, onCreate: (db, version) async {
    // Set up location table
    await db.execute(
        "CREATE TABLE location(id INTEGER PRIMARY KEY, longitude REAL, latitude REAL, cell_id TEXT, speed REAL, activity TEXT, sample INTEGER, timestamp TEXT, exposure INTEGER DEFAULT 0, reported INTEGER DEFAULT 0)");

    // Set up user table
    await db.execute(
        "CREATE TABLE user(id INTEGER PRIMARY KEY, uuid STRING, track_location INTEGER, gender STRING, age INTEGER, longitude REAL, latitude REAL, home_radius REAL, onboarding INTEGER, last_check TEXT, verify_token TEXT)");
    await db.insert(
        'user', {'uuid': Uuid().v4(), 'home_radius': 40.0, 'onboarding': 1});

    // Set up reports table
    await db.execute(
        "CREATE TABLE report(id INTEGER PRIMARY KEY, timestamp TEXT, last_location_id INTEGER, FOREIGN KEY (last_location_id) REFERENCES location (id) ON DELETE CASCADE)");
  }, version: 1);

  return database;
}

class Storage {
  static final Future<Database> db = _initDatabase();
}
