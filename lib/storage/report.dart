import 'dart:async';
import 'db.dart';
import 'package:sqflite/sqflite.dart';

class ReportModel {
  final int id;
  final String lastExposureKey;
  final DateTime timestamp;

  ReportModel({this.id, this.lastExposureKey, this.timestamp});

  create() async {
    final Database db = await Storage.db;
    await db.insert('report', {
      'last_exposure_key': lastExposureKey,
      'timestamp': timestamp.toIso8601String()
    });
  }

  static Future<ReportModel> findLatest() async {
    final Database db = await Storage.db;
    final List<Map<String, dynamic>> rows =
        await db.query('report', limit: 1, orderBy: "timestamp DESC");

    if (rows.length == 0) {
      return null;
    }

    return ReportModel(
      id: rows[0]['id'],
      lastExposureKey: rows[0]['last_exposure_key'],
      timestamp: DateTime.parse(rows[0]['timestamp']),
    );
  }

  static Future<void> destroyAll() async {
    final Database db = await Storage.db;
    await db.delete('report');
  }
}
