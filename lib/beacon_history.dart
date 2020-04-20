import 'dart:async';

import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:flutter/cupertino.dart';
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

class BeaconHistory extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => BeaconState();
}

class BeaconState extends State {
  BeaconUuid _beacon;
  bool _broadcasting = false;
  bool _advertising = false;
  List<BeaconTransmission> _transmissions = [];
  List<BeaconModel> _beacons = [];
  Timer refreshTimer;
  Timer sequenceTimer;

  String _filter = 'in_progress';

  @override
  void initState() {
    super.initState();

    initBroadcast();
    refreshBeacons();

    refreshTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      refreshBeacons();
    });
  }

  @override
  void dispose() {
    super.dispose();
    refreshTimer.cancel();
    stopAdvertising();
  }

  void initBroadcast() {
    beaconBroadcast.getAdvertisingStateChange().listen((isAdvertising) {
      if (mounted) {
        setState(() => _advertising = isAdvertising);
      }
    });

    beaconBroadcast
        .setUUID(UUID)
        .setIdentifier('com.covidtrace.app')
        .setLayout('m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24') // iBeacon
        .setManufacturerId(0x004C); // Apple
  }

  void onBroadcastChange(bool value) async {
    setState(() => _broadcasting = value);
    if (value) {
      await startAdvertising();
    } else {
      stopAdvertising();
    }
  }

  Future<void> startAdvertising() async {
    var beacon = await BeaconUuid.get();
    setState(() => _beacon = beacon);

    sequenceTimer?.cancel();
    sequenceTimer = Timer.periodic(Duration(seconds: 4), (timer) async {
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
    sequenceTimer?.cancel();
    beaconBroadcast.stop();
  }

  Future<void> refreshBeacons() async {
    var transmissions = await BeaconTransmission.findAll(orderBy: 'start DESC');
    var beacons = await BeaconModel.findAll(orderBy: 'start DESC');

    if (!mounted) {
      return;
    }

    setState(() {
      _beacons = beacons;
      _transmissions = transmissions;
    });
  }

  void setFilter(value) {
    setState(() => _filter = value);
  }

  Future<void> removeTransmissions(int clientId, DateTime lastSeen) async {
    setState(() => _transmissions
        .removeWhere((t) => t.clientId == clientId && t.lastSeen == lastSeen));

    await BeaconTransmission.destroy(
        where: 'clientId = ? AND last_seen = ? AND end IS NOT NULL',
        whereArgs: [clientId, lastSeen.toIso8601String()]);
  }

  @override
  Widget build(BuildContext context) {
    Map<String, List<BeaconTransmission>> clientMap = Map();
    _transmissions.forEach((b) {
      clientMap['${b.clientId}-${b.lastSeen}'] ??= [];
      clientMap['${b.clientId}-${b.lastSeen}'].add(b);
    });
    var clients = clientMap.values.toList();

    var inProgress = (context, index) {
      var transmissions = clients[index];
      transmissions.sort((a, b) => a.duration.compareTo(b.duration));

      var b = transmissions.last;
      var time = b.duration;
      var mins = time.inMinutes;
      var secs = time.inSeconds % 60;
      var allowDismiss = transmissions.length < 8 && b.end != null;

      var content = ListTile(
        leading: Padding(
            padding: EdgeInsets.only(top: 10, left: 5),
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 3, value: transmissions.length / 8))),
        title: Text('${DateFormat.jm().format(b.start).toLowerCase()}'),
        subtitle: Text('${b.clientId}.${b.offset}.${b.token}'),
        trailing: Text(mins > 0 ? '${mins}m ${secs}s' : '${secs}s'),
      );

      return !allowDismiss
          ? content
          : Dismissible(
              key: Key(b.clientId.toString()),
              background: Container(
                  color: Theme.of(context).primaryColor,
                  alignment: Alignment.centerRight,
                  padding: EdgeInsets.only(right: 15),
                  child: Icon(
                    Icons.delete,
                    color: Colors.white,
                  )),
              direction: DismissDirection.endToStart,
              onDismissed: (direction) async {
                await removeTransmissions(b.clientId, b.lastSeen);
              },
              child: content);
    };

    var completed = (context, index) {
      var b = _beacons[index];
      var time = b.duration;
      var mins = time.inMinutes;
      var secs = time.inSeconds % 60;

      return ListTile(
        isThreeLine: true,
        leading: Icon(Icons.check_circle,
            size: 30, color: Theme.of(context).primaryColor),
        title: Text('${DateFormat.jm().format(b.start).toLowerCase()}'),
        subtitle: Text(b.uuid ?? ''),
        trailing: Text(mins > 0 ? '${mins}m ${secs}s' : '${secs}s'),
      );
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('Beacons'),
        centerTitle: true,
      ),
      body: Column(children: [
        Container(
            color: Colors.blueGrey,
            child: ListTileTheme(
                textColor: Colors.white,
                iconColor: Colors.white,
                child: ListTile(
                    title: Text('Broadcasting'),
                    subtitle: _beacon != null && _broadcasting
                        ? Text(
                            '${_beacon.clientId}.${_beacon.offset}.${_beacon.major}')
                        : Text('is turned off'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Switch(
                          value: _broadcasting, onChanged: onBroadcastChange),
                      Icon(_broadcasting
                          ? Icons.bluetooth_searching
                          : Icons.bluetooth_disabled),
                    ])))),
        Padding(
            padding: EdgeInsets.all(15),
            child: CupertinoSlidingSegmentedControl(
              backgroundColor: Color(0xCCCCCCCC),
              padding: EdgeInsets.all(5),
              groupValue: _filter,
              children: {
                'in_progress': Text('In Progress'),
                'completed': Text('Completed'),
              },
              onValueChanged: setFilter,
            )),
        Divider(height: 0),
        Flexible(
            child: RefreshIndicator(
                onRefresh: refreshBeacons,
                child: ListView.separated(
                  itemCount: _filter == 'in_progress'
                      ? clients.length
                      : _beacons.length,
                  separatorBuilder: (context, index) => Divider(),
                  itemBuilder:
                      _filter == 'in_progress' ? inProgress : completed,
                ))),
      ]),
    );
  }
}
