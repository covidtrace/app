import 'dart:convert';
import 'package:http/http.dart' as http;

Future<dynamic> getConfig() async {
  var configResp = await http
      .get("https://storage.googleapis.com/covidtrace-config/config.json");
  if (configResp.statusCode != 200) {
    throw ("Unable to fetch config file");
  }
  return jsonDecode(configResp.body);
}
