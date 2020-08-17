import 'dart:convert';
import 'dart:io';

import 'package:covidtrace/config.dart';
import 'package:flutter_safetynet_attestation/flutter_safetynet_attestation.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

Future<http.Response> report(Map<String, dynamic> postData) async {
  Map<String, dynamic> config;
  try {
    config = await Config.remote();
  } catch (err) {
    print('Unable to fetch remote config');
    return null;
  }

  // Silently ignore unconfigured metric reporting
  if (!config.containsKey('metricsPublishUrl')) {
    print('Metric reporting is not configured');
    return null;
  }

  // Add deviceCheck or Attestation to payload depending on platform
  if (Platform.isIOS) {
    try {
      postData['deviceCheck'] = await GactPlugin.deviceCheck;
    } catch (err) {
      print('metric deviceCheck error');
      print(err);
    }
  }

  if (Platform.isAndroid) {
    try {
      var available =
          await FlutterSafetynetAttestation.googlePlayServicesAvailability();
      if (available != GooglePlayServicesAvailability.success) {
        return null;
      }

      var nonce = Uuid().v4();
      var jwt =
          await FlutterSafetynetAttestation.safetyNetAttestationJwt(nonce);
      postData['deviceAttestation'] = jwt;
    } catch (err) {
      print('metric attestation error');
      print(err);
    }
  }

  var url = config['metricsPublishUrl'];
  var postResp;
  try {
    postResp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(postData),
    );

    if (postResp.statusCode != 200) {
      print('Metric reporting error ${postResp.statusCode}');
      print(postResp.body);
    }
  } catch (err) {
    print('Unable to report metric: ${jsonEncode(postData)}');
    print(err);
  }

  return postResp;
}

Future install() {
  return report({
    "event": "install",
  });
}

Future onboard({bool authorized = false, bool notifications = false}) {
  return report({
    "event": "onboard",
    "payload": {
      "en_enabled": authorized,
      "notifications_enabled": notifications,
    }
  });
}

Future exposure() {
  return report({
    "event": "exposure",
  });
}

Future contact() {
  return report({
    "event": "contact",
  });
}

Future notify() {
  return report({
    "event": "notify",
  });
}
