import 'dart:async';
import 'dart:math';

import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import 'storage/beacon.dart';

// COVID Trace Beacon UUID
const String UUID = '9F9D2C7D-5022-4052-A36B-B225DBC5E6D2';

List<Region> regions = [
  Region(identifier: 'com.covidtrace.app', proximityUUID: UUID)
];

final BeaconBroadcast beaconBroadcast = BeaconBroadcast();
StreamSubscription<RangingResult> _streamRanging;

Future<void> setupBeaconScanning() async {
  print('initScan');
  try {
    // TODO(wes): initializeAndCheckScanning will never return on iOS if already have permissions
    var success = await flutterBeacon.initializeScanning;
    print('initScan $success');
  } catch (err) {
    print(err);
  }

  // Start monitoring for entry/exit of a region
  flutterBeacon.monitoring(regions).listen((MonitoringResult result) {
    print('monitoring... $result');
    print(result.monitoringEventType);
    print(result.monitoringState);
    print(result.region);

    switch (result.monitoringState) {
      case MonitoringState.inside:
        showBeaconNotification(result.monitoringState);
        startRegionRange();
        break;
      case MonitoringState.outside:
        showBeaconNotification(result.monitoringState);
        stopRegionRange();
        break;
      case MonitoringState.unknown:
        showBeaconNotification(result.monitoringState);
        break;
    }
  });
}

void startRegionRange() {
  print('starting region range');
  _streamRanging =
      flutterBeacon.ranging(regions).listen((RangingResult result) {
    result.beacons.forEach((b) {
      // TODO(wes): Possible filter beacons based on proximity
      BeaconModel.seen(b.major, b.minor);
    });

    BeaconModel.endUnseen();
  });
}

Future<void> stopRegionRange() {
  print('stopping region range');
  BeaconModel.endUnseen();
  return _streamRanging.cancel();
}

void showBeaconNotification(MonitoringState state) async {
  var notificationPlugin = FlutterLocalNotificationsPlugin();
  var androidSpec = AndroidNotificationDetails(
      '1', 'COVID Trace', 'Beacon notification',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iosSpecs = IOSNotificationDetails();
  await notificationPlugin.show(1, 'COVID Trace Beacon Alert', '$state',
      NotificationDetails(androidSpec, iosSpecs));
}

class Beacon extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => BeaconState();
}

class BeaconState extends State {
  int _major = Random().nextInt(pow(2, 16));
  int _minor = Random().nextInt(pow(2, 16));
  bool _broadcasting = false;
  List<BeaconModel> _beacons = [];

  @override
  void initState() {
    super.initState();

    initBroadcast();
    BeaconModel.destroyAll();
  }

  void initBroadcast() async {
    beaconBroadcast.getAdvertisingStateChange().listen((isAdvertising) {
      if (mounted) {
        setState(() => _broadcasting = isAdvertising);
      }
    });

    beaconBroadcast
        .setUUID(UUID)
        .setMajorId(_major)
        .setMinorId(_minor)
        .setIdentifier('com.covidtrace.app')
        .setLayout('m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24') // iBeacon
        .setManufacturerId(0x004C); // Apple

    if (!await beaconBroadcast.isAdvertising()) {
      print('starting beacon broadcasting');
      beaconBroadcast.start();
    } else {
      setState(() => _broadcasting = true);
    }
  }

  void onBroadcastChange(bool value) {
    if (value) {
      beaconBroadcast.start();
    } else {
      beaconBroadcast.stop();
    }
  }

  Future<void> refreshBeacons() async {
    var beacons = await BeaconModel.findAll(orderBy: 'last_seen DESC');
    setState(() => _beacons = beacons);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Beacon'),
        centerTitle: true,
      ),
      body: Column(children: [
        Container(
            child: ListTile(
                title: Text('Broadcasting'),
                subtitle: Text('ID: $_major:$_minor'),
                trailing: Switch.adaptive(
                    value: _broadcasting, onChanged: onBroadcastChange))),
        Divider(),
        Flexible(
            child: RefreshIndicator(
                onRefresh: refreshBeacons,
                child: ListView.separated(
                  itemCount: _beacons.length,
                  separatorBuilder: (context, index) => Divider(),
                  itemBuilder: (context, index) {
                    var b = _beacons[index];
                    var time = b.duration;
                    var mins = time.inMinutes;
                    var secs = time.inSeconds % 60;

                    return ListTile(
                      title: Text(
                          '${DateFormat.jm().format(b.start).toLowerCase()}'),
                      subtitle: Text('${b.major}:${b.minor}'),
                      trailing: Text(mins > 0 ? '$mins m $secs s' : '$secs s'),
                    );
                  },
                ))),
      ]),
    );
  }
}
