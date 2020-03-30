import 'dart:convert';

import 'package:covidtrace/storage/report.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'config.dart';
import 'helper/signed_upload.dart';
import 'storage/location.dart';
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
    _exposure = await loadExposure();
    _ready = true;
    notifyListeners();
  }

  Future<LocationModel> loadExposure() async {
    var date = DateTime.now().subtract(Duration(days: 7));
    var timestamp = DateFormat('yyyy-MM-dd').format(date);

    var locations = await LocationModel.findAll(
        limit: 1,
        where: 'DATE(timestamp) > DATE(?) AND exposure = 1',
        whereArgs: [timestamp],
        orderBy: 'timestamp DESC');

    return locations.isEmpty ? null : locations.first;
  }

  Future<LocationModel> checkExposure() async {
    _exposure = await loadExposure();
    notifyListeners();

    return _exposure;
  }

  bool get ready {
    return _ready;
  }

  LocationModel get exposure => _exposure;

  UserModel get user => _user;

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

      var bucket = config['exposureBucket'];
      if (bucket == null) {
        bucket = 'covidtrace-exposures';
      }

      var contentType = 'application/json; charset=utf-8';
      var uploadSuccess = await signedUpload(config,
          query: {
            'bucket': bucket,
            'contentType': contentType,
            'object': '${user.uuid}.json'
          },
          headers: {'Content-Type': contentType},
          body: jsonEncode({
            'cellID': _exposure.cellID.parent(10).toToken(),
            'timestamp': DateFormat('yyyy-MM-dd').format(DateTime.now())
          }));

      if (!uploadSuccess) {
        return false;
      }

      success = true;
    } catch (err) {
      print(err);
      success = false;
    }

    notifyListeners();
    return success;
  }

  Future<bool> sendReport(Map<String, dynamic> symptoms) async {
    var success = false;

    try {
      var config = await getConfig();
      var user = await UserModel.find();

      var symptomBucket = config['symptomBucket'];
      if (symptomBucket == null) {
        symptomBucket = 'covidtrace-symptoms';
      }

      var contentType = 'application/json; charset=utf-8';
      var symptomSuccess = await signedUpload(config,
          query: {
            'bucket': symptomBucket,
            'contentType': contentType,
            'object': '${Uuid().v4()}.json'
          },
          headers: {'Content-Type': contentType},
          body: jsonEncode(symptoms));

      if (!symptomSuccess) {
        return false;
      }

      String where = 'sample != 1';
      List whereArgs = [];
      if (_report != null) {
        where = '$where AND id > ${_report.lastLocationId}';
      } else {
        double days = symptoms['days'];
        var date = DateTime.now().subtract(Duration(days: 8 + days.toInt()));
        where = '$where AND DATE(timestamp) >= DATE(?)';
        whereArgs = [DateFormat('yyyy-MM-dd').format(date)];
      }

      List<LocationModel> locations = await LocationModel.findAll(
          orderBy: 'id ASC', where: where, whereArgs: whereArgs);

      List<List<dynamic>> headers = [
        ['timestamp', 's2geo', 'status']
      ];

      var holdingBucket = config['holdingBucket'];
      if (holdingBucket == null) {
        holdingBucket = 'covidtrace-holding';
      }

      contentType = 'text/csv; charset=utf-8';
      var uploadSuccess = await signedUpload(config,
          query: {
            'bucket': holdingBucket,
            'contentType': contentType,
            'object': '${user.uuid}.csv',
          },
          headers: {
            'Content-Type': contentType,
          },
          body: ListToCsvConverter()
              .convert(headers + locations.map((l) => l.toCSV()).toList()));

      if (!uploadSuccess) {
        return false;
      }

      _report = ReportModel(
          lastLocationId: locations.last.id, timestamp: DateTime.now());
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
