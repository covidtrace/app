import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_migration/sqflite_migration.dart';
import 'package:uuid/uuid.dart';

final uuid = Uuid().v4();

// This value should essentially never change. Any changes to the DB schema
// must be applied via the `migrationScripts` list.
List<String> initialScript = [
  '''
CREATE TABLE location (
  id INTEGER PRIMARY KEY,
  longitude REAL,
  latitude REAL,
  cell_id TEXT,
  speed REAL,
  activity TEXT,
  sample INTEGER,
  timestamp TEXT UNIQUE,
  exposure INTEGER DEFAULT 0,
  reported INTEGER DEFAULT 0
 )
  ''',
  '''
CREATE TABLE user (
  id INTEGER PRIMARY KEY,
  uuid STRING,
  track_location INTEGER,
  longitude REAL,
  latitude REAL,
  home_radius REAL,
  onboarding INTEGER,
  last_check TEXT,
  verify_token TEXT,
  refresh_token TEXT
)
  ''',
  "INSERT INTO user (uuid, home_radius, onboarding) VALUES ('$uuid', 40.0, 1)",
  '''
CREATE TABLE report (
  id INTEGER PRIMARY KEY,
  timestamp TEXT,
  last_location_id INTEGER,
  FOREIGN KEY (last_location_id) REFERENCES location (id) ON DELETE CASCADE
)
  ''',
  '''
CREATE TABLE user_beacon (
  major INTEGER,
  minor INTEGER,
  timestamp TEXT,
  PRIMARY KEY (major, minor)
)
  ''',
  '''
CREATE TABLE beacon (
  id INTEGER PRIMARY KEY,
  major INTEGER,
  minor INTEGER,
  start TEXT,
  last_seen TEXT,
  end TEXT,
  UNIQUE (major, minor, start)
)
  ''',
];

List<String> migrationScripts = [];

Future<String> _dataBasePath(String path) async {
  return join(await getDatabasesPath(), path);
}

Future<Database> _initDatabase() async {
  return await openDatabaseWithMigration(
      await _dataBasePath('locations.db'),
      MigrationConfig(
          initializationScript: initialScript,
          migrationScripts: migrationScripts));
}

class Storage {
  static final Future<Database> db = _initDatabase();
}
