import '../config.dart';
import '../storage/location.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

Future<bool> checkExposures() async {
  print('Checking exposures...');

  var config = await getConfig();
  int aggLevel = config['aggS2Level'];
  int compareLevel = config['compareS2Level'];
  String publishedBucket = config['publishedBucket'];

  var exposed = false;
  var dir = await getApplicationSupportDirectory();

  // Collection set of truncated geos for google cloud rsync
  var locations = await LocationModel.findAll();
  var geos = Set.from(
      locations.map((location) => location.cellID.parent(aggLevel).toToken()));

  // for each truncated geo, download aggregated data
  await Future.forEach(geos, (geo) async {
    var listResp = await http.get(
        'https://storage.googleapis.com/storage/v1/b/$publishedBucket/o?prefix=$geo'); // TODO(Josh): paging?

    if (listResp.statusCode != 200) {
      throw ('Google Cloud Storage returned ${listResp.statusCode}!');
    }

    var listJson = jsonDecode(listResp.body);
    List<dynamic> listItems = listJson['items'];
    if (listItems == null) {
      return;
    }

    await Future.forEach(listItems, (item) async {
      String object = item['name'];
      print('Syncing $object...');

      var fileHandle = new File('${dir.path}/$publishedBucket/$object');

      if (!await fileHandle.exists()) {
        await fileHandle.create(recursive: true);
      }

      var checksum = base64Decode(item['md5Hash'] as String);
      var fileBytes = await fileHandle.readAsBytes();
      var fileChecksum = md5.convert(fileBytes).bytes;

      if (!listEquals(checksum, fileChecksum)) {
        var fileResp = await http
            .get('https://$publishedBucket.storage.googleapis.com/$object');

        if (fileResp.statusCode != 200) {
          throw ('Unable to download Google Cloud Storage object $object!');
        }

        await fileHandle.writeAsBytes(fileResp.bodyBytes);
      }

      // We have the relevant file, locally, with proper checksum. Parse and compare with local locations.
      var fileCsv = await fileHandle.readAsString();
      var parsedRows = CsvToListConverter(eol: '\n').convert(fileCsv);

      // Iterate through rows and search for matching locations
      await Future.forEach(parsedRows, (parsedRow) async {
        var timestamp =
            DateTime.fromMillisecondsSinceEpoch(parsedRow[0] * 1000);
        String cellID = parsedRow[1];

        var exposures = locations
            .where((location) =>
                location.cellID.parent(compareLevel).toToken() == cellID &&
                timestamp.millisecondsSinceEpoch -
                        location.timestamp.millisecondsSinceEpoch <
                    1000 * 60 * 60)
            .toList();

        await Future.forEach(exposures, (location) async {
          exposed = true;
          location.exposure = true;
          await location.save();
        });
      });
    });
  });

  print('Done checking exposures!');
  return exposed;
}
