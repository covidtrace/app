import 'package:covidtrace/helper/datetime.dart';
import 'package:covidtrace/storage/user.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../storage/location.dart';
import '../storage/user.dart';
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

  var user = await UserModel.find();

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

  // Big ass map of geo ID -> map of timestamp -> locations
  Map<String, Map<int, List<LocationModel>>> geoLookup = new Map();
  locations.forEach((location) {
    var cellID = location.cellID.parent(compareLevel).toToken();
    var unixHour = roundedDateTime(location.timestamp);

    if (geoLookup[cellID] == null) {
      geoLookup[cellID] = new Map();
    }

    if (geoLookup[cellID][unixHour] == null) {
      geoLookup[cellID][unixHour] = new List();
    }

    geoLookup[cellID][unixHour].add(location);
  });

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
      var parsedRows = CsvToListConverter(shouldParseNumbers: false, eol: '\n')
          .convert(fileCsv);

      // Iterate through rows and search for matching locations
      await Future.forEach(parsedRows, (parsedRow) async {
        var timestamp = roundedDateTime(DateTime.fromMillisecondsSinceEpoch(
            int.parse(parsedRow[0]) * 1000));

        // Note: aggregate CSVs look like
        // [timestamp, cellID.parent(compareLevel), cellID.parent(localLevel), ...]
        // so let's take the cellID at compareLevel
        String compareCellID = parsedRow[1];

        var locationsbyTimestamp = geoLookup[compareCellID];
        if (locationsbyTimestamp != null) {
          var exposures = locationsbyTimestamp[timestamp];

          if (exposures != null) {
            await Future.forEach(exposures, (location) async {
              exposed = true;
              location.exposure = true;
              await location.save();
            });

            showExposureNotification(exposures.last);
          }
        }
      });
    });
  });

  user.lastCheck = DateTime.now();
  await user.save();

  print('Done checking exposures!');
  return exposed;
}

void showExposureNotification(LocationModel location) async {
  var timestamp = location.timestamp.toLocal();

  var notificationPlugin = FlutterLocalNotificationsPlugin();
  var androidSpec = AndroidNotificationDetails(
      'covid_channel_id', 'covid_channel_name', 'covid_channel_description',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iosSpecs = IOSNotificationDetails();
  await notificationPlugin.show(
      0,
      'COVID-19 Exposure Alert',
      'Your location history matched with a reported infection on ${DateFormat.Md().format(timestamp)} ${DateFormat('ha').format(timestamp).toLowerCase()} - ${DateFormat('ha').format(timestamp.add(Duration(hours: 1))).toLowerCase()}',
      NotificationDetails(androidSpec, iosSpecs));
}
