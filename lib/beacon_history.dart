import 'dart:async';

import 'package:covidtrace/helper/beacon.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'storage/beacon.dart';

class BeaconHistory extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => BeaconState();
}

class BeaconState extends State {
  BeaconUuid _beacon;
  bool _broadcasting = false;
  List<BeaconTransmission> _transmissions = [];
  List<BeaconModel> _beacons = [];
  Timer refreshTimer;
  Timer sequenceTimer;

  String _filter = 'in_progress';

  @override
  void initState() {
    super.initState();

    refreshBeacons();
    refreshTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      refreshBeacons();
    });

    setState(() => _broadcasting = isBroadcasting());
  }

  @override
  void dispose() {
    super.dispose();
    refreshTimer.cancel();
  }

  Future<void> refreshBeacons() async {
    var transmissions = await BeaconTransmission.findAll(orderBy: 'start DESC');
    var beacons = await BeaconModel.findAll(orderBy: 'start DESC');
    var beacon = getBeaconUuid();

    if (!mounted) {
      return;
    }

    setState(() {
      _beacon = beacon;
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

  void onBroadcastChange(bool value) async {
    if (value) {
      await startAdvertising();
    } else {
      stopAdvertising();
    }
    setState(() => _broadcasting = isBroadcasting());
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
                    subtitle: _broadcasting && _beacon != null
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
