import 'package:covidtrace/storage/db.dart';
import 'package:sqflite/sqflite.dart';

class ExposureModel {
  static const TABLE_NAME = 'exposure';

  final int id;
  final DateTime date;
  final Duration duration;
  final int attenuationValue;
  bool reported;

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
      'attenuation_value': attenuationValue,
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
        duration: Duration(minutes: rows[i]['duration']),
        attenuationValue: rows[i]['attenuation_value'],
        reported: rows[i]['reported'] == 1,
      );
    });
  }

  Future<int> save() async {
    final Database db = await Storage.db;
    return db.update(TABLE_NAME, toMap(), where: 'id = ?', whereArgs: [id]);
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
