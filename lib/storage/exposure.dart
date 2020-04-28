import 'package:covidtrace/storage/db.dart';
import 'package:sqflite/sqflite.dart';

class ExposureModel {
  static const TABLE_NAME = 'exposure';

  final int id;
  final DateTime date;
  final Duration duration;
  final int attenuationValue;
  final bool reported;

  ExposureModel(
      {this.id,
      this.date,
      this.duration,
      this.attenuationValue,
      this.reported});

  Map<String, dynamic> toMap() {
    var day = DateTime(date.year, date.month, date.day);

    return {
      'id': id,
      'date': day.toIso8601String(),
      'duration': duration.inMinutes,
      'reported': reported == true ? 1 : 0,
    };
  }

  static Future<List<ExposureModel>> findAll(
      {int limit,
      String where,
      List<dynamic> whereArgs,
      String orderBy,
      String groupBy}) async {
    final Database db = await Storage.db;

    var rows = await db.query(TABLE_NAME,
        limit: limit,
        orderBy: orderBy,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy);

    return List.generate(rows.length, (i) {
      return ExposureModel(
        id: rows[i]['id'],
        date: DateTime.parse(rows[i]['date']),
        reported: rows[i]['reported'] == 1,
      );
    });
  }

  Future<void> insert() async {
    final Database db = await Storage.db;
    await db.insert(TABLE_NAME, toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    print('inserted exposure ${toMap()}');
  }

  static Future<Map<String, int>> count() async {
    var db = await Storage.db;

    var count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $TABLE_NAME;'));

    var reported = Sqflite.firstIntValue(await db
        .rawQuery('SELECT COUNT(*) FROM $TABLE_NAME WHERE reported = 1;'));

    return {'count': count, 'reported': reported};
  }

  Future<void> destroy() async {
    final Database db = await Storage.db;
    return db.delete(TABLE_NAME, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> destroyAll() async {
    final Database db = await Storage.db;
    await db.delete(TABLE_NAME);
  }
}
