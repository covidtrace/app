import 'dart:async';
import 'dart:convert';

import 'package:covidtrace/exposure.dart';
import 'package:covidtrace/storage/db.dart';
import 'package:csv/csv.dart';
import 'package:sqflite/sqflite.dart';
import 'package:gact_plugin/gact_plugin.dart';

import 'config.dart';
import 'helper/check_exposures.dart' as bg;
import 'helper/signed_upload.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'storage/exposure.dart';
import 'storage/report.dart';
import 'storage/user.dart';

class AppState with ChangeNotifier {
  static UserModel _user;
  static ReportModel _report;
  static bool _ready = false;
  static Exposure _exposure;

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

  Exposure get exposure => _exposure;

  UserModel get user => _user;

  Future<Exposure> getExposure() async {
    return Exposure.newest;
  }

  Future<Exposure> checkExposures() async {
    await bg.checkExposures();
    _user = await UserModel.find();
    _exposure = await getExposure();
    notifyListeners();
    return _exposure;
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

  Future<List<ExposureKey>> sendExposureKeys(
      {@required Map<String, dynamic> config, DateTime date}) async {
    Iterable<ExposureKey> keys;
    try {
      keys = await GactPlugin.getExposureKeys();
    } catch (err) {
      print(err);
    }

    if (keys == null || keys.isEmpty) {
      return keys?.toList();
    }

    final List<dynamic> _headers = [
      'key_data',
      'rolling_start_number',
      'verified'
    ];
    var data = ListToCsvConverter().convert([_headers] +
        keys.map((key) => [key.keyData, key.rollingStartNumber, false]));

    try {
      var success = await objectUpload(
          config: config,
          bucket: config['exposureKeysHoldingBucket'] ??
              'covidtrace-exposure-keys-holding',
          object: '${user.uuid}.csv',
          contentType: 'text/csv; charset=utf-8',
          data: data);
      return success ? keys.toList() : null;
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
        sendExposureKeys(config: config, date: date),
      ]);

      List<ExposureKey> keys = results[1] ?? [];

      if (keys.isNotEmpty) {
        _report = ReportModel(
            lastExposureKey: keys.last.keyData, timestamp: DateTime.now());
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

  Future<void> resetInfections() async {
    final Database db = await Storage.db;
    await Future.wait([
      db.update('user', {'last_check': null}),
      ExposureModel.destroyAll(),
    ]);
    _exposure = null;
    notifyListeners();
  }
}
