import 'dart:async';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/exposure.dart';
import 'package:covidtrace/exposure/beacon.dart';
import 'package:covidtrace/exposure/location.dart';
import 'package:covidtrace/helper/beacon.dart';
import 'package:covidtrace/helper/cloud_storage.dart';
import 'package:covidtrace/storage/beacon.dart';
import 'package:covidtrace/storage/location.dart';
import 'package:covidtrace/storage/user.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tuple/tuple.dart';

Future<Exposure> checkExposures() async {
  print('Checking exposures...');
  var threeWeeksAgo = DateTime.now().subtract(Duration(days: 21));
  var whereArgs = [threeWeeksAgo.toIso8601String()];

  var results = await Future.wait([
    UserModel.find(),
    getConfig(),
    getApplicationSupportDirectory(),
    LocationModel.findAll(
        where: 'exposure = 0 AND DATE(timestamp) >= DATE(?)',
        whereArgs: whereArgs),
    BeaconModel.findAll(
        where: 'exposure = 0 AND DATE(start) >= DATE(?)', whereArgs: whereArgs),
  ]);

  var user = results[0];
  var config = results[1];
  var dir = results[2];
  var locations = results[3];
  var beacons = results[4];

  String publishedBucket = config['publishedBucket'];
  int compareLevel = config['compareS2Level'];
  List<dynamic> aggLevels = config['aggS2Levels'];
  Duration timeResolution = Duration(minutes: config['timeResolution'] ?? 60);

  // Structures for exposures
  Map<int, LocationModel> exposedLocations = {};
  var locationExposure =
      new LocationExposure(locations, compareLevel, timeResolution);

  Map<int, BeaconModel> exposedBeacons = {};
  var beaconExposure = new BeaconExposure(beacons, compareLevel);

  // Set of all top level geo prefixes to begin querying
  var geoPrefixes = Set<String>.from(locations.map(
      (location) => location.cellID.parent(aggLevels.first as int).toToken()));

  // Build a queue of geos to fetch
  List<Tuple2<String, int>> geoPrefixQueue =
      geoPrefixes.map((prefix) => Tuple2(prefix, 0)).toList();

  // BFS through published bucket using `geoPrefixQueue`
  var objects = [];
  while (geoPrefixQueue.length > 0) {
    var prefix = geoPrefixQueue.removeAt(0);
    var geo = prefix.item1;
    var level = prefix.item2;

    var hint = await objectExists(publishedBucket, '$geo/0_HINT');
    if (hint && level + 1 < aggLevels.length) {
      geoPrefixQueue.addAll(Set.from(locations
              .where((location) =>
                  location.cellID.parent(aggLevels[level]).toToken() == geo)
              .map((location) =>
                  location.cellID.parent(aggLevels[level + 1]).toToken()))
          .map((geo) => Tuple2(geo, level + 1)));
    } else {
      objects.addAll(await getPrefixMatches(publishedBucket, '$geo/'));
    }
  }

  // Filter objects for any that are lexically equal to or greater than
  // the CSVs we last downloaded. If we have never checked before, we
  // should fetch everything for the last three weeks
  var lastCheck = user.lastCheck ?? threeWeeksAgo;
  var lastCsv = '${(lastCheck.millisecondsSinceEpoch / 1000).floor()}.csv';

  await Future.wait(objects.where((object) {
    // Strip off geo prefix for lexical comparison
    var objectName = object['name'] as String;
    var objectNameParts = objectName.split('/');
    if (objectNameParts.length != 2) {
      return false;
    }

    // Perform lexical comparison. Object names look like: '$UNIX_TS.$TYPE.csv'
    // where $TYPE is one of `points` or `tokens`. We want to compare
    // '$UNIX_TS.csv' to `lastCsv`
    var fileName = objectNameParts[1];
    var fileNameParts = fileName.split('.');
    if (fileNameParts.length < 1) {
      return false;
    }
    var unixTs = fileNameParts[0];

    //  Lexical comparison
    return '$unixTs.csv'.compareTo(lastCsv) >= 0;
  }).map((object) async {
    var objectName = object['name'] as String;
    print('processing $objectName');

    // Sync file to local storage
    var file = await syncObject(
        dir.path, publishedBucket, objectName, object['md5Hash'] as String);

    // Find exposures and update!
    if (objectName.contains(".tokens.csv")) {
      var exposed =
          await beaconExposure.getExposures(await file.readAsString());
      exposed.forEach((e) => exposedBeacons[e.id] = e);
    } else {
      var exposed =
          await locationExposure.getExposures(await file.readAsString());
      exposed.forEach((e) => exposedLocations[e.id] = e);
    }
  }));

  user.lastCheck = DateTime.now();
  await user.save();

  if (exposedBeacons.isNotEmpty) {
    print('Found new beacon exposures!');
    var locations = await matchBeaconsAndLocations(exposedBeacons.values);
    exposedLocations.addAll(locations);
  }

  // Save all exposed beacons and locations
  var exposures = [
    ...exposedBeacons.values.map((b) => Exposure(b)),
    ...exposedLocations.values.map((l) => Exposure(l)),
  ];

  await Future.wait(
    exposures.map((e) {
      e.exposure = true;
      return e.save();
    }),
  );

  exposures.sort((a, b) => a.end.compareTo(b.end));
  var exposure = exposures.isNotEmpty ? exposures.last : null;

  if (exposure != null) {
    showExposureNotification(exposure);
  }

  print('Done checking exposures!');
  return exposure;
}

void showExposureNotification(Exposure exposure) async {
  var start = exposure.start.toLocal();
  var end = exposure.end.toLocal();
  var timeFormat = DateFormat('ha');
  if (exposure.duration.compareTo(Duration(hours: 1)) < 0) {
    timeFormat = DateFormat.jm();
  }

  var notificationPlugin = FlutterLocalNotificationsPlugin();
  var androidSpec = AndroidNotificationDetails(
      '1', 'COVID Trace', 'Exposure notifications',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iosSpecs = IOSNotificationDetails();
  await notificationPlugin.show(
      0,
      'COVID-19 Exposure Alert',
      'Your location history matched with a reported infection on ${DateFormat.Md().format(start)} ${timeFormat.format(start).toLowerCase()} - ${timeFormat.format(end).toLowerCase()}',
      NotificationDetails(androidSpec, iosSpecs),
      payload: 'Default_Sound');
}
