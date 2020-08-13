import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Config {
  static Map<String, dynamic> _local;

  static Map<String, dynamic> _remote;

  static Map<String, dynamic> get() => _local;

  static bool get loaded => _local != null;

  static Future<Map<String, dynamic>> load() async {
    if (loaded) {
      return _local;
    }

    WidgetsFlutterBinding.ensureInitialized();

    var source = await rootBundle.loadString('assets/config.json');
    _local = jsonDecode(source);

    return _local;
  }

  static Future<Map<String, dynamic>> remote() async {
    // TODO(wes): Store last remote refresh and invalidate every 12 hours
    if (_remote != null) {
      return _remote;
    }

    if (!loaded) {
      await load();
    }

    // Allow local "remote" configuration for easier development/testing
    var remoteUrl = Uri.parse(_local['remote']);
    if (remoteUrl.hasScheme) {
      var configResp = await http.get(remoteUrl.toString());
      if (configResp.statusCode != 200) {
        throw ("Unable to fetch config file");
      }
      _remote = jsonDecode(configResp.body) as Map<String, dynamic>;
    } else {
      var configResp = await rootBundle.loadString(remoteUrl.toString());
      _remote = jsonDecode(configResp) as Map<String, dynamic>;
    }

    return _remote;
  }
}
