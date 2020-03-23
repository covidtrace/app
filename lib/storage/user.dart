import 'dart:async';
import 'db.dart';
import 'package:sqflite/sqflite.dart';

class UserModel {
  final int id;
  final String uuid;
  String gender;
  int age;
  bool trackLocation;

  UserModel({this.id, this.uuid, this.gender, this.age, this.trackLocation});

  static Future<UserModel> find() async {
    final Database db = await Storage.db;
    final List<Map<String, dynamic>> rows =
        await db.query('user', limit: 1, orderBy: "id ASC");

    return UserModel(
      id: rows[0]['id'],
      uuid: rows[0]['uuid'],
      age: rows[0]['age'],
      gender: rows[0]['gender'],
      trackLocation: rows[0]['track_location'] == 1,
    );
  }

  Future<void> save() async {
    final Database db = await Storage.db;
    return db.update(
        'user',
        {
          'age': age,
          'gender': gender,
          'track_location': trackLocation ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }
}
