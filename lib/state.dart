import 'dart:async';
import 'dart:convert';

import 'package:covidtrace/config.dart';
import 'package:covidtrace/helper/check_exposures.dart' as bg;
import 'package:covidtrace/helper/metrics.dart' as metrics;
import 'package:covidtrace/storage/db.dart';
import 'package:covidtrace/storage/exposure.dart';
import 'package:covidtrace/storage/report.dart';
import 'package:covidtrace/storage/user.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:package_info/package_info.dart';
import 'package:sqflite/sqflite.dart';

class NotificationState with ChangeNotifier {
  static final instance = NotificationState();

  void onNotice(String notice) {
    notifyListeners();
  }
}

class AppState with ChangeNotifier {
  static UserModel _user;
  static ReportModel _report;
  static bool _ready = false;
  static ExposureModel _exposure;
  static AuthorizationStatus _status;

  AppState() {
    initState();
    NotificationState.instance.addListener(() async {
      setExposure(await getExposure());
    });
  }

  initState() async {
    _user = await UserModel.find();
    _report = await ReportModel.findLatest();
    _exposure = await getExposure();
    _status = await checkStatus();
    _ready = true;

    if (_user.firstRun) {
      _user.firstRun = false;
      await _user.save();
      metrics.install();
    }

    notifyListeners();
  }

  bool get ready => _ready;

  ExposureModel get exposure => _exposure;

  UserModel get user => _user;

  AuthorizationStatus get status => _status;

  Future<ExposureModel> getExposure() async {
    var rows = await ExposureModel.findAll(limit: 1, orderBy: 'date DESC');

    return rows.isNotEmpty ? rows.first : null;
  }

  void setExposure(ExposureModel exposure) {
    _exposure = exposure;
    notifyListeners();
  }

  Future<AuthorizationStatus> checkStatus() async {
    _status = await GactPlugin.authorizationStatus;
    notifyListeners();
    return _status;
  }

  Future<ExposureModel> checkExposures() async {
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

  Future<void> saveReport(ReportModel report) async {
    _report = report;
    await _report.create();
    notifyListeners();
  }

  Future<List<ExposureKey>> sendExposureKeys(
      Map<String, dynamic> config, String verificationCode) async {
    Iterable<ExposureKey> keys;

    try {
      // Note that using `testMode: true` will include today's exposure key
      // which will be rejected by the exposure server if included.
      keys = await GactPlugin.getExposureKeys(testMode: false);
    } catch (err) {
      print(err);
      if (errorFromException(err) == ErrorCode.notAuthorized) {
        return null;
      }
    }

    if (keys == null || keys.isEmpty) {
      return keys?.toList();
    }

    var cert = await verifyCode(verificationCode, keys);
    if (cert == null) {
      return null;
    }

    var postData = {
      "regions": ['US'],
      "appPackageName": (await PackageInfo.fromPlatform()).packageName,
      "revisionToken": user.revisionToken,
      "temporaryExposureKeys": keys
          .map((k) => {
                "key": k.keyData,
                "rollingPeriod": k.rollingPeriod,
                "rollingStartNumber": k.rollingStartNumber,
                "transmissionRisk": k.transmissionRiskLevel
              })
          .toList(),
      "verificationPayload": cert,
      "hmackey": base64.encode(utf8.encode(_user.uuid)),
    };
    print('Sending TEKs');
    print(postData);

    var postResp = await http.post(
      Uri.parse(config['exposurePublishUrl']),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(postData),
    );

    if (postResp.statusCode == 200) {
      // Store revisionToken to allow resubmission of TEKS
      var data = jsonDecode(postResp.body) as Map<String, dynamic>;
      if (data.containsKey('revisionToken')) {
        user.revisionToken = data['revisionToken'];
        await saveUser(user);
      }

      return keys.toList();
    } else {
      print('Error exporting TEKs: ${postResp.statusCode}');
      print(postResp.body);
      throw (getErrorMessage(postResp));
    }
  }

  Future<bool> sendReport(String verificationCode) async {
    var success = false;
    var config = await Config.remote();

    List<ExposureKey> keys =
        await sendExposureKeys(config, verificationCode) ?? [];

    if (keys.isNotEmpty) {
      _report = ReportModel(
          lastExposureKey: keys.last.keyData, timestamp: DateTime.now());
      await report.create();
      success = true;
    }

    notifyListeners();

    if (success) {
      metrics.notify();
    }

    return success;
  }

  Future<String> verifyCode(
      String verificationCode, Iterable<ExposureKey> keys) async {
    var config = await Config.remote();

    var uri = Uri.parse('${config['verifyUrl']}/api/verify');
    var postResp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': config['verifyApiKey']
      },
      body: jsonEncode({"code": verificationCode}),
    );
    print(postResp.body);

    var statusCode = postResp.statusCode;
    print('Verification code result');
    print(postResp.statusCode);
    print(postResp.body);

    if (statusCode == 429) {
      throw ('errors.too_many_attempts');
    }

    if (statusCode != 200) {
      var code = getErrorCode(postResp);
      if (code == 'token_invalid') {
        throw ('errors.verify_code_failed');
      } else {
        throw (getErrorMessage(postResp));
      }
    }

    var body = jsonDecode(postResp.body);
    var token = body['token'];
    var testType = body['testtype'];

    if (testType != 'confirmed') {
      throw ('errors.verify_type_unconfirmed');
    }

    // Calculate and submit HMAC
    // See: https://developers.google.com/android/exposure-notifications/verification-system#hmac-calc
    var hmacSha256 = new Hmac(sha256, utf8.encode(_user.uuid));
    var sortedKeys = keys.toList();
    sortedKeys.sort((a, b) => a.keyData.compareTo(b.keyData));
    var bytes = sortedKeys
        .map((k) =>
            '${k.keyData}.${k.rollingStartNumber}.${k.rollingPeriod}.${k.transmissionRiskLevel}')
        .join(',');
    var digest = hmacSha256.convert(utf8.encode(bytes));

    uri = Uri.parse('${config['verifyUrl']}/api/certificate');
    postResp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': config['verifyApiKey']
      },
      body:
          jsonEncode({"token": token, 'ekeyhmac': base64.encode(digest.bytes)}),
    );

    print(postResp.body);
    if (postResp.statusCode != 200) {
      throw (postResp.body);
    }

    body = jsonDecode(postResp.body);
    var certificate = body['certificate'];

    return certificate;
  }

  String getErrorCode(Response resp) {
    try {
      var body = jsonDecode(resp.body);
      return body['errorCode'];
    } catch (err) {
      return null;
    }
  }

  String getErrorMessage(Response resp) {
    try {
      var body = jsonDecode(resp.body);
      return body['error'] ?? resp.body;
    } catch (err) {
      return resp.body;
    }
  }

  Future<void> clearReport() async {
    await ReportModel.destroyAll();
    _report = null;
    notifyListeners();
  }

  Future<void> resetInfections() async {
    final Database db = await Storage.db;
    await Future.wait([
      db.update('user', {'last_check': null, 'last_key_file': null}),
      ExposureModel.destroyAll(),
    ]);
    _exposure = null;
    notifyListeners();
  }
}
