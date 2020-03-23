import 'dart:async';
import 'db.dart';
import 'package:s2geometry/s2geometry.dart';
import 'package:sqflite/sqflite.dart';

class LocationModel {
  final int id;
  final double longitude;
  final double latitude;
  final double speed;
  final int sample;
  final String activity;
  final DateTime timestamp;
  String cellID;

  LocationModel(
      {this.id,
      this.longitude,
      this.latitude,
      this.speed,
      this.activity,
      this.sample,
      this.timestamp}) {
    S2LatLng ll = new S2LatLng.fromDegrees(this.latitude, this.longitude);
    S2CellId cellID = new S2CellId.fromLatLng(ll);
    this.cellID = cellID.toToken();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'longitude': longitude,
      'latitude': latitude,
      'activity': activity,
      'sample': sample,
      'speed': speed,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  List<dynamic> toCSV() {
    var unix = timestamp.millisecondsSinceEpoch / 1000;
    var hour = (unix / 60 / 60).ceil() * 60 * 60;
    return [hour, cellID, 'self'];
  }

  static Future<void> insert(LocationModel location) async {
    final Database db = await Storage.db;
    await db.insert('location', location.toMap());
    print('inserted location $location');
  }

  static Future<int> count() async {
    final Database db = await Storage.db;

    int count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM location;'));

    return count;
  }

  static Future<List<LocationModel>> findAll(
      {int limit, String where, String orderBy, String groupBy}) async {
    var rows = await findAllRaw(
        limit: limit, orderBy: orderBy, where: where, groupBy: groupBy);

    return List.generate(rows.length, (i) {
      return LocationModel(
        id: rows[i]['id'],
        longitude: rows[i]['longitude'],
        latitude: rows[i]['latitude'],
        activity: rows[i]['activity'],
        sample: rows[i]['sample'],
        speed: rows[i]['speed'],
        timestamp: DateTime.parse(rows[i]['timestamp']),
      );
    });
  }

  static Future<List<Map<String, dynamic>>> findAllRaw(
      {List<String> columns,
      int limit,
      String where,
      String orderBy,
      String groupBy}) async {
    final Database db = await Storage.db;

    return await db.query('location',
        columns: columns,
        limit: limit,
        orderBy: orderBy,
        where: where,
        groupBy: groupBy);
  }

  static Future<void> destroyAll() async {
    final Database db = await Storage.db;
    await db.delete('location');
  }
}
