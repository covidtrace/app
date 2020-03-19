import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'storage.dart';
import 'app_model.dart';
import 'dart:math';

class ListenLocationWidget extends StatefulWidget {
  ListenLocationWidget({Key key}) : super(key: key);

  @override
  _ListenLocationState createState() => _ListenLocationState();
}

class _ListenLocationState extends State<ListenLocationWidget> {
  Timer timer;
  int _numLocations = 0;
  LocationModel _recent;
  LocationModel _center = LocationModel(
      latitude: 37.42796133580664,
      longitude: -122.085749655962,
      speed: 0,
      timestamp: DateTime.now().toIso8601String());
  List<LocationModel> _locations = [];
  Completer<GoogleMapController> _controller = Completer();

  @override
  void initState() {
    super.initState();

    timer = new Timer.periodic(
        new Duration(seconds: 15), (timer) async => await pollLocations());
    pollLocations();

    bg.BackgroundGeolocation.onLocation((bg.Location l) {
      print('[location] - $l');
      LocationModel model = LocationModel(
          longitude: l.coords.longitude,
          latitude: l.coords.latitude,
          speed: l.coords.speed,
          timestamp: l.timestamp);
      setState(() {
        _recent = model;
      });
      LocationModel.insert(model);
    }, (bg.LocationError error) {
      print('[location_error] - $error');
    });

    bg.BackgroundGeolocation.onProviderChange((bg.ProviderChangeEvent event) {
      print('[providerchange] - $event');
    });

    bg.BackgroundGeolocation.ready(bg.Config(
            desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
            distanceFilter: 1.0,
            stopOnTerminate: false,
            startOnBoot: true,
            logLevel: bg.Config.LOG_LEVEL_OFF))
        .then((bg.State state) {
      if (!state.enabled) {
        bg.BackgroundGeolocation.start();
      }
    });
  }

  Future<void> pollLocations() async {
    print('pollLocations');
    List<LocationModel> locations = await LocationModel.findAll();
    int count = await LocationModel.count();

    setState(() {
      _locations = locations;
      _numLocations = count;
      _center = _numLocations > 0
          ? locations.last
          : LocationModel(
              longitude: 0,
              latitude: 0,
              speed: 0,
              timestamp: DateTime.now().toIso8601String());
    });

    if (locations.length == 0) {
      return;
    }

    // Compute location bounds
    double minLat = locations.map((l) => l.latitude).reduce(min);
    double minLon = locations.map((l) => l.longitude).reduce(min);
    double maxLat = locations.map((l) => l.latitude).reduce(max);
    double maxLon = locations.map((l) => l.longitude).reduce(max);

    CameraUpdate update = CameraUpdate.newLatLngBounds(
        LatLngBounds(
            northeast: LatLng(maxLat, maxLon),
            southwest: LatLng(minLat, minLon)),
        20);

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(update);
  }

  _resetLocations() {
    LocationModel.destroyAll();
    setState(() {
      _recent = null;
      _numLocations = 0;
      _locations = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: [
            Container(
              margin: EdgeInsets.all(21),
              child: RaisedButton(
                child: Text("Reset"),
                onPressed: _resetLocations,
              ),
            ),
            Container(
              margin: EdgeInsets.all(21),
              child: RaisedButton(
                child: Text("Refresh"),
                onPressed: pollLocations,
              ),
            )
          ],
        ),
        Row(
          children: [
            Consumer<AppModel>(builder: (context, locations, child) {
              CameraPosition _camera = CameraPosition(
                  target: LatLng(_center.latitude, _center.longitude),
                  zoom: 16.0);

              Set<Marker> markers = {};
              _locations.forEach((l) {
                Marker m = new Marker(
                    markerId: new MarkerId('$markers.length'),
                    position: LatLng(l.latitude, l.longitude),
                    infoWindow: InfoWindow(title: '${l.timestamp.toString()}'));
                markers.add(m);
              });

              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Num of locations: $_numLocations',
                        style: Theme.of(context).textTheme.body2),
                    Text(
                        'Most recent: ${_recent != null ? DateTime.parse(_recent.timestamp).toLocal().toString() : ''}',
                        style: Theme.of(context).textTheme.body2),
                    SizedBox(
                        width: MediaQuery.of(context).size.width,
                        height: 300,
                        child: GoogleMap(
                          mapType: MapType.normal,
                          initialCameraPosition: _camera,
                          markers: markers,
                          minMaxZoomPreference: MinMaxZoomPreference(10, 18),
                          onMapCreated: (GoogleMapController controller) {
                            _controller.complete(controller);
                          },
                        ))
                  ]);
            })
          ],
        )
      ],
    );
  }
}
