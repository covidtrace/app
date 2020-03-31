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

  var user = await UserModel.find();

  var config = await getConfig();
  List<dynamic> aggLevels = config['aggS2Levels'];
  int compareLevel = config['compareS2Level'];
  String publishedBucket = config['publishedBucket'];

  LocationModel exposed;
  var dir = await getApplicationSupportDirectory();
  var locations = await LocationModel.findAll();

  // Set of all top level geo prefixes to begin querying
  var prefixes = Set<String>();

  // S2 cell ID to locations at each aggregation level
  var geoLevelsLookup = Map<String, List<LocationModel>>();

  // S2 cell ID at compare level -> locations grouped by unix timestamp
  var geoCompareLookup = new Map<String, Map<int, List<LocationModel>>>();

  // Build all structures by iterating over locations only once
  locations.forEach((location) {
    // Populate `prefixes` with least precise S2 geo
    prefixes.add(location.cellID.parent(aggLevels.first as int).toToken());

    // Populate `geoLevelLookup` at each aggregation level
    aggLevels.forEach((level) {
      var cellID = location.cellID.parent(level).toToken();
      if (geoLevelsLookup[cellID] == null) {
        geoLevelsLookup[cellID] = [];
      }

      geoLevelsLookup[cellID].add(location);
    });

    // Populate `geoCompareLookup` object
    var cellID = location.cellID.parent(compareLevel).toToken();
    var unixHour = roundedDateTime(location.timestamp);

    if (geoCompareLookup[cellID] == null) {
      geoCompareLookup[cellID] = new Map();
    }

    if (geoCompareLookup[cellID][unixHour] == null) {
      geoCompareLookup[cellID][unixHour] = [];
    }

    geoCompareLookup[cellID][unixHour].add(location);
  });

  // Build a queue of geos to fetch
  List<Tuple2<String, int>> queue =
      prefixes.map((prefix) => Tuple2(prefix, 0)).toList();

  var objects = [];
  while (queue.length > 0) {
    var prefix = queue.removeAt(0);
    var geo = prefix.item1;
    var level = prefix.item2;

    var hint = await objectExists(publishedBucket, '$geo/0_HINT');
    if (hint && level + 1 < aggLevels.length) {
      queue.addAll(Set.from(locations
              .where((location) =>
                  location.cellID.parent(aggLevels[level]).toToken() == geo)
              .map((location) =>
                  location.cellID.parent(aggLevels[level + 1]).toToken()))
          .map((geo) => Tuple2(geo, level + 1)));
    } else {
      objects.addAll(await getPrefixMatches(publishedBucket, '$geo/'));
    }
  }

  // Fetch all the objects (probably should throttle this)
  await Future.wait(objects.where((object) {
    // Filter objects for any that are lexically equal to or greater than
    // the CSVs we last downloaded. If we have never checked before, we
    // should fetch everything for the last three weeks
    var lastCheck = user.lastCheck;
    if (lastCheck == null) {
      lastCheck = DateTime.now().subtract(Duration(days: 21));
    }

    // Strip off geo prefix for lexical comparison
    var name = object['name'] as String;
    var nameParts = name.split('/');
    if (nameParts.length != 2) {
      return false;
    }

    // Perform lexical comparison
    var unixCsv = nameParts[1];
    var lastCsv = '${(lastCheck.millisecondsSinceEpoch / 1000).round()}.csv';
    return unixCsv.compareTo(lastCsv) >= 0;
  }).map((object) async {
    // Sync file to local storage
    var fileHandle = await syncObject(dir.path, publishedBucket,
        object['name'] as String, object['md5Hash'] as String);

    // Parse and compare with local locations.
    var fileCsv = await fileHandle.readAsString();
    var parsedRows = CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(fileCsv);

    // Iterate through rows and search for matching locations
    await Future.forEach(parsedRows, (parsedRow) async {
      var timestamp = roundedDateTime(
          DateTime.fromMillisecondsSinceEpoch(int.parse(parsedRow[0]) * 1000));

      // Note: aggregate CSVs look like
      // [timestamp, cellID.parent(compareLevel), cellID.parent(localLevel), ...]
      // so let's take the cellID at compareLevel
      String compareCellID = parsedRow[1];

      var locationsbyTimestamp = geoCompareLookup[compareCellID];
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
