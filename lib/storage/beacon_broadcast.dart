import 'dart:async';
import 'dart:math';

import 'db.dart';
import 'package:sqflite/sqflite.dart';

class BeaconBroadcastModel {
  final int id;
  int major;
  int minor;
  DateTime timestamp;

  BeaconBroadcastModel({this.id, this.major, this.minor, this.timestamp}) {
    major ??= Random().nextInt(pow(2, 16));
    minor ??= Random().nextInt(pow(2, 16));
    timestamp ??= DateTime.now();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'major': major,
      'minor': minor,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  static Future<BeaconBroadcastModel> get() async {
    var cutoff = DateTime.now().subtract(Duration(hours: 1));
    final Database db = await Storage.db;

    var rows = await db.query('beacon_broadcast',
        limit: 1,
        orderBy: 'timestamp DESC',
        where: 'DATETIME(timestamp) > DATETIME(?)',
        whereArgs: [cutoff.toIso8601String()]);

    if (rows.isNotEmpty) {
      var first = rows.first;
      return BeaconBroadcastModel(
          id: first['id'],
          major: first['major'],
          minor: first['major'],
          timestamp: DateTime.parse(first['timestamp']));
    } else {
      var beacon = BeaconBroadcastModel();
      await beacon.insert();
      return beacon;
    }
  }

  Future<void> insert() async {
    final Database db = await Storage.db;
    await db.insert('beacon_broadcast', toMap());
  }
}
