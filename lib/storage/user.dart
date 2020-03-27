import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'db.dart';
import 'package:sqflite/sqflite.dart';
import 'package:latlong/latlong.dart' as lt;

class UserModel {
  final int id;
  final String uuid;
  String gender;
  int age;
  double latitude;
  double longitude;
  double homeRadius;
  bool trackLocation;
  bool onboarding;
  DateTime lastCheck;

  UserModel(
      {this.id,
      this.uuid,
      this.gender,
      this.age,
      this.trackLocation,
      this.latitude,
      this.longitude,
      this.homeRadius,
      this.onboarding,
      this.lastCheck});

  static Future<UserModel> find() async {
    final Database db = await Storage.db;
    final List<Map<String, dynamic>> rows =
        await db.query('user', limit: 1, orderBy: "id ASC");

    var lastCheck = rows[0]['last_check'];

    return UserModel(
      id: rows[0]['id'],
      uuid: rows[0]['uuid'],
      age: rows[0]['age'],
      gender: rows[0]['gender'],
      trackLocation: rows[0]['track_location'] == 1,
      latitude: rows[0]['latitude'],
      longitude: rows[0]['longitude'],
      onboarding: rows[0]['onboarding'] == 1,
      homeRadius: rows[0]['home_radius'] ?? 40.0,
      lastCheck: lastCheck != null ? DateTime.parse(lastCheck) : null,
    );
  }

  static Future<void> setHome(double latitude, double longitude,
      {double radius}) async {
    var user = await find();
    user.latitude = latitude;
    user.longitude = longitude;
    if (radius != null) {
      user.homeRadius = radius;
    }
    await user.save();
  }

  static Future<bool> isInHome(LatLng point) async {
    var user = await find();
    if (user.latitude == null || user.homeRadius == 0) {
      return false;
    }

    var area =
        lt.Circle(lt.LatLng(user.latitude, user.longitude), user.homeRadius);
    return area.isPointInside(lt.LatLng(point.latitude, point.longitude));
  }

  LatLng get home {
    return latitude != null ? LatLng(latitude, longitude) : null;
  }

  Future<void> save() async {
    final Database db = await Storage.db;
    return db.update(
        'user',
        {
          'age': age,
          'gender': gender,
          'track_location': trackLocation ? 1 : 0,
          'latitude': latitude,
          'longitude': longitude,
          'home_radius': homeRadius,
          'onboarding': onboarding ? 1 : 0,
          'last_check': lastCheck != null ? lastCheck.toIso8601String() : null
        },
        where: 'id = ?',
        whereArgs: [id]);
  }
}
