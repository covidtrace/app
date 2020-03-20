import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

Future<String> _dataBasePath(String path) async {
  return join(await getDatabasesPath(), path);
}

Future<Database> _initDatabase() async {
  var path = await _dataBasePath('locations.db');
  print(path);

  Future<Database> database = openDatabase(path, onCreate: (db, version) async {
    // Set up location table
    await db.execute(
        "CREATE TABLE location(id INTEGER PRIMARY KEY, longitude REAL, latitude REAL, speed REAL, timestamp TEXT)");

    // Set up user table
    await db.execute("CREATE TABLE user(id INTEGER PRIMARY KEY, uuid STRING)");
    await db.insert('user', {'uuid': Uuid().v4()});

    // Set up reports table
    await db.execute(
        "CREATE TABLE report(id INTEGER PRIMARY KEY, timestamp TEXT, last_location_id INTEGER, FOREIGN KEY (last_location_id) REFERENCES location (id))");
  }, version: 1);

  return database;
}

class Storage {
  static final Future<Database> db = _initDatabase();
}