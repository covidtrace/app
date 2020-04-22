import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
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
CREATE TABLE beacon_broadcast (
  id INTEGER PRIMARY KEY,
  uuid STRING UNIQUE,
  timestamp TEXT,
  client_id INTEGER,
  client_id_timestamp TEXT
)
  ''',
  '''
CREATE TABLE beacon (
  id INTEGER PRIMARY KEY,
  uuid TEXT,
  start TEXT,
  end TEXT,
  UNIQUE (uuid, start)
)
  ''',
  '''
CREATE TABLE beacon_transmission (
  id INTEGER PRIMARY KEY,
  clientId INTEGER,
  offset INTEGER,
  token INTEGER,
  start TEXT,
  last_seen TEXT,
  end TEXT,
  UNIQUE (clientId, offset, token, start)
)
  ''',
];

// Maps a DB version to migration scripts
Map<int, List<String>> migrationScripts = {
  2: [
    '''
ALTER TABLE report ADD COLUMN last_beacon_id INTEGER REFERENCES beacon_broadcast (id) ON DELETE CASCADE
  ''',
  ],
  3: [
    '''
ALTER TABLE beacon ADD COLUMN exposure INTEGER DEFAULT 0
  ''',
    '''
ALTER TABLE beacon ADD COLUMN reported INTEGER DEFAULT 0
  ''',
  ],
  4: [
    '''
ALTER TABLE beacon ADD COLUMN location_id INTEGER REFERENCES location (id)
  ''',
  ]
};

Future<void> _runMigrations(db, oldVersion, newVersion) async {
  for (var i = oldVersion + 1; i <= newVersion; i++) {
    print('running migration ver $i');
    migrationScripts[i].forEach((script) async => await db.execute(script));
  }
}

Future<String> _dataBasePath(String path) async {
  return join(await getDatabasesPath(), path);
}

Future<Database> _initDatabase() async {
  return await openDatabase(await _dataBasePath('locations.db'), version: 4,
      onCreate: (db, version) async {
    initialScript.forEach((script) async => await db.execute(script));
    if (version > 1) {
      _runMigrations(db, 1, version);
    }
  }, onUpgrade: _runMigrations);
}

class Storage {
  static final Future<Database> db = _initDatabase();
}
