import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Dashboard extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => DashboardState();
}

class DashboardState extends State {
  Completer<GoogleMapController> _mapController = Completer();

  @override
  Widget build(BuildContext context) {
    var loc = LatLng(47.6513435, -122.3511888);
    return Column(children: [
      Padding(
          padding: EdgeInsets.only(top: 15, left: 15, right: 15),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Incidents', style: Theme.of(context).textTheme.headline),
            SizedBox(height: 5),
            Text(
                'Your location history for the last 5 days has been compared against self reported infections.',
                style: Theme.of(context).textTheme.body1)
          ])),
      Card(
          elevation: 4,
          margin: EdgeInsets.all(15),
          child: Column(children: [
            SizedBox(
                height: 150,
                child: GoogleMap(
                  mapType: MapType.normal,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  initialCameraPosition: CameraPosition(target: loc, zoom: 18),
                  minMaxZoomPreference: MinMaxZoomPreference(10, 18),
                  markers:
                      [Marker(markerId: MarkerId('1'), position: loc)].toSet(),
                  onMapCreated: (controller) {
                    if (!_mapController.isCompleted) {
                      _mapController.complete(controller);
                    }
                  },
                )),
            ListTile(
              isThreeLine: true,
              leading: Icon(Icons.warning, color: Colors.amber, size: 40),
              title: Text('Possible Exposure'),
              subtitle: Text(
                  '3/22 3pm - 4pm. Your location overlap with someone who reported as having COVID-19.'),
            )
          ]))
    ]);
  }
}
