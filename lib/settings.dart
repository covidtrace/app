import 'dart:async';
import 'package:covidtrace/storage/user.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'helper/location.dart';
import 'storage/location.dart';

class SettingsView extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => SettingsViewState();
}

class SettingsViewState extends State {
  double _radius = 0;
  LatLng _home;
  UserModel _user;
  Completer<GoogleMapController> _mapController = Completer();

  initState() {
    super.initState();
    loadUser();
  }

  Future<void> loadUser() async {
    _user = await UserModel.find();
    setState(() {
      _radius = _user.homeRadius;
      _home = _user.home;
    });
  }

  void setHomePosition(LatLng position) async {
    setState(() => _home = position);
    var mapController = await _mapController.future;
    mapController.animateCamera(CameraUpdate.newLatLng(position));
  }

  Future<bool> setHome() async {
    try {
      var position = await locateCurrentPosition();
      await UserModel.setHome(position.latitude, position.longitude,
          radius: _radius);
      setHomePosition(position);
      await LocationModel.deleteInArea(position, _radius);
      return true;
    } catch (err) {
      return false;
    }
  }

  void setRadius(double size) {
    setState(() {
      _radius = size;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Circle> circles = [];

    if (_home != null) {
      circles = [
        Circle(
            circleId: CircleId('home'),
            center: _home,
            radius: _radius,
            fillColor: Colors.red.withOpacity(.2),
            strokeColor: Colors.red,
            strokeWidth: 2)
      ];
    }

    return Scaffold(
        appBar: AppBar(title: Text('Set My Home')),
        body: Builder(
            builder: (context) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                      height: 250,
                      child: circles
                              .isNotEmpty // TODO(wes): Need to load current position if no home is defined
                          ? GoogleMap(
                              mapType: MapType.normal,
                              myLocationEnabled: true,
                              myLocationButtonEnabled: true,
                              circles: circles.toSet(),
                              initialCameraPosition:
                                  CameraPosition(target: _home, zoom: 17),
                              minMaxZoomPreference:
                                  MinMaxZoomPreference(10, 20),
                              onMapCreated: (controller) {
                                if (!_mapController.isCompleted) {
                                  _mapController.complete(controller);
                                }
                              },
                            )
                          : Container()),
                  SizedBox(height: 10),
                  Slider.adaptive(
                      min: 0, max: 300, value: _radius, onChanged: setRadius),
                  Padding(
                      padding: EdgeInsets.only(top: 10, left: 20, right: 20),
                      child: Text(
                          'Update your home to your current location below. COVID Trace will never record any activity around your home.',
                          style: Theme.of(context).textTheme.subhead)),
                  SizedBox(height: 10),
                  ButtonBar(
                      alignment: MainAxisAlignment.center,
                      buttonPadding:
                          EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      children: [
                        RaisedButton(
                            color: Theme.of(context)
                                .buttonTheme
                                .colorScheme
                                .primary,
                            onPressed: () async {
                              if (await setHome()) {
                                Scaffold.of(context).showSnackBar(SnackBar(
                                    content: Text(
                                        'Your home location was updated successfully')));
                              } else {
                                Scaffold.of(context).showSnackBar(SnackBar(
                                    backgroundColor: Colors.red,
                                    content: Text(
                                        'There was an error updating your home location ')));
                              }
                            },
                            child: Text('Set as My Home'))
                      ]),
                ])));
  }
}
