import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppConfig {
  static Map<String, dynamic> _config;

  static Map<String, dynamic> get() => _config;

  static Future<void> load() async {
    WidgetsFlutterBinding.ensureInitialized();

    var source = await rootBundle.loadString('assets/config.json');
    _config = jsonDecode(source);
  }
}
