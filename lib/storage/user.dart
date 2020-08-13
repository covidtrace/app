import 'dart:async';
import 'db.dart';
import 'package:covidtrace/operator.dart';
import 'package:sqflite/sqflite.dart';

class UserModel {
  final int id;
  final String uuid;
  bool onboarding;
  bool firstRun;
  DateTime lastCheck;
  String lastKeyFile;
  Token token;

  UserModel(
      {this.id,
      this.uuid,
      this.firstRun,
      this.onboarding,
      this.lastCheck,
      this.lastKeyFile,
      this.token});

  static Future<UserModel> find() async {
    final Database db = await Storage.db;
    final List<Map<String, dynamic>> rows =
        await db.query('user', limit: 1, orderBy: "id ASC");

    var lastCheck = rows[0]['last_check'];

    return UserModel(
      id: rows[0]['id'],
      uuid: rows[0]['uuid'],
      firstRun: rows[0]['first_run'] == 1,
      onboarding: rows[0]['onboarding'] == 1,
      lastCheck: lastCheck != null ? DateTime.parse(lastCheck) : null,
      lastKeyFile: rows[0]['last_key_file'],
      token: Token(
          token: rows[0]['verify_token'],
          refreshToken: rows[0]['refresh_token']),
    );
  }

  bool get verified => token != null && token.valid;

  Future<void> save() async {
    final Database db = await Storage.db;
    return db.update(
        'user',
        {
          'first_run': firstRun ? 1 : 0,
          'onboarding': onboarding ? 1 : 0,
          'last_check': lastCheck != null ? lastCheck.toIso8601String() : null,
          'last_key_file': lastKeyFile,
          'verify_token': token != null ? token.token : null,
          'refresh_token': token != null ? token.refreshToken : null,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }
}
