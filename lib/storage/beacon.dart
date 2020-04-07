import 'dart:async';

import 'db.dart';
import 'package:sqflite/sqflite.dart';

const int MIN_TIME_INTERVAL = 1000 * 15;

class BeaconModel {
  final int id;
  final int major;
  final int minor;
  DateTime start;
  DateTime end;
  DateTime lastSeen;

  BeaconModel(
      {this.id, this.major, this.minor, this.start, this.end, this.lastSeen}) {
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
      'major': major,
      'minor': minor,
      'start': startTime.toIso8601String(),
      'end': end?.toIso8601String(),
      'last_seen': lastSeen.toIso8601String(),
    };
  }

  Future<int> save() async {
    final Database db = await Storage.db;
    return db.update('beacon', toMap(), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insert() async {
    final Database db = await Storage.db;
    await db.insert('beacon', toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    print('inserted beacon ${toMap()}');
  }

  static Future<void> seen(major, minor) async {
    // Find a beacon that is in proximity
    var found = await findAll(
        limit: 1,
        orderBy: 'last_seen DESC',
        where: 'major =  ? AND minor = ? AND end is NULL',
        whereArgs: [major, minor]);

    // Create a new one if it doesn't exist, otherwise update it's lastSeen
    if (found.isEmpty) {
      await BeaconModel(major: major, minor: minor).insert();
    } else {
      var first = found.first;
      first.lastSeen = DateTime.now();
      await first.save();
    }
  }

  static Future<void> endUnseen() async {
    var threshold = DateTime.now().subtract(Duration(seconds: 15));

    final Database db = await Storage.db;
    var count = await db.update(
        'beacon', {'end': DateTime.now().toIso8601String()},
        where: 'end is NULL AND DATETIME(last_seen) < DATETIME(?)',
        whereArgs: [threshold.toIso8601String()]);

    if (count > 0) {
      print('ended $count beacons');
    }
    return;
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
              major: rows[i]['major'],
              minor: rows[i]['minor'],
              start: DateTime.parse(rows[i]['start']),
              end: rows[i]['end'] != null
                  ? DateTime.parse(rows[i]['end'])
                  : null,
              lastSeen: rows[i]['last_seen'] != null
                  ? DateTime.parse(rows[i]['last_seen'])
                  : null,
            ));
  }

  static Future<void> destroyAll() async {
    final Database db = await Storage.db;
    await db.delete('beacon');
  }
}
