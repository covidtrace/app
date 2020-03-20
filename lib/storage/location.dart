import 'dart:async';
import 'db.dart';
import 'package:s2geometry/s2geometry.dart';
import 'package:sqflite/sqflite.dart';

class LocationModel {
  final int id;
  final double longitude;
  final double latitude;
  final double speed;
  final DateTime timestamp;
  String cellID;

  LocationModel(
      {this.id, this.longitude, this.latitude, this.speed, this.timestamp}) {
    S2LatLng ll = new S2LatLng.fromDegrees(this.latitude, this.longitude);
    S2CellId cellID = new S2CellId.fromLatLng(ll);
    this.cellID = cellID.toToken();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'longitude': longitude,
      'latitude': latitude,
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
      {int limit, String where, String orderBy}) async {
    final Database db = await Storage.db;

    print('querying DB for all locations');

    final List<Map<String, dynamic>> rows =
        await db.query('location', limit: limit, orderBy: orderBy);

    return List.generate(rows.length, (i) {
      return LocationModel(
        id: rows[i]['id'],
        longitude: rows[i]['longitude'],
        latitude: rows[i]['latitude'],
        speed: rows[i]['speed'],
        timestamp: DateTime.parse(rows[i]['timestamp']),
      );
    });
  }

  static Future<void> destroyAll() async {
    final Database db = await Storage.db;
    await db.delete('location');
  }
}
