import 'dart:convert';
import 'package:covidtrace/config.dart';
import 'package:http/http.dart' as http;
import 'package:jaguar_jwt/jaguar_jwt.dart';

DateTime _getTokenExpiration(String token) {
  var parts = token.split(".");
  var payload = parts[1];
  var decoded = B64urlEncRfc7515.decodeUtf8(payload);
  var claims = jsonDecode(decoded);
  return DateTime.fromMillisecondsSinceEpoch((claims['exp'] as int) * 1000);
}

class Token {
  final String token;
  final String refreshToken;

  Token({this.token, this.refreshToken});

  bool get valid => token != null && refreshToken != null;

  Future<Token> refreshed() async {
    var expiresAt = _getTokenExpiration(token);
    if (expiresAt.isAfter(DateTime.now())) {
      return this;
    }

    return await Operator.refresh(refreshToken);
  }
}

class Operator {
  static Future<String> init(String phone) async {
    var config = await getConfig();
    String operatorUrl = config['operatorUrl'];

    var resp = await http.post('$operatorUrl/init',
        body: jsonEncode({'phone': phone}));

    if (resp.statusCode != 200) {
      return null;
    }

    var result = jsonDecode(resp.body);
    return result['token'] as String;
  }

  static Future<Token> verify(String token, String code) async {
    var config = await getConfig();
    String operatorUrl = config['operatorUrl'];

    var resp = await http.post('$operatorUrl/verify',
        body: jsonEncode({
          'code': code,
          'token': token,
        }));

    if (resp.statusCode != 200) {
      return null;
    }

    var result = jsonDecode(resp.body);
    return Token(token: result['token'], refreshToken: result['refresh']);
  }

  static Future<Token> refresh(String refreshToken) async {
    var config = await getConfig();
    String operatorUrl = config['operatorUrl'];

    var resp = await http.post(Uri.parse('$operatorUrl/refresh')
        .replace(queryParameters: {'code': refreshToken}));

    if (resp.statusCode != 200) {
      return null;
    }

    var result = jsonDecode(resp.body);
    return Token(token: result['token'], refreshToken: result['refresh']);
  }
}
