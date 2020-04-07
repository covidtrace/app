import 'dart:async';

import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import 'storage/beacon.dart';
import 'storage/beacon_broadcast.dart';

// COVID Trace Beacon UUID
const String UUID = '9F9D2C7D-5022-4052-A36B-B225DBC5E6D2';
List<Region> regions = [
  Region(identifier: 'com.covidtrace.app', proximityUUID: UUID)
];

final BeaconBroadcast beaconBroadcast = BeaconBroadcast();
StreamSubscription<RangingResult> _streamRanging;

Future<void> setupBeaconScanning() async {
  try {
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
        showBeaconNotification();
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

void showBeaconNotification() async {
  var notificationPlugin = FlutterLocalNotificationsPlugin();
  var androidSpec = AndroidNotificationDetails(
      '1', 'COVID Trace', 'Beacon notification',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iosSpecs = IOSNotificationDetails();
  await notificationPlugin.show(
      1,
      'COVID Trace Monitoring Alert',
      'Keep the app open to get accurate monitoring while indoors.',
      NotificationDetails(androidSpec, iosSpecs),
      payload: 'Default_Sound');
}

class Beacon extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => BeaconState();
}

class BeaconState extends State {
  BeaconBroadcastModel _broadcast;
  bool _broadcasting = false;
  List<BeaconModel> _beacons = [];
  Timer timer;

  @override
  void initState() {
    super.initState();

    initBroadcast();
    refreshBeacons();

    timer = Timer.periodic(Duration(seconds: 1), (timer) {
      refreshBeacons();
    });
  }

  @override
  void dispose() {
    super.dispose();
    timer.cancel();
  }

  void initBroadcast() async {
    beaconBroadcast.getAdvertisingStateChange().listen((isAdvertising) {
      if (mounted) {
        setState(() => _broadcasting = isAdvertising);
      }
    });

    beaconBroadcast
        .setUUID(UUID)
        .setIdentifier('com.covidtrace.app')
        .setLayout('m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24') // iBeacon
        .setManufacturerId(0x004C); // Apple

    if (!await beaconBroadcast.isAdvertising()) {
      print('starting beacon broadcasting');
      onBroadcastChange(true);
    } else {
      setState(() => _broadcasting = true);
    }
  }

  void onBroadcastChange(bool value) async {
    if (value) {
      var broadcast = await BeaconBroadcastModel.get();
      beaconBroadcast
          .setMajorId(broadcast.major)
          .setMinorId(broadcast.minor)
          .start();
      setState(() => _broadcast = broadcast);
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
        title: Text('Beacons'),
        centerTitle: true,
      ),
      body: Column(children: [
        Container(
            child: ListTile(
                title: Text('Broadcasting'),
                subtitle: _broadcast != null
                    ? Text('ID: ${_broadcast.major}:${_broadcast.minor}')
                    : null,
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
                      trailing:
                          Text(mins > 0 ? '${mins}m ${secs}s' : '${secs}s'),
                    );
                  },
                ))),
      ]),
    );
  }
}
