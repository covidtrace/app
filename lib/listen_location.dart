import 'dart:async';

import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ListenLocationWidget extends StatefulWidget {
  ListenLocationWidget({Key key}) : super(key: key);

  @override
  _ListenLocationState createState() => _ListenLocationState();
}

class _ListenLocationState extends State<ListenLocationWidget> {
  final Location location = new Location();

  LocationData _location;
  StreamSubscription<LocationData> _locationSubscription;
  String _error;

  Completer<GoogleMapController> _controller = Completer();
  CameraPosition _camera = CameraPosition(
      target: LatLng(37.42796133580664, -122.085749655962), zoom: 16.0);
  Set<Circle> _circles = {};

  _listenLocation() async {
    _locationSubscription = location.onLocationChanged().handleError((err) {
      setState(() {
        _error = err.code;
      });
      _locationSubscription.cancel();
    }).listen((LocationData currentLocation) async {
      setState(() {
        _error = null;
        _location = currentLocation;
        _camera = CameraPosition(
            target: LatLng(_location.latitude, _location.longitude),
            zoom: 16.0);
        _circles.add(new Circle(
            circleId: new CircleId('$_circles.length'),
            radius: 10,
            strokeColor: Colors.redAccent,
            strokeWidth: 0,
            fillColor: Color.fromARGB(150, 255, 0, 0),
            center: LatLng(_location.latitude, _location.longitude)));
      });

      // Center map on newest location
      GoogleMapController controller = await _controller.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(_camera));
    });
  }

  _stopListen() async {
    _locationSubscription.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Listen location: ' + (_error ?? '${_location ?? "unknown"}'),
          style: Theme.of(context).textTheme.body2,
        ),
        Row(
          children: [
            Container(
              margin: EdgeInsets.only(right: 42),
              child: RaisedButton(
                child: Text("Listen"),
                onPressed: _listenLocation,
              ),
            ),
            RaisedButton(
              child: Text("Stop"),
              onPressed: _stopListen,
            )
          ],
        ),
        Row(
          children: [
            SizedBox(
                width: MediaQuery.of(context).size.width,
                height: 300,
                child: GoogleMap(
                  mapType: MapType.normal,
                  initialCameraPosition: _camera,
                  circles: _circles,
                  onMapCreated: (GoogleMapController controller) {
                    _controller.complete(controller);
                  },
                ))
          ],
        )
      ],
    );
  }
}
