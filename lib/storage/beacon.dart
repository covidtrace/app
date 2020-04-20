import 'dart:async';
import 'dart:math';
import 'package:covidtrace/helper/datetime.dart';
import 'package:covidtrace/storage/location.dart';
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';
import 'package:sqflite/sqflite.dart';

const int MIN_TIME_INTERVAL = 1000 * 15;

int decodeClientId(int minor) => minor >> 3;
int decodeOffset(int minor) => minor & 7;

class BeaconModel {
  final int id;
  final String uuid;
  final DateTime start;
  final DateTime end;

  int locationId;
  LocationModel _location;
  bool exposure;
  bool reported;

  BeaconModel(
      {this.id,
      this.uuid,
      this.start,
      this.end,
      this.exposure,
      this.reported,
      this.locationId});

  Duration get duration => end.difference(start);

  LocationModel get location => _location;

  set location(LocationModel loc) {
    locationId = loc.id;
    _location = loc;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'exposure': exposure == true ? 1 : 0,
      'reported': reported == true ? 1 : 0,
      'location_id': locationId,
    };
  }

  Future<void> insert() async {
    final Database db = await Storage.db;
    await db.insert('beacon', toMap());
    print('inserted beacon ${toMap()}');
  }

  Future<int> save() async {
    final Database db = await Storage.db;
    return db.update('beacon', toMap(), where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<BeaconModel>> findAll(
      {int limit,
      String orderBy,
      String where,
      List<dynamic> whereArgs,
      String groupBy}) async {
    final Database db = await Storage.db;

    var rows = await db.query('beacon',
        limit: limit,
        orderBy: orderBy,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy);

    // Associated LocationModels
    // TODO(wes): Use a rawQuery to do a join instead of this separate query.
    var locationIds = Set();
    locationIds.addAll(rows
        .where((r) => r['location_id'] != null)
        .map((r) => r['location_id']));

    var locations = await LocationModel.findAll(
        where: 'id in (?)', whereArgs: [locationIds.toList().join(',')]);

    return List.generate(rows.length, (i) {
      var row = rows[i];
      var beacon = BeaconModel(
        id: row['id'],
        uuid: row['uuid'],
        start: DateTime.parse(row['start']),
        end: DateTime.parse(row['end']),
        exposure: row['exposure'] == 1,
        reported: row['reported'] == 1,
        locationId: row['location_id'],
      );

      if (beacon.locationId != null) {
        beacon.location =
            locations.firstWhere((l) => l.id == beacon.locationId);
      }

      return beacon;
    });
  }

  static Future<void> destroyAll() async {
    final Database db = await Storage.db;
    await db.delete('beacon');
  }
}

class BeaconTransmission {
  static const UNSEEN_TIMEOUT = Duration(seconds: 20);

  final int id;
  final int clientId;
  final int offset;
  final int token;
  DateTime start;
  DateTime end;
  DateTime lastSeen;

  BeaconTransmission(
      {this.id,
      this.clientId,
      this.offset,
      this.token,
      this.start,
      this.end,
      this.lastSeen}) {
    start ??= DateTime.now();
    lastSeen ??= start;
  }

  Duration get duration => lastSeen.difference(start);

  Map<String, dynamic> toMap() {
    // Round time to nearest interval to prevent duplicate insertions
    var startTime = DateTime.fromMillisecondsSinceEpoch(
        start.millisecondsSinceEpoch ~/ MIN_TIME_INTERVAL * MIN_TIME_INTERVAL);

    return {
      'id': id,
      'clientId': clientId,
      'offset': offset,
      'token': token,
      'start': startTime.toIso8601String(),
      'end': end?.toIso8601String(),
      'last_seen': lastSeen.toIso8601String(),
    };
  }

  Future<int> save() async {
    final Database db = await Storage.db;
    return db.update('beacon_transmission', toMap(),
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insert() async {
    final Database db = await Storage.db;
    await db.insert('beacon_transmission', toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    print('inserted beacon transmission ${toMap()}');
  }

  static Future<void> seen(major, minor) async {
    var clientId = decodeClientId(minor);
    var offset = decodeOffset(minor);
    var token = major;

    // Find transmissions that were recently seen
    var found = await findAll(
        limit: 1,
        orderBy: 'last_seen DESC',
        where: 'clientId = ? AND offset = ? AND token = ? AND end is NULL',
        whereArgs: [clientId, offset, token]);

    // Create a new one if it doesn't exist
    if (found.isEmpty) {
      await BeaconTransmission(clientId: clientId, offset: offset, token: token)
          .insert();
    }

    // Update last seen for any other matching clients
    final Database db = await Storage.db;
    await db.update(
        'beacon_transmission', {'last_seen': DateTime.now().toIso8601String()},
        where: 'clientId = ? and END is NULL', whereArgs: [clientId]);
  }

  static Future<int> endUnseen() async {
    var threshold = DateTime.now().subtract(UNSEEN_TIMEOUT);

    final Database db = await Storage.db;
    var count = await db.update(
        'beacon_transmission', {'end': DateTime.now().toIso8601String()},
        where: 'end is NULL AND DATETIME(last_seen) < DATETIME(?)',
        whereArgs: [threshold.toIso8601String()]);

    if (count > 0) {
      print('ended $count beacons transmission');
    }

    return count;
  }

  static Future<List<BeaconModel>> convertCompleted() async {
    final Database db = await Storage.db;

    var rows = await db.query('beacon_transmission',
        columns: [
          'clientId',
          'GROUP_CONCAT(token) as tokens',
          'MIN(start) as start',
          'last_seen',
        ],
        orderBy: 'last_seen DESC, offset ASC',
        where: 'end IS NOT NULL',
        having: 'COUNT(offset) = 8',
        groupBy: 'clientId, last_seen');

    print(rows);

    var beacons = rows.map((row) {
      String tokens = row['tokens'];
      return BeaconModel(
        uuid: unparseUuid(
            tokens.split(',').map((t) => int.parse(t, radix: 10)).toList()),
        start: DateTime.parse(row['start']),
        end: DateTime.parse(row['last_seen']),
      );
    }).toList();

    // Insert converted beacons and remove completed transmissions
    await Future.wait(beacons.map((b) => b.insert()));
    await Future.wait(rows.map((row) => db.delete(
          'beacon_transmission',
          where: 'clientId = ? AND last_seen = ?',
          whereArgs: [row['clientId'], row['last_seen']],
        )));

    return beacons;
  }

  static Future<List<BeaconTransmission>> findAll(
      {int limit,
      String orderBy,
      String where,
      List<dynamic> whereArgs,
      String groupBy}) async {
    final Database db = await Storage.db;

    var rows = await db.query('beacon_transmission',
        limit: limit,
        orderBy: orderBy,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy);

    return List.generate(
        rows.length,
        (i) => BeaconTransmission(
              id: rows[i]['id'],
              clientId: rows[i]['clientId'],
              offset: rows[i]['offset'],
              token: rows[i]['token'],
              start: DateTime.parse(rows[i]['start']),
              end: rows[i]['end'] != null
                  ? DateTime.parse(rows[i]['end'])
                  : null,
              lastSeen: rows[i]['last_seen'] != null
                  ? DateTime.parse(rows[i]['last_seen'])
                  : null,
            ));
  }

  static Future<void> destroy({String where, List<dynamic> whereArgs}) async {
    final Database db = await Storage.db;
    await db.delete('beacon_transmission', where: where, whereArgs: whereArgs);
  }

  static Future<void> destroyAll() async {
    final Database db = await Storage.db;
    await db.delete('beacon_transmission');
  }
}

const int MASK_3_BITS = 7;
const int MASK_8_BITS = 255;
const int MASK_13_BITS = 8191;

const int MAX_CLIENT_ID = 8191;
const int MAX_OFFSET = 7;

// Converts 16bit buffer into 8bit buffer and unparses into String Uuid.
String unparseUuid(List<int> buffer16Bit) {
  var buffer8Bit = new List<int>(16);
  for (var i = 0; i < 8; i++) {
    buffer8Bit[i * 2] = buffer16Bit[i] >> 8;
    buffer8Bit[i * 2 + 1] = buffer16Bit[i] & MASK_8_BITS;
  }

  var uuid = Uuid();
  return uuid.unparse(buffer8Bit);
}

// Represents a UUID that can be transmitted as a sequence of Beacon major/minor payloads
class BeaconUuid {
  static const UUID_ROTATE_INTERVAL = Duration(minutes: 60);
  static const CLIENT_ID_ROTATE_INTERVAL = Duration(minutes: 20);

  int id;
  DateTime timestamp;
  int clientId;
  DateTime clientIdTimestamp;
  List<int> uuidBuffer = List(16); // 16 8bit integers
  int offset = 0;
  LocationModel location;

  BeaconUuid(
      {this.id,
      String uuid,
      this.timestamp,
      this.clientId,
      this.clientIdTimestamp}) {
    if (uuid != null) {
      Uuid().parse(uuid, buffer: uuidBuffer);
    } else {
      Uuid().v4buffer(uuidBuffer);
    }

    timestamp ??= DateTime.now();
    clientId ??= Random().nextInt(MAX_CLIENT_ID);
    clientIdTimestamp ??= DateTime.now();
  }

  Future<void> rotateClientId() async {
    clientId = Random().nextInt(MAX_CLIENT_ID);
    clientIdTimestamp = DateTime.now();
    await save();
  }

  Future<void> rotateUuid() async {
    var beacon = BeaconUuid();
    await beacon.insert();
    beacon = await get();
    // Update existing instance to match newly created entry
    id = beacon.id;
    uuidBuffer = beacon.uuidBuffer;
    timestamp = beacon.timestamp;
    clientId = beacon.clientId;
    clientIdTimestamp = beacon.clientIdTimestamp;
  }

  bool get isStale {
    var diff = DateTime.now().difference(timestamp);
    return diff.compareTo(UUID_ROTATE_INTERVAL) >= 0;
  }

  bool get isClientIdStale {
    var diff = DateTime.now().difference(clientIdTimestamp);
    return diff.compareTo(CLIENT_ID_ROTATE_INTERVAL) >= 0;
  }

  Future<void> next() async {
    if (isStale) {
      await rotateUuid();
    } else if (isClientIdStale) {
      await rotateClientId();
    }

    offset = offset < MAX_OFFSET ? offset + 1 : 0;
  }

  String get uuid => Uuid().unparse(uuidBuffer);

  int get major {
    var firstByte = uuidBuffer[offset * 2];
    var secondByte = uuidBuffer[offset * 2 + 1];

    return firstByte << 8 | secondByte;
  }

  int get minor => (clientId << 3) | offset;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'timestamp': timestamp.toIso8601String(),
      'client_id': clientId,
      'client_id_timestamp': clientIdTimestamp.toIso8601String(),
    };
  }

  static Future<BeaconUuid> get() async {
    final Database db = await Storage.db;

    var rows = await db.query(
      'beacon_broadcast',
      limit: 1,
      orderBy: 'timestamp DESC',
    );

    if (rows.isNotEmpty) {
      var first = rows.first;
      return BeaconUuid(
        id: first['id'],
        uuid: first['uuid'],
        timestamp: DateTime.parse(first['timestamp']),
        clientId: first['client_id'],
        clientIdTimestamp: DateTime.parse(first['client_id_timestamp']),
      );
    } else {
      var beacon = BeaconUuid();
      await beacon.insert();
      return get();
    }
  }

  Future<void> insert() async {
    final Database db = await Storage.db;
    await db.insert('beacon_broadcast', toMap());
  }

  Future<int> save() async {
    final Database db = await Storage.db;
    return db
        .update('beacon_broadcast', toMap(), where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<BeaconUuid>> findAll(
      {int limit,
      String orderBy,
      String where,
      List<dynamic> whereArgs,
      String groupBy}) async {
    final Database db = await Storage.db;

    var rows = await db.query('beacon_broadcast',
        limit: limit,
        orderBy: orderBy,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy);

    return List.generate(
        rows.length,
        (i) => BeaconUuid(
              id: rows[i]['id'],
              uuid: rows[i]['uuid'],
              timestamp: DateTime.parse(rows[i]['timestamp']),
              clientId: rows[i]['client_id'],
              clientIdTimestamp: DateTime.parse(rows[i]['client_id_timestamp']),
            ));
  }

  static final List<dynamic> _headers = ['timestamp', 'uuid', 's2geo'];
  static String toCSV(Iterable<BeaconUuid> beacons, int level) =>
      ListToCsvConverter().convert([_headers] +
          beacons
              .map((beacon) => [
                    ceilUnixSeconds(beacon.timestamp, 60),
                    beacon.uuid,
                    beacon.location.cellID.parent(level).toToken(),
                  ])
              .toList());
}
