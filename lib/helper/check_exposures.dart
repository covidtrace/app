import 'package:covidtrace/helper/cloud_storage.dart';
import 'package:covidtrace/helper/datetime.dart';
import 'package:covidtrace/storage/user.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../storage/location.dart';
import '../storage/user.dart';
import 'dart:async';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

Future<bool> checkExposures() async {
  print('Checking exposures...');

  var user = await UserModel.find();

  var config = await getConfig();
  int aggIndex = config['aggS2Index'];
  List<dynamic> aggLevels = config['aggS2Levels'];
  int compareLevel = config['compareS2Level'];
  String publishedBucket = config['publishedBucket'];

  LocationModel exposed;
  var dir = await getApplicationSupportDirectory();

  // Collection set of truncated geos for google cloud rsync
  var locations = await LocationModel.findAll();
  var geos = Set.from(locations.map((location) =>
      location.cellID.parent(aggLevels[aggIndex] as int).toToken()));

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

  await Future.forEach(geos, (geo) async {
    var objects = await getPrefixMatches(publishedBucket, '$geo/');

    await Future.wait(objects.map((item) async {
      // Sync file to local storage
      var fileHandle = await syncObject(dir.path, publishedBucket,
          item['name'] as String, item['md5Hash'] as String);

      // Parse and compare with local locations.
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
            exposed = exposures.last;
            await Future.forEach(exposures, (location) async {
              location.exposure = true;
              await location.save();
            });
          }
        }
      });
    }));
  });

  user.lastCheck = DateTime.now();
  await user.save();

  print('Done checking exposures!');
  if (exposed != null) {
    showExposureNotification(exposed);
  }

  return exposed != null;
}

void showExposureNotification(LocationModel location) async {
  var timestamp = location.timestamp.toLocal();

  var notificationPlugin = FlutterLocalNotificationsPlugin();
  var androidSpec = AndroidNotificationDetails(
      '1', 'COVID Trace', 'Exposure notifications',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iosSpecs = IOSNotificationDetails();
  await notificationPlugin.show(
      0,
      'COVID-19 Exposure Alert',
      'Your location history matched with a reported infection on ${DateFormat.Md().format(timestamp)} ${DateFormat('ha').format(timestamp).toLowerCase()} - ${DateFormat('ha').format(timestamp.add(Duration(hours: 1))).toLowerCase()}',
      NotificationDetails(androidSpec, iosSpecs));
}
