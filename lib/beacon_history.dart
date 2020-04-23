import 'dart:async';
import 'dart:math';

import 'package:covidtrace/helper/beacon.dart';
import 'package:covidtrace/helper/location.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';

import 'storage/beacon.dart';

class BeaconHistory extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => BeaconState();
}

class BeaconState extends State {
  String _filter = 'all';
  bool _broadcasting = false;
  int _transmissions = 0;
  List<BeaconModel> _beacons = [];
  List<BeaconModel> _display = [];
  BeaconModel _selected;
  Map<String, Map<int, List<BeaconModel>>> _beaconsIndex = Map();
  LatLng _currentLocation;
  Completer<GoogleMapController> _controller = Completer();
  List<Marker> _markers = [];
  Timer refreshTimer;

  @override
  void initState() {
    super.initState();
    refreshBeacons();
    currentLocation();
    setState(() => _broadcasting = isBroadcasting());

    refreshTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      refreshBeacons();
    });
  }

  @override
  void dispose() {
    super.dispose();
    refreshTimer.cancel();
  }

  Future<void> currentLocation() async {
    var loc = await locateCurrentPosition();
    setState(() => _currentLocation = loc);
  }

  Future<void> refreshBeacons() async {
    var beacons = await BeaconModel.findAll(orderBy: 'start DESC');
    var transmissions = await BeaconTransmission.findAll(
        where: 'end IS NULL', groupBy: 'clientId');

    if (!mounted) {
      return;
    }

    setState(() {
      _beacons = beacons;
      _transmissions = transmissions.length;
    });
    setFilter(_filter, resetSelected: false);
  }

  setFilter(String value, {bool resetSelected = true}) async {
    var beacons = value == 'exposed'
        ? _beacons.where((l) => l.exposure).toList()
        : _beacons;

    var beaconsIndex = await indexBeacons(beacons);
    setState(() {
      _beaconsIndex = beaconsIndex;
      _filter = value;
      _display = beacons;
    });

    var reset = _display.length > 0 ? _display.first : null;
    var selected = resetSelected
        ? reset
        : _display.firstWhere((b) => b.id == _selected?.id,
            orElse: () => reset);

    setBeacon(selected);
  }

  Future<Map<String, Map<int, List<BeaconModel>>>> indexBeacons(
      List<BeaconModel> beacons) async {
    // bucket beacons by day and hour
    Map<String, Map<int, List<BeaconModel>>> beaconsIndex = Map();
    beacons.forEach((l) {
      var timestamp = l.start.toLocal();
      var dayHour = DateFormat.EEEE().add_MMMd().format(timestamp);
      beaconsIndex[dayHour] ??= Map<int, List<BeaconModel>>();
      beaconsIndex[dayHour][timestamp.hour] ??= List<BeaconModel>();
      beaconsIndex[dayHour][timestamp.hour].add(l);
    });

    await matchBeaconsAndLocations(beacons);

    return beaconsIndex;
  }

  void setBeacon(BeaconModel item) async {
    if (item == null) {
      setState(() {
        _selected = null;
        _markers = [];
      });

      return;
    }

    setState(() {
      _selected = item;
    });

    if (item.location == null) {
      setState(() => _markers = []);
      return;
    }

    var loc = item.location.latLng;
    setState(() {
      _markers = [
        Marker(
            markerId: MarkerId(item.id.toString()),
            position: loc,
            onTap: () => launchMapsApp(loc))
      ];
    });

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLng(loc));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Beacon History'),
      ),
      body: Column(children: [
        Container(
            color: Colors.blueGrey,
            child: ListTileTheme(
                textColor: Colors.white,
                iconColor: Colors.white,
                child: ListTile(
                    title: Text('Broadcasting'),
                    subtitle: _broadcasting
                        ? Text({
                              0: 'no devices nearby',
                              1: '1 device nearby'
                            }[_transmissions] ??
                            '$_transmissions devices nearby')
                        : Text('is turned off'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_broadcasting
                          ? Icons.bluetooth_searching
                          : Icons.bluetooth_disabled),
                    ])))),
        Divider(height: 0),
        Flexible(
            flex: 2,
            child: Stack(children: [
              if (_selected != null || _currentLocation != null)
                GoogleMap(
                  mapType: MapType.normal,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  initialCameraPosition: CameraPosition(
                      target: _selected?.location?.latLng ?? _currentLocation,
                      zoom: 16),
                  markers: _markers.toSet(),
                  onMapCreated: (GoogleMapController controller) {
                    _controller.complete(controller);
                  },
                ),
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 15.0,
                  child: Center(
                      child: CupertinoSlidingSegmentedControl(
                          backgroundColor: Color(0xCCCCCCCC),
                          padding: EdgeInsets.all(5),
                          groupValue: _filter,
                          children: {
                            'all': Text('All Locations'),
                            'exposed': Text('Potential Exposures'),
                          },
                          onValueChanged: setFilter)))
            ])),
        Flexible(
            flex: 3,
            child: RefreshIndicator(
              onRefresh: refreshBeacons,
              child: CustomScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  slivers: _beaconsIndex.entries
                      .map((MapEntry<String, Map<int, List<BeaconModel>>>
                          entry) {
                        List<BeaconModel> beacons = [];
                        entry.value.values
                            .forEach((list) => beacons.addAll(list));

                        return MapEntry(
                            entry.key,
                            SliverStickyHeader(
                                header: Container(
                                  decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.8),
                                      border: Border(
                                          bottom: BorderSide(
                                              color: Colors.grey.shade200,
                                              width: 1))),
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 15, vertical: 10),
                                  alignment: Alignment.center,
                                  child: Text(
                                    entry.key,
                                    style: Theme.of(context).textTheme.subtitle,
                                  ),
                                ),
                                sliver: SliverList(
                                  delegate:
                                      SliverChildBuilderDelegate((context, i) {
                                    var item = beacons[i];
                                    var timestamp = item.start.toLocal();
                                    var hour = timestamp.hour;
                                    var dayHour = DateFormat.EEEE()
                                        .add_MMMd()
                                        .format(timestamp);
                                    var hourMap = _beaconsIndex[dayHour];
                                    var selected = _selected?.id == item.id;

                                    var duration = item.duration;
                                    var mins = duration.inMinutes;

                                    return Column(children: [
                                      InkWell(
                                          onTap: () => setBeacon(item),
                                          child: Container(
                                            padding: EdgeInsets.all(15),
                                            color: selected
                                                ? Colors.grey[200]
                                                : Colors.transparent,
                                            child: Row(children: [
                                              Container(
                                                width: 70,
                                                child: Text(
                                                  DateFormat.jm()
                                                      .format(timestamp)
                                                      .toLowerCase(),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .subhead,
                                                  textAlign: TextAlign.right,
                                                ),
                                              ),
                                              Expanded(child: Container()),
                                              Container(
                                                  width: 160,
                                                  child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceEvenly,
                                                      children: List.generate(
                                                        24,
                                                        (i) {
                                                          return Flexible(
                                                              flex: 1,
                                                              child: Row(
                                                                  children: [
                                                                    Expanded(
                                                                        child:
                                                                            Container(
                                                                      decoration: BoxDecoration(
                                                                          borderRadius: BorderRadius.vertical(
                                                                              top: Radius.circular(
                                                                                  5),
                                                                              bottom: Radius.circular(
                                                                                  5)),
                                                                          color: i == hour
                                                                              ? item.exposure ? Colors.red : Colors.grey[600]
                                                                              : Colors.grey[selected ? 400 : 300]),
                                                                      height: hourMap != null &&
                                                                              hourMap.containsKey(i)
                                                                          ? 18
                                                                          : 5,
                                                                    )),
                                                                    SizedBox(
                                                                        width:
                                                                            3)
                                                                  ]));
                                                        },
                                                      ))),
                                              Expanded(child: Container()),
                                              Container(
                                                width: 40,
                                                child: Text(
                                                  mins <= 10
                                                      ? '${max(1, mins)}m'
                                                      : mins < 60
                                                          ? '${mins}m'
                                                          : '+1hr',
                                                  textAlign: TextAlign.right,
                                                ),
                                              ),
                                              SizedBox(width: 20),
                                              Icon(
                                                  item.exposure
                                                      ? Icons.warning
                                                      : null,
                                                  color: item.exposure
                                                      ? Colors.orange
                                                      : Colors.grey)
                                            ]),
                                          )),
                                      Divider(height: 0),
                                    ]);
                                  }, childCount: beacons.length),
                                )));
                      })
                      .toList()
                      .map((e) => e.value)
                      .toList()),
            ))
      ]),
    );
  }
}
