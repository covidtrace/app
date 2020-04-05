import 'package:covidtrace/helper/cloud_storage.dart';
import 'package:covidtrace/helper/datetime.dart';
import 'package:covidtrace/storage/user.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:tuple/tuple.dart';

import '../config.dart';
import '../storage/location.dart';
import '../storage/user.dart';
import 'dart:async';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

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
  ]);

  var user = results[0];
  var config = results[1];
  var dir = results[2];
  var locations = results[3];

  String publishedBucket = config['publishedBucket'];
  int compareLevel = config['compareS2Level'];
  List<dynamic> aggLevels = config['aggS2Levels'];
  LocationModel exposed;

  // Set of all top level geo prefixes to begin querying
  var geoPrefixes = Set<String>();

  // S2 cell ID to locations at each aggregation level
  var geoLevels = Map<String, List<LocationModel>>();

  // S2 cell ID at compare level -> locations grouped by unix timestamp
  var geoLevelsTimestamp = new Map<String, Map<int, List<LocationModel>>>();

  // Build all structures by iterating over locations only once
  locations.forEach((location) {
    // Populate `geoPrefixes` with least precise S2 geo
    geoPrefixes.add(location.cellID.parent(aggLevels.first as int).toToken());

    // Populate `geoLevels` at each aggregation level
    aggLevels.forEach((level) {
      var cellID = location.cellID.parent(level).toToken();

      if (geoLevels[cellID] == null) {
        geoLevels[cellID] = [];
      }
      geoLevels[cellID].add(location);
    });

    // Populate `geoLevelsTimestamp` object at each aggregation level
    var timestamp = roundedDateTime(location.timestamp);
    var cellID = location.cellID.parent(compareLevel).toToken();
    if (geoLevelsTimestamp[cellID] == null) {
      geoLevelsTimestamp[cellID] = new Map();
    }
    if (geoLevelsTimestamp[cellID][timestamp] == null) {
      geoLevelsTimestamp[cellID][timestamp] = [];
    }
    geoLevelsTimestamp[cellID][timestamp].add(location);
  });

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
    var objectName = object['name'] as String;

    // For now, ignore `token` csvs
    if (objectName.contains(".tokens.csv")) {
      return;
    }

    // Sync file to local storage
    var fileHandle = await syncObject(
        dir.path, publishedBucket, objectName, object['md5Hash'] as String);

    // Parse and compare with local locations.
    var fileCsv = await fileHandle.readAsString();
    var parsedRows = CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(fileCsv);

    // Iterate through rows and search for matching locations
    await Future.forEach(parsedRows, (parsedRow) async {
      var timestamp = roundedDateTime(
          DateTime.fromMillisecondsSinceEpoch(int.parse(parsedRow[0]) * 1000));

      // Note: aggregate point CSVs look like [timestamp, cellID, verified]
      String cellID = parsedRow[1];

      var locationsbyTimestamp = geoLevelsTimestamp[cellID];
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

  user.lastCheck = DateTime.now();
  await user.save();

  if (exposed != null) {
    print('Found new exposure!');
    showExposureNotification(exposed);
  }

  print('Done checking exposures!');
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
