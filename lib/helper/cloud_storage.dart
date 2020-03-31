import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

Future<bool> objectExists(String bucket, String object) async {
  var resp = await http.get('https://storage.googleapis.com/$bucket/$object');
  return resp.statusCode == 200;
}

Future<List<dynamic>> getPrefixMatches(String bucket, String prefix) async {
  var objects = new List<dynamic>();

  var queryParameters = {
    'delimiter': '/',
    'maxResults': '500',
    'prefix': prefix,
  };

  do {
    var resp = await http.get(
        Uri.parse('https://storage.googleapis.com/storage/v1/b/$bucket/o')
            .replace(queryParameters: queryParameters));

    if (resp.statusCode != 200) {
      throw ('Google Cloud Storage returned ${resp.statusCode}!');
    }

    var json = jsonDecode(resp.body);

    var items = json['items'] as List<dynamic>;
    if (items != null) {
      items.forEach((item) => objects.add(item));
    }

    queryParameters['pageToken'] = json['nextPageToken'];
  } while (queryParameters['pageToken'] != null);

  return objects;
}

Future<File> syncObject(
    String localDir, String bucket, String object, String md5hash) async {
  var fileHandle = new File('$localDir/$bucket/$object');

  if (!await fileHandle.exists()) {
    await fileHandle.create(recursive: true);
  }

  var checksum = base64Decode(md5hash);
  var fileBytes = await fileHandle.readAsBytes();
  var fileChecksum = md5.convert(fileBytes).bytes;

  if (!listEquals(checksum, fileChecksum)) {
    var fileResp =
        await http.get('https://$bucket.storage.googleapis.com/$object');

    if (fileResp.statusCode != 200) {
      throw ('Unable to download $bucket/$object!');
    }

    await fileHandle.writeAsBytes(fileResp.bodyBytes);
  }

  return fileHandle;
}
