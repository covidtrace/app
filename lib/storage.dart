import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocationModel {
  final double longitude;
  final double latitude;
  final double speed;
  final String timestamp;

  LocationModel({this.longitude, this.latitude, this.speed, this.timestamp});

  Map<String, dynamic> toMap() {
    return {
      'longitude': longitude,
      'latitude': latitude,
      'speed': speed,
      'timestamp': timestamp,
    };
  }

  static Future<void> insert(LocationModel location) async {
    final Database db = await initDatabase();
    await db.insert('location', location.toMap());

    print('inserted location $location');
  }

  static Future<int> count() async {
    final Database db = await initDatabase();

    int count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM location;'));

    return count;
  }

  static Future<List<LocationModel>> findAll() async {
    final Database db = await initDatabase();

    print('querying DB for all locations');
    final List<Map<String, dynamic>> rows =
        await db.query('location', limit: 10, orderBy: 'timestamp DESC');

    return List.generate(rows.length, (i) {
      return LocationModel(
        longitude: rows[i]['longitude'],
        latitude: rows[i]['latitude'],
        speed: rows[i]['speed'],
        timestamp: rows[i]['timestamp'],
      );
    });
  }

  static Future<void> destroyAll() async {
    final Database db = await initDatabase();
    await db.delete('location');
  }
}

// Open the database and store the reference.
Future<Database> initDatabase() async {
  final Future<Database> database =
      openDatabase(await dataBasePath(), onCreate: (db, version) async {
    await db.execute(
        "CREATE TABLE location(longitude REAL, latitude REAL, speed REAL, timestamp TEXT)");
  }, version: 1);

  return database;
}

Future<String> dataBasePath() async {
  String dbPath = await getDatabasesPath();
  return join(dbPath, 'locations.db');
}
