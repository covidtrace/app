import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Config {
  static Map<String, dynamic> _local;

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

  static Future<dynamic> remote() async {
    if (!loaded) {
      await load();
    }

    var configResp = await http.get(_local['remote']);
    if (configResp.statusCode != 200) {
      throw ("Unable to fetch config file");
    }
    return jsonDecode(configResp.body);
  }
}
