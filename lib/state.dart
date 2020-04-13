import 'dart:async';
import 'dart:convert';

import 'config.dart';
import 'helper/check_exposures.dart' as bg;
import 'helper/signed_upload.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'storage/beacon.dart';
import 'storage/location.dart';
import 'storage/report.dart';
import 'storage/user.dart';

class AppState with ChangeNotifier {
  static UserModel _user;
  static ReportModel _report;
  static bool _ready = false;
  static LocationModel _exposure;

  AppState() {
    initState();
  }

  initState() async {
    _user = await UserModel.find();
    _report = await ReportModel.findLatest();
    _exposure = await getExposure();
    _ready = true;
    notifyListeners();
  }

  bool get ready => _ready;

  LocationModel get exposure => _exposure;

  UserModel get user => _user;

  Future<LocationModel> getExposure() async {
    var date = DateTime.now().subtract(Duration(days: 7));
    var timestamp = DateFormat('yyyy-MM-dd').format(date);

    var locations = await LocationModel.findAll(
        limit: 1,
        where: 'DATE(timestamp) > DATE(?) AND exposure = 1',
        whereArgs: [timestamp],
        orderBy: 'timestamp DESC');

    return locations.isEmpty ? null : locations.first;
  }

  Future<bool> checkExposures() async {
    var found = await bg.checkExposures();
    _user = await UserModel.find();
    _exposure = await getExposure();
    notifyListeners();
    return found;
  }

  Future<void> saveUser(user) async {
    _user = user;
    await _user.save();
    notifyListeners();
  }

  ReportModel get report => _report;

  Future<void> saveReport(user) async {
    _report = report;
    await _report.create();
    notifyListeners();
  }

  Future<bool> sendExposure() async {
    var success = false;
    try {
      var config = await getConfig();
      var user = await UserModel.find();

      int level = config['exposureS2Level'];
      String bucket = config['exposureBucket'] ?? 'covidtrace-exposures';
      var data = jsonEncode({
        'cellID': _exposure.cellID.parent(level).toToken(),
        'timestamp': DateFormat('yyyy-MM-dd').format(DateTime.now())
      });

      if (!await objectUpload(
          config: config,
          bucket: bucket,
          object: '${user.uuid}.json',
          data: data)) {
        return false;
      }

      _exposure.reported = true;
      await _exposure.save();
      success = true;
    } catch (err) {
      print(err);
      success = false;
    }

    notifyListeners();
    return success;
  }

  Future<bool> objectUpload(
      {@required Map<String, dynamic> config,
      @required String bucket,
      @required String object,
      @required String data,
      String contentType = 'application/json; charset=utf-8'}) async {
    var user = await UserModel.find();

    return signedUpload(config, user.token,
        query: {'bucket': bucket, 'contentType': contentType, 'object': object},
        headers: {'Content-Type': contentType},
        body: data);
  }

  Future<bool> sendSymptoms(
      {@required Map<String, dynamic> symptoms,
      @required Map<String, dynamic> config}) {
    var bucket = config['symptomBucket'] ?? 'covidtrace-symptoms';
    return objectUpload(
        config: config,
        bucket: bucket,
        object: '${Uuid().v4()}.json',
        data: jsonEncode(symptoms));
  }

  Future<List<LocationModel>> sendLocations(
      {@required Map<String, dynamic> config, DateTime date}) async {
    String where = 'sample != 1';
    List whereArgs = [];
    if (report?.lastLocationId != null) {
      where = '$where AND id > ?';
      whereArgs = [report.lastLocationId];
    } else {
      where = '$where AND DATE(timestamp) >= DATE(?)';
      whereArgs = [DateFormat('yyyy-MM-dd').format(date)];
    }

    List<LocationModel> locations = await LocationModel.findAll(
        orderBy: 'id ASC', where: where, whereArgs: whereArgs);

    if (locations.isEmpty) {
      return locations;
    }

    int level = config['reportS2Level'];
    var data = LocationModel.toCSV(locations, level);

    try {
      var success = await objectUpload(
          config: config,
          bucket: config['holdingBucket'] ?? 'covidtrace-holding',
          object: '${user.uuid}.csv',
          contentType: 'text/csv; charset=utf-8',
          data: data);
      return success ? locations : null;
    } catch (err) {
      print(err);
      return null;
    }
  }

  Future<List<BeaconUuid>> sendBeacons(
      {@required Map<String, dynamic> config, DateTime date}) async {
    String where;
    List whereArgs = [];
    if (report?.lastBeaconId != null) {
      where = 'id > ?';
      whereArgs = [report.lastBeaconId];
    } else {
      where = 'DATE(timestamp) >= DATE(?)';
      whereArgs = [DateFormat('yyyy-MM-dd').format(date)];
    }

    List<BeaconUuid> beacons = await BeaconUuid.findAll(
        orderBy: 'id ASC', where: where, whereArgs: whereArgs);

    if (beacons.isEmpty) {
      return beacons;
    }

    // We evaluate all locations from previous 2 days since location
    // changes may be infrequent in worst case scenario.
    List<LocationModel> locations = await LocationModel.findAll(
        orderBy: 'id ASC',
        where: 'DATE(timestamp) >= DATE(?)',
        whereArgs: [
          DateFormat('yyyy-MM-dd')
              .format(beacons.first.timestamp.subtract(Duration(days: 2)))
        ]);

    // For each beacon find the closest location recorded based on timestamp
    beacons.forEach((b) {
      var time = b.timestamp;
      var before = locations.lastWhere((l) => l.timestamp.compareTo(time) < 0,
          orElse: () => null);
      var after = locations.firstWhere((l) => l.timestamp.compareTo(time) >= 0,
          orElse: () => null);

      if (before == null || after == null) {
        b.location = before ?? after;
      } else {
        var beforeDiff = time.difference(before.timestamp);
        var afterDiff = time.difference(after.timestamp);
        b.location = beforeDiff.compareTo(afterDiff) < 0 ? before : after;
      }
    });

    // TODO(wes): Although this is unlikely to ever occur we need to consider
    // how to report beacons without any rough location.
    beacons = beacons.where((b) => b.location != null).toList();

    int level = config['reportS2Level'];
    var data = BeaconUuid.toCSV(beacons, level);

    try {
      var success = await objectUpload(
          config: config,
          bucket: config['tokenBucket'] ?? 'covidtrace-tokens',
          object: '${user.uuid}.csv',
          contentType: 'text/csv; charset=utf-8',
          data: data);
      return success ? beacons : null;
    } catch (err) {
      print(err);
      return null;
    }
  }

  Future<bool> sendReport(Map<String, dynamic> symptoms) async {
    var success = false;
    var config = await getConfig();

    int days = symptoms['days'];
    var date = DateTime.now().subtract(Duration(days: 8 + days));

    try {
      var results = await Future.wait([
        sendSymptoms(symptoms: symptoms, config: config),
        sendLocations(config: config, date: date),
        sendBeacons(config: config, date: date)
      ]);

      List<LocationModel> locations = results[1] ?? [];
      List<BeaconUuid> beacons = results[2] ?? [];

      if (locations.isNotEmpty) {
        _report = ReportModel(
            lastLocationId: locations.last.id,
            lastBeaconId: beacons.isNotEmpty ? beacons.last.id : null,
            timestamp: DateTime.now());
        await report.create();
        success = true;
      }
    } catch (err) {
      print(err);
      success = false;
    }

    notifyListeners();
    return success;
  }

  Future<void> clearReport() async {
    await ReportModel.destroyAll();
    _report = null;
    notifyListeners();
  }
}
