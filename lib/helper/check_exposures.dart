import 'dart:async';
import 'dart:io';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/helper/cloud_storage.dart';
import 'package:covidtrace/storage/exposure.dart';
import 'package:covidtrace/storage/user.dart';
import 'package:csv/csv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

Future<ExposureInfo> checkExposures() async {
  print('Checking exposures...');

  var results = await Future.wait([
    UserModel.find(),
    getConfig(),
    getApplicationSupportDirectory(),
  ]);

  var user = results[0];
  var config = results[1];
  var dir = results[2] as Directory;

  String publishedBucket = config['exposureKeysPublishedBucket'];
  var objects = await getPrefixMatches(publishedBucket, '');

  // Filter objects for any that are lexically equal to or greater than
  // the CSVs we last downloaded. If we have never checked before, we
  // should fetch everything for the last three weeks
  var threeWeeksAgo = DateTime.now().subtract(Duration(days: 21));
  var lastCheck = user.lastCheck ?? threeWeeksAgo;
  var lastCsv = '${(lastCheck.millisecondsSinceEpoch / 1000).floor()}.csv';
  List<Uri> keyFiles = [];

  await Future.wait(objects.where((object) {
    // Strip off geo prefix for lexical comparison
    var fileName = object['name'] as String;

    // Perform lexical comparison. Object names look like: '$UNIX_TS.csv'
    var fileNameParts = fileName.split('.');
    var unixTs = fileNameParts[0];

    //  Lexical comparison
    return '$unixTs.csv'.compareTo(lastCsv) >= 0;
  }).map((object) async {
    var objectName = object['name'] as String;
    print('processing $objectName');

    // Sync file to local storage and parse
    var file = File('${dir.path}/$publishedBucket/$objectName');
    await syncObject(
        file, publishedBucket, objectName, object['md5Hash'] as String);

    // Parse CSV file and convert to ExposureKeys
    var rows = CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(await file.readAsString());

    var keyFile = File('${dir.path}/$publishedBucket/$objectName.pb');
    var keys = rows.map((row) =>
        ExposureKey(row[0], int.parse(row[1]), int.parse(row[2]), row[3]));

    await GactPlugin.saveExposureKeyFile(keys, keyFile);
    keyFiles.add(keyFile.uri);
  }));

  // Save all found exposures
  // TODO(wes): Need a way to prevent duplicate exposures
  var exposures = await GactPlugin.detectExposures(keyFiles);
  await Future.wait(exposures.map((e) {
    return ExposureModel(
            date: e.date,
            duration: e.duration,
            attenuationValue: e.attenuationValue)
        .insert();
  }));

  user.lastCheck = DateTime.now();
  await user.save();

  exposures.sort((a, b) => a.date.compareTo(b.date));
  var exposure = exposures.isNotEmpty ? exposures.last : null;

  if (exposure != null) {
    showExposureNotification(exposure);
  }

  print('Done checking exposures!');
  return exposure;
}

void showExposureNotification(ExposureInfo exposure) async {
  var date = exposure.date.toLocal();
  var dur = exposure.duration;
  var notificationPlugin = FlutterLocalNotificationsPlugin();

  var androidSpec = AndroidNotificationDetails(
      '1', 'COVID Trace', 'Exposure notifications',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iosSpecs = IOSNotificationDetails();
  await notificationPlugin.show(
      0,
      'COVID-19 Exposure Alert',
      'You where exposed to someone who reported an infection on ${DateFormat.EEEE().add_MMMd().format(date)} for ${dur.inMinutes} minutes.',
      NotificationDetails(androidSpec, iosSpecs),
      payload: 'Default_Sound');
}
