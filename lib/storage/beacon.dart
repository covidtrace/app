import 'dart:async';
import 'dart:math';
import 'package:uuid/uuid.dart';

import 'db.dart';
import 'package:sqflite/sqflite.dart';

const int MIN_TIME_INTERVAL = 1000 * 15;

int decodeClientId(int minor) => minor >> 3;
int decodeOffset(int minor) => minor & 7;

class BeaconModel {
  int id;
  final String uuid;
  final DateTime start;
  final DateTime end;

  BeaconModel({this.id, this.uuid, this.start, this.end});

  static BeaconModel fromTransmissions(List<BeaconTransmission> transmissions) {
    var sorted = [...transmissions];
    // Get oldest transmissin for duration
    sorted.sort((a, b) => a.duration.compareTo(b.duration));
    var last = sorted.last;
    // Sort by offset to construct UUID
    sorted.sort((a, b) => a.offset.compareTo(b.offset));

    return BeaconModel(
        uuid: unparseUuid(sorted.map((t) => t.token).toList()),
        start: last.start,
        end: last.lastSeen);
  }

  Duration get duration => end.difference(start);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
    };
  }

  Future<void> insert() async {
    final Database db = await Storage.db;
    await db.insert('beacon', toMap());
    print('inserted beacon ${toMap()}');
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

    return List.generate(
        rows.length,
        (i) => BeaconModel(
              id: rows[i]['id'],
              uuid: rows[i]['uuid'],
              start: DateTime.parse(rows[i]['start']),
              end: DateTime.parse(rows[i]['end']),
            ));
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
  int id;
  int clientId;
  DateTime timestamp;
  List<int> uuidBuffer = List(16); // 16 8bit integers
  int offset = 0;

  BeaconUuid({this.id, String uuid, this.clientId, this.timestamp}) {
    if (uuid != null) {
      Uuid().parse(uuid, buffer: uuidBuffer);
    } else {
      Uuid().v4buffer(uuidBuffer);
    }

    clientId ??= Random().nextInt(MAX_CLIENT_ID);
    timestamp ??= DateTime.now();
  }

  Future<void> rotate() async {
    clientId = Random().nextInt(MAX_CLIENT_ID);
    await save();
  }

  void next() {
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
      'clientId': clientId,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  static Future<BeaconUuid> get() async {
    var cutoff = DateTime.now().subtract(Duration(hours: 1));
    final Database db = await Storage.db;

    var rows = await db.query('beacon_broadcast',
        limit: 1,
        orderBy: 'timestamp DESC',
        where: 'DATETIME(timestamp) > DATETIME(?)',
        whereArgs: [cutoff.toIso8601String()]);

    if (rows.isNotEmpty) {
      var first = rows.first;
      return BeaconUuid(
          id: first['id'],
          uuid: first['uuid'],
          clientId: first['clientId'],
          timestamp: DateTime.parse(first['timestamp']));
    } else {
      var beacon = BeaconUuid();
      await beacon.insert();
      return beacon;
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
}
