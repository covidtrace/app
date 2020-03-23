import 'dart:async';
import 'dart:math';
import 'location_history.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'storage/location.dart';

class ListenLocationWidget extends StatefulWidget {
  ListenLocationWidget({Key key}) : super(key: key);

  @override
  _ListenLocationState createState() => _ListenLocationState();
}

class _ListenLocationState extends State<ListenLocationWidget> {
  Timer timer;
  int _numLocations = 0;
  int _numExposures = 0;
  LocationModel _recent;
  LocationModel _center = LocationModel(
      latitude: 37.42796133580664,
      longitude: -122.085749655962,
      speed: 0,
      timestamp: DateTime.now());
  List<LocationModel> _locations = [];
  Completer<GoogleMapController> _controller = Completer();

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    timer = new Timer.periodic(
        new Duration(seconds: 30), (timer) async => await pollLocations());
    pollLocations();
  }

  String formatDate(DateTime d) {
    return new DateFormat('Md').add_jm().format(d.toLocal());
  }

  Future<void> pollLocations() async {
    List<LocationModel> locations =
        await LocationModel.findAll(limit: 10, orderBy: 'timestamp DESC');
    Map<String, int> counts = await LocationModel.count();

    setState(() {
      _locations = locations;
      _numLocations = counts['count'];
      _numExposures = counts['exposures'];
      _recent = locations.length > 0 ? locations.last : _recent;
      _center = locations.length > 0
          ? locations.last
          : LocationModel(
              longitude: 0, latitude: 0, speed: 0, timestamp: DateTime.now());
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
      _numExposures = 0;
      _locations = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    CameraPosition _camera = CameraPosition(
        target: LatLng(_center.latitude, _center.longitude), zoom: 16.0);

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
                      snippet: '${l.cellID.toToken()}')));
        })
        .values
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
            height: 300,
            child: GoogleMap(
              mapType: MapType.normal,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              initialCameraPosition: _camera,
              markers: markers,
              minMaxZoomPreference: MinMaxZoomPreference(10, 18),
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
              },
            )),
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
                      Text('Exposures: $_numExposures',
                          style: Theme.of(context).textTheme.body2),
                      Text(
                          'Latest: ${_recent != null ? formatDate(_recent.timestamp) : ''}',
                          style: Theme.of(context).textTheme.body2),
                    ]),
                Container(
                  child: IconButton(
                    icon: Icon(Icons.refresh),
                    onPressed: pollLocations,
                  ),
                ),
                Container(
                  child: IconButton(
                    icon: Icon(Icons.delete_forever),
                    onPressed: _resetLocations,
                  ),
                ),
              ],
            )),
        Expanded(child: LocationHistory()),
      ],
    );
  }
}
