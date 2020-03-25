import 'dart:async';
import 'package:covidtrace/storage/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SettingsView extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => SettingsViewState();
}

class SettingsViewState extends State {
  Future<UserModel> _user;
  Completer<GoogleMapController> _mapController = Completer();
  List<Circle> _circles = [];

  initState() {
    super.initState();
    _user = UserModel.find();
  }

  void setHomePosition(LatLng position) async {
    var circle = Circle(
        circleId: CircleId('home'),
        center: position,
        radius: 30,
        fillColor: Colors.red.withOpacity(.2),
        strokeColor: Colors.red,
        strokeWidth: 2);

    setState(() => _circles = [circle]);
    var mapController = await _mapController.future;
    mapController.animateCamera(CameraUpdate.newLatLng(position));
  }

  Future<LatLng> locateCurrentPosition() async {
    // Get current positon to show on map for marking home
    var current = await bg.BackgroundGeolocation.getCurrentPosition(
        timeout: 15, maximumAge: 10000);
    var latlng = LatLng(current.coords.latitude, current.coords.longitude);

    return latlng;
  }

  Future<bool> setHome() async {
    var position = await locateCurrentPosition();
    var user = await UserModel.find();

    user.latitude = position.latitude;
    user.longitude = position.longitude;
    try {
      await user.save();
      setHomePosition(position);
      return true;
    } catch (err) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('Set My Home')),
      body: Builder(
          builder: (context) =>
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    height: 250,
                    child: FutureBuilder(
                        future: _user,
                        builder: (context, AsyncSnapshot<UserModel> snapshot) {
                          if (!snapshot.hasData) {
                            return Container();
                          }

                          var user = snapshot.data;
                          var loc = user.latitude != null
                              ? LatLng(user.latitude, user.longitude)
                              : LatLng(39.5, -98.35);

                          if (user.latitude != null && _circles.length == 0) {
                            setHomePosition(loc);
                          }

                          return GoogleMap(
                            mapType: MapType.normal,
                            myLocationEnabled: true,
                            myLocationButtonEnabled: true,
                            circles: _circles.toSet(),
                            initialCameraPosition:
                                CameraPosition(target: loc, zoom: 18),
                            minMaxZoomPreference: MinMaxZoomPreference(10, 18),
                            onMapCreated: (controller) {
                              if (!_mapController.isCompleted) {
                                _mapController.complete(controller);
                              }
                            },
                          );
                        })),
                Padding(
                    padding: EdgeInsets.only(top: 20, left: 20, right: 20),
                    child: Text(
                        'Update your home to your current location below. CovidTrace will never record any activity around your home.',
                        style: Theme.of(context).textTheme.subhead)),
                ButtonBar(
                    alignment: MainAxisAlignment.center,
                    buttonPadding:
                        EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    children: [
                      RaisedButton(
                          color:
                              Theme.of(context).buttonTheme.colorScheme.primary,
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
