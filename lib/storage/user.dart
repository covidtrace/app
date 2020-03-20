import 'dart:async';
import 'db.dart';
import 'package:sqflite/sqflite.dart';

class UserModel {
  final int id;
  final String uuid;

  UserModel({this.id, this.uuid});

  static Future<UserModel> find() async {
    final Database db = await Storage.db;
    final List<Map<String, dynamic>> rows =
        await db.query('user', limit: 1, orderBy: "id ASC");

    return UserModel(
      id: rows[0]['id'],
      uuid: rows[0]['uuid'],
    );
  }
}
