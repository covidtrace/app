import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'storage/location.dart';

class DebugLocations extends StatefulWidget {
  @override
  DebugLocationsState createState() => DebugLocationsState();
}

class DebugLocationsState extends State {
  List<LocationModel> _locations = [];
  int _selected;
  Completer<GoogleMapController> _controller = Completer();
  List<Marker> _markers = [];
  var _camera = CameraPosition(target: LatLng(0, 0), zoom: 16);

  @override
  void initState() {
    super.initState();
    loadLocations();
  }

  Future<void> loadLocations() async {
    var locations = await LocationModel.findAll(orderBy: 'timestamp DESC');
    setState(() => _locations = locations);
    setLocation(0);
  }

  setLocation(int index) async {
    var item = _locations[index];
    var loc = LatLng(item.latitude, item.longitude);

    setState(() {
      _selected = index;
      _markers = [
        Marker(markerId: MarkerId(item.id.toString()), position: loc)
      ];
    });

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLng(loc));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Debug locations'),
          actions: [
            Padding(
                padding: EdgeInsets.only(right: 10),
                child: Chip(
                  label: Text(_locations.length.toString(),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary)),
                  backgroundColor: Colors.white,
                  elevation: 0,
                ))
          ],
        ),
        body: Column(children: [
          Flexible(
              flex: 2,
              child: GoogleMap(
                mapType: MapType.normal,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                initialCameraPosition: _camera,
                markers: _markers.toSet(),
                onMapCreated: (GoogleMapController controller) {
                  _controller.complete(controller);
                },
              )),
          Flexible(
              flex: 4,
              child: RefreshIndicator(
                  onRefresh: loadLocations,
                  child: ListView.builder(
                    itemCount: _locations.length,
                    itemBuilder: (context, i) {
                      var item = _locations[i];
                      var timestamp = item.timestamp.toLocal();
                      return Column(children: [
                        ListTile(
                          selected: i == _selected,
                          onTap: () => setLocation(i),
                          title: Text(DateFormat.Md().format(timestamp)),
                          subtitle: Text(DateFormat.jms().format(timestamp)),
                          trailing: Text('${item.cellID}'),
                        ),
                        Divider(height: 0)
                      ]);
                    },
                  )))
        ]));
  }
}
