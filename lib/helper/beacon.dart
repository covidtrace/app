import 'dart:async';

import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:covidtrace/storage/beacon.dart';
import 'package:covidtrace/storage/location.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// COVID Trace Beacon UUID
const String BEACON_UUID = '9F9D2C7D-5022-4052-A36B-B225DBC5E6D2';
List<Region> regions = [
  Region(identifier: 'com.covidtrace.app', proximityUUID: BEACON_UUID)
];

final BeaconBroadcast beaconBroadcast = BeaconBroadcast();
StreamSubscription<RangingResult> _streamRanging;
BeaconUuid _beacon;
bool _broadcasting = false;
bool _advertising = false;
StreamSubscription _advertisingStream;
Timer _sequenceTimer;

void setupBeaconBroadcast() {
  beaconBroadcast
      .setUUID(BEACON_UUID)
      .setIdentifier('com.covidtrace.app')
      .setLayout('m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24') // iBeacon
      .setManufacturerId(0x004C); // Apple

  startAdvertising();
}

Future<void> setupBeaconScanning() async {
  try {
    var success = await flutterBeacon.initializeScanning;
    print('initScan $success');
  } catch (err) {
    print(err);
  }

  // Start monitoring for entry/exit of a region
  flutterBeacon.monitoring(regions).listen((MonitoringResult result) async {
    print('monitoring... $result');
    print(result.monitoringEventType);
    print(result.monitoringState);
    print(result.region);

    switch (result.monitoringState) {
      case MonitoringState.inside:
        var advertising = await beaconBroadcast.isAdvertising();
        if (!advertising) {
          showBeaconNotification();
        }
        startRegionRange();
        break;
      case MonitoringState.outside:
        stopRegionRange();
        break;
      case MonitoringState.unknown:
        break;
    }
  });
}

void startRegionRange() {
  print('starting region range');
  _streamRanging =
      flutterBeacon.ranging(regions).listen((RangingResult result) async {
    // TODO(wes): Rotate clientId if there is a collision detected
    Future.wait(
        result.beacons.map((b) => BeaconTransmission.seen(b.major, b.minor)));
    await cleanupTransmissions();
  });
}

Future<void> cleanupTransmissions() async {
  var count = await BeaconTransmission.endUnseen();
  if (count > 0) {
    await BeaconTransmission.convertCompleted();
  }
}

Future<void> stopRegionRange() async {
  print('stopping region range');
  _streamRanging?.cancel();
  await Future.delayed(BeaconTransmission.UNSEEN_TIMEOUT);
  await cleanupTransmissions();
}

Future<void> startAdvertising() async {
  _broadcasting = true;
  _beacon = await BeaconUuid.get();
  _advertisingStream = beaconBroadcast
      .getAdvertisingStateChange()
      .listen((isAdvertising) => _advertising = isAdvertising);

  _sequenceTimer?.cancel();
  _sequenceTimer = Timer.periodic(Duration(seconds: 4), (timer) async {
    if (_advertising) {
      beaconBroadcast.stop();
      await Future.delayed(Duration(seconds: 2));
    }

    if (!timer.isActive || !_broadcasting) {
      return;
    }

    await _beacon.next();
    beaconBroadcast.setMajorId(_beacon.major);
    beaconBroadcast.setMinorId(_beacon.minor);

    if (!_advertising) {
      beaconBroadcast.start();
    }
  });
}

void stopAdvertising() {
  _broadcasting = false;
  _sequenceTimer?.cancel();
  beaconBroadcast.stop();
  _advertising = false;
  _advertisingStream.cancel();
}

bool isBroadcasting() => _broadcasting;

BeaconUuid getBeaconUuid() => _beacon;

void showBeaconNotification() async {
  var notificationPlugin = FlutterLocalNotificationsPlugin();
  var androidSpec = AndroidNotificationDetails(
      '1', 'COVID Trace', 'Beacon notification',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iosSpecs = IOSNotificationDetails();
  await notificationPlugin.show(
      1,
      'COVID Trace Monitoring Alert',
      'Keep the app open to get accurate exposure monitoring.',
      NotificationDetails(androidSpec, iosSpecs),
      payload: 'Default_Sound');
}

/// Takes a list of beacons and attempts to match them with a recored location within
/// the provided duration window. This method sets the `location` property on each
/// `BeaconModel` when a match is found. Additionally it returns the set of locations
/// that matched against any of the provided beacons.
///
/// The default `window` Duration is 10 minutes.
Future<Map<int, LocationModel>> matchBeaconsAndLocations(
    Iterable<BeaconModel> beacons,
    {Duration window}) async {
  if (beacons.isEmpty) {
    return null;
  }

  window ??= Duration(minutes: 10);
  var sorted = List.from(beacons);
  sorted.sort((a, b) => a.start.compareTo(b.start));
  var start = sorted.first.start.subtract(window).toIso8601String();
  var end = sorted.last.end.add(window).toIso8601String();

  List<LocationModel> locations = await LocationModel.findAll(
      orderBy: 'id ASC',
      where:
          'DATETIME(timestamp) >= DATETIME(?) AND DATETIME(timestamp) <= DATETIME(?)',
      whereArgs: [start, end]);
  Map<int, LocationModel> locationMatches = {};

  /// For each Beacon do the following:
  /// - Find all the locations that fall within the duration window of the Beacon time range.
  /// - Associate the location closest to the midpoint of the Beacon time range to the Beacon.
  /// - Mark any matching locations as exposures.
  sorted.forEach((b) {
    var start = b.start.subtract(window);
    var end = b.end.add(window);
    var midpoint = b.start
        .add(Duration(milliseconds: end.difference(start).inMilliseconds ~/ 2));

    var matches = locations
        .where((l) => l.timestamp.isAfter(start) && l.timestamp.isBefore(end))
        .toList();

    matches.sort((a, b) {
      var aDiff = midpoint.difference(a.timestamp);
      var bDiff = midpoint.difference(b.timestamp);

      return aDiff.compareTo(bDiff);
    });

    if (matches.isNotEmpty) {
      b.location = matches.first;
      matches.forEach((l) => locationMatches[l.id] = l);
    }
  });

  return locationMatches;
}
