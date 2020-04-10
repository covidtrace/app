import 'dart:async';
import 'dart:convert';

import 'package:covidtrace/storage/beacon.dart';

import 'config.dart';
import 'helper/check_exposures.dart' as bg;
import 'helper/signed_upload.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
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
      String bucket = config['exposureBucket'];
      if (bucket == null) {
        bucket = 'covidtrace-exposures';
      }

      var contentType = 'application/json; charset=utf-8';
      var uploadSuccess = await signedUpload(config, user.token,
          query: {
            'bucket': bucket,
            'contentType': contentType,
            'object': '${user.uuid}.json'
          },
          headers: {'Content-Type': contentType},
          body: jsonEncode({
            'cellID': _exposure.cellID.parent(level).toToken(),
            'timestamp': DateFormat('yyyy-MM-dd').format(DateTime.now())
          }));

      if (!uploadSuccess) {
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

  Future<bool> _submitSymptoms(
      Map<String, dynamic> config, Map<String, dynamic> symptoms) {
    var bucket = config['symptomBucket'];
    if (bucket == null) {
      bucket = 'covidtrace-symptoms';
    }

    var contentType = 'application/json; charset=utf-8';
    return signedUpload(config, user.token,
        query: {
          'bucket': bucket,
          'contentType': contentType,
          'object': '${Uuid().v4()}.json'
        },
        headers: {'Content-Type': contentType},
        body: jsonEncode(symptoms));
  }

  Future<LocationModel> _submitLocations(
      Map<String, dynamic> config, UserModel user, double days) async {
    int level = config['reportS2Level'];

    var where = 'sample != 1';
    var whereArgs = [];

    if (_report != null) {
      where = '$where AND id > ${_report.lastLocationId}';
    } else {
      var date = DateTime.now().subtract(Duration(days: 8 + days.toInt()));
      where = '$where AND DATE(timestamp) >= DATE(?)';
      whereArgs = [DateFormat('yyyy-MM-dd').format(date)];
    }

    List<LocationModel> locations = await LocationModel.findAll(
        orderBy: 'id ASC', where: where, whereArgs: whereArgs);

    var bucket = config['holdingBucket'];
    if (bucket == null) {
      bucket = 'covidtrace-holding';
    }

    var contentType = 'text/csv; charset=utf-8';
    var success = await signedUpload(config, user.token,
        query: {
          'bucket': bucket,
          'contentType': contentType,
          'object': '${user.uuid}.csv',
        },
        headers: {
          'Content-Type': contentType,
        },
        body: LocationModel.toCSV(locations, level));

    if (!success) {
      return null;
    }

    return locations.last;
  }

  Future<BeaconUuid> _submitBeacons(
      Map<String, dynamic> config, UserModel user, double days) async {
    // TODO(Wes) this, should look roughly identical to the above method
    return null;
  }

  Future<bool> sendReport(Map<String, dynamic> symptoms) async {
    var success = false;
    double days = symptoms['days'];

    try {
      var config = await getConfig();
      if (!await _submitSymptoms(config, symptoms)) {
        return false;
      }

      var user = await UserModel.find();
      var results = await Future.wait([
        _submitLocations(config, user, days),
        _submitBeacons(config, user, days)
      ]);

      var location = results[0] as LocationModel;
      var beacon = results[1] as BeaconUuid;

      if (location == null && beacon == null) {
        return false;
      }

      _report = ReportModel(
          lastLocationId: location != null ? location.id : null,
          lastBeaconId: beacon != null ? beacon.id : null,
          timestamp: DateTime.now());
      await report.create();

      success = true;
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
