import 'app_model.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';

class ListenLocationWidget extends StatefulWidget {
  ListenLocationWidget({Key key}) : super(key: key);

  @override
  _ListenLocationState createState() => _ListenLocationState();
}

class _ListenLocationState extends State<ListenLocationWidget> {
  final Location location = new Location();

  _listenLocation() async {
    bool permission = await location.hasPermission();
    if (!permission) {
      permission = await location.requestPermission();

      if (!permission) {
        // Set state to show notice
        return;
      }
    }

    bool status = await location.registerBackgroundLocation(backgroundCallback);
    print('statusBackgroundLocation: $status');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: [
            Container(
              margin: EdgeInsets.only(right: 42),
              child: RaisedButton(
                child: Text("Listen"),
                onPressed: _listenLocation,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Consumer<AppModel>(builder: (context, locations, child) {
              Completer<GoogleMapController> _controller = Completer();
              CameraPosition _camera = CameraPosition(
                  target: LatLng(37.42796133580664, -122.085749655962),
                  zoom: 16.0);

              Set<Circle> circles = {};
              locations.items.forEach((l) {
                Circle c = new Circle(
                    circleId: new CircleId('$circles.length'),
                    radius: 10,
                    strokeColor: Colors.redAccent,
                    strokeWidth: 0,
                    fillColor: Color.fromARGB(150, 255, 0, 0),
                    center: LatLng(l.latitude, l.longitude));
                circles.add(c);
              });

              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Num of locations: ${locations.items.length}',
                        style: Theme.of(context).textTheme.body2),
                    SizedBox(
                        width: MediaQuery.of(context).size.width,
                        height: 300,
                        child: GoogleMap(
                          mapType: MapType.normal,
                          initialCameraPosition: _camera,
                          circles: circles,
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
