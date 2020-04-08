import 'dart:async';
import 'package:covidtrace/helper/datetime.dart';
import 'package:covidtrace/storage/db.dart';
import 'package:csv/csv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong/latlong.dart' as lt;
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

  bool exposure;
  bool reported;
  S2CellId cellID;

  LocationModel(
      {this.id,
      this.longitude,
      this.latitude,
      this.speed,
      this.activity,
      this.sample,
      this.timestamp,
      this.exposure,
      this.reported}) {
    cellID = new S2CellId.fromLatLng(
        new S2LatLng.fromDegrees(this.latitude, this.longitude));
  }

  Map<String, dynamic> toMap() {
    // Round time to nearest 5 minute to prevent duplicate insertions since
    // onLocation callbacks are not serial
    var time = DateTime.fromMillisecondsSinceEpoch(
        roundedUnixSeconds(timestamp, 5) * 1000);

    return {
      'id': id,
      'longitude': longitude,
      'latitude': latitude,
      'cell_id': cellID.toToken(),
      'activity': activity,
      'sample': sample,
      'speed': speed,
      'timestamp': time.toIso8601String(),
      'exposure': exposure == true ? 1 : 0,
      'reported': reported == true ? 1 : 0,
    };
  }

  Future<int> save() async {
    final Database db = await Storage.db;
    return db.update('location', toMap(), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insert() async {
    final Database db = await Storage.db;
    await db.insert('location', toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    print('inserted location ${toMap()}');
  }

  LatLng get latLng => LatLng(latitude, longitude);

  static Future<Map<String, int>> count() async {
    var db = await Storage.db;

    var count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM location;'));

    var exposures = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM location WHERE exposure = 1;'));

    var reported = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM location WHERE reported = 1;'));

    return {'count': count, 'exposures': exposures, 'reported': reported};
  }

  Future<void> destroy() async {
    final Database db = await Storage.db;
    return db.delete('location', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteInArea(LatLng center, double radius) async {
    var locations = await findAll();

    var area = lt.Circle(lt.LatLng(center.latitude, center.longitude), radius);
    var remove = locations.where((LocationModel l) {
      return radius == 0 ||
          area.isPointInside(lt.LatLng(l.latitude, l.longitude));
    });

    await Future.forEach(remove, (LocationModel l) => l.destroy());
    return;
  }

  static Future<List<LocationModel>> findAll(
      {int limit,
      String where,
      List<dynamic> whereArgs,
      String orderBy,
      String groupBy}) async {
    var rows = await findAllRaw(
        limit: limit,
        orderBy: orderBy,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy);

    return List.generate(rows.length, (i) {
      return LocationModel(
        id: rows[i]['id'],
        longitude: rows[i]['longitude'],
        latitude: rows[i]['latitude'],
        activity: rows[i]['activity'],
        sample: rows[i]['sample'],
        speed: rows[i]['speed'],
        timestamp: DateTime.parse(rows[i]['timestamp']),
        exposure: rows[i]['exposure'] == 1,
        reported: rows[i]['reported'] == 1,
      );
    });
  }

  static Future<List<Map<String, dynamic>>> findAllRaw(
      {List<String> columns,
      int limit,
      String where,
      List<dynamic> whereArgs,
      String orderBy,
      String groupBy}) async {
    final Database db = await Storage.db;

    return await db.query('location',
        columns: columns,
        limit: limit,
        orderBy: orderBy,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy);
  }

  static Future<void> destroyAll() async {
    final Database db = await Storage.db;
    await db.delete('location');
  }

  static final List<dynamic> _headers = ['timestamp', 's2geo', 'verified'];
  static String toCSV(Iterable<LocationModel> locations, int level) =>
      ListToCsvConverter().convert([_headers] +
          locations
              .map((location) => [
                    ceilUnixSeconds(location.timestamp, 60),
                    location.cellID.parent(level).toToken(),
                    false // whether this is a verified submission, always false for now
                  ])
              .toList());
}
