import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class Config {
  static var remoteCacheDuration = Duration(hours: 24);

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

    try {
      remote();
    } catch (err) {
      print('Unable to load remote config');
      print(err);
    }

    return _local;
  }

  static Future<Map<String, dynamic>> remote() async {
    var config;
    var dir = await getApplicationSupportDirectory();

    var file = File('${dir.path}/remote_config.json');
    if (await file.exists()) {
      var modified = await file.lastModified();

      if (DateTime.now().difference(modified).compareTo(
              kReleaseMode ? remoteCacheDuration : Duration(seconds: 10)) <
          0) {
        print('returning cached config');
        print(modified);
        return jsonDecode(await file.readAsString());
      }
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
      config = jsonDecode(configResp.body) as Map<String, dynamic>;
    } else {
      var configResp = await rootBundle.loadString(remoteUrl.toString());
      config = jsonDecode(configResp) as Map<String, dynamic>;
    }

    // Save config to disk
    try {
      await file.create(recursive: true);
      file.writeAsString(jsonEncode(config));
      print('Saved remote config to disk');
    } catch (err) {
      print('Error saving remote config to disk');
      print(err);
    }

    // Merge overrides
    if (config.containsKey('override')) {
      var override = config['override'] as Map<String, dynamic>;
      override.forEach((key, value) {
        if (value is Map) {
          (_local[key] as Map).addAll(value);
        } else {
          _local[key] = value;
        }
      });
    }

    return config;
  }
}
