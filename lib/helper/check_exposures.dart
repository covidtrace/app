import 'dart:async';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/exposure/beacon.dart';
import 'package:covidtrace/exposure/location.dart';
import 'package:covidtrace/helper/cloud_storage.dart';
import 'package:covidtrace/storage/beacon.dart';
import 'package:covidtrace/storage/location.dart';
import 'package:covidtrace/storage/user.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tuple/tuple.dart';

Future<bool> checkExposures() async {
  print('Checking exposures...');

  var threeWeeksAgo = DateTime.now().subtract(Duration(days: 21));

  var results = await Future.wait([
    UserModel.find(),
    getConfig(),
    getApplicationSupportDirectory(),
    LocationModel.findAll(
        where: 'exposure = 0 AND DATE(timestamp) >= DATE(?)',
        whereArgs: [
          threeWeeksAgo.toIso8601String()
        ]), // no use searching already exposed locations or older than 3 weeks
    Future.value([] as List<BeaconUuid>)
  ]);

  var user = results[0];
  var config = results[1];
  var dir = results[2];
  var locations = results[3];
  var beacons = results[4];

  String publishedBucket = config['publishedBucket'];
  int compareLevel = config['compareS2Level'];
  List<dynamic> aggLevels = config['aggS2Levels'];

  // Structures for location exposure
  LocationModel exposedLocation;
  var locationExposure = new LocationExposure(locations, compareLevel);

  BeaconModel exposedBeacon;
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
  var lastCheck = user.lastCheck;
  if (lastCheck == null) {
    lastCheck = threeWeeksAgo;
  }
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
    // For now, ignore `token` csvs
    var objectName = object['name'] as String;
    if (objectName.contains(".tokens.csv")) {
      return;
    }

    // Sync file to local storage
    var file = await syncObject(
        dir.path, publishedBucket, objectName, object['md5Hash'] as String);

    // Find exposures and update!
    if (objectName.contains(".tokens.csv")) {
      var exposures =
          await beaconExposure.getExposures(await file.readAsString());

      if (exposures.length > 0) {
        exposures.sort((a, b) => a.start.compareTo(b.start));
        exposedBeacon = exposures.last;
        await Future.wait(exposures.map((beacon) async {
          // TODO(Wes) save state
        }));
      }
    } else {
      var exposures =
          await locationExposure.getExposures(await file.readAsString());

      if (exposures.length > 0) {
        exposures.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        exposedLocation = exposures.last;
        await Future.wait(exposures.map((location) async {
          location.exposure = true;
          await location.save();
        }));
      }
    }
  }));

  user.lastCheck = DateTime.now();
  await user.save();

  if (exposedLocation != null) {
    print('Found new exposure!');
    showExposureNotification(exposedLocation);
  }

  print('Done checking exposures!');
  return exposedLocation != null;
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
      NotificationDetails(androidSpec, iosSpecs),
      payload: 'Default_Sound');
}
