import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'storage.dart';
import 'app_model.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

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

  bool _loading = false;

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
            stopOnTerminate: false,
            startOnBoot: true,
            logLevel: bg.Config.LOG_LEVEL_OFF))
        .then((bg.State state) {
      if (!state.enabled) {
        bg.BackgroundGeolocation.start();
      }
    });
  }

  String formatDate(String isoStr) {
    return new DateFormat('Md')
        .add_jm()
        .format(DateTime.parse(isoStr).toLocal());
  }

  Future<void> pollLocations() async {
    List<LocationModel> locations = await LocationModel.findAll();
    int count = await LocationModel.count();

    setState(() {
      _locations = locations;
      _numLocations = count;
      _recent = locations.length > 0 ? locations.last : _recent;
      _center = locations.length > 0
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
        30);

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

  _sendReport() async {
    setState(() {
      _loading = true;
    });

    try {
      List<LocationModel> locations = await LocationModel.findAll();
      await http.post('http://localhost:8080/report',
          headers: <String, String>{
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonEncode(locations.map((l) => l.toMap()).toList()));
    } catch (err) {
      print(err);
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: [
            Consumer<AppModel>(builder: (context, locations, child) {
              CameraPosition _camera = CameraPosition(
                  target: LatLng(_center.latitude, _center.longitude),
                  zoom: 16.0);

              Set<Marker> markers = _locations
                  .asMap()
                  .map((i, l) {
                    double age = (i + 1) / _locations.length * .6;
                    return MapEntry(
                        i,
                        new Marker(
                            markerId: new MarkerId('$i'),
                            alpha: (1 - age),
                            position: LatLng(l.latitude, l.longitude),
                            infoWindow: InfoWindow(
                                title: formatDate(l.timestamp),
                                snippet: '${l.cellID}')));
                  })
                  .values
                  .toSet();

              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
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
        ),
        Padding(
            padding: EdgeInsets.all(10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Locations: $_numLocations',
                          style: Theme.of(context).textTheme.body2),
                      Text(
                          'Latest: ${_recent != null ? formatDate(_recent.timestamp) : ''}',
                          style: Theme.of(context).textTheme.body2),
                    ]),
                Container(
                  child: RaisedButton(
                    child: Icon(Icons.refresh),
                    onPressed: pollLocations,
                  ),
                ),
                Container(
                  child: RaisedButton(
                    child: Icon(Icons.delete_forever),
                    onPressed: _resetLocations,
                  ),
                ),
              ],
            )),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          Column(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(10.0),
                child: CupertinoButton.filled(
                  child: _loading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: null,
                              valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : Text("Report Symptoms"),
                  onPressed: _sendReport,
                ),
              ),
              CupertinoButton.filled(
                child: Text("Show Test Code"),
                onPressed: pollLocations,
              ),
            ],
          ),
        ])
      ],
    );
  }
}
