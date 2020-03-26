import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'storage/location.dart';

final Map<String, Icon> activities = {
  'unknown': Icon(Icons.not_listed_location),
  'still': Icon(Icons.location_on),
  'on_foot': Icon(Icons.directions_walk),
  'walking': Icon(Icons.directions_walk),
  'running': Icon(Icons.directions_run),
  'on_bicycle': Icon(Icons.directions_bike),
  'in_vehicle': Icon(Icons.directions_car),
};

class LocationHistory extends StatefulWidget {
  @override
  LocationHistoryState createState() => LocationHistoryState();
}

class LocationHistoryState extends State {
  String _filter = 'all';
  List<LocationModel> _locations = [];
  List<LocationModel> _display = [];
  LocationModel _selected;
  Completer<GoogleMapController> _controller = Completer();
  ScrollController _scroller = ScrollController();
  List<Marker> _markers = [];
  var _camera = CameraPosition(target: LatLng(0, 0), zoom: 16);

  @override
  void initState() {
    super.initState();
    loadLocations();
  }

  Future<void> loadLocations() async {
    var locations = await LocationModel.findAll(
        where: 'sample = 0', orderBy: 'timestamp DESC');
    setState(() => _locations = locations);
    setFilter(_filter);
  }

  setFilter(String value) {
    var locations = value == 'exposed'
        ? _locations.where((l) => l.exposure).toList()
        : _locations;

    setState(() {
      _filter = value;
      _display = locations;
    });

    setLocation(_display.length > 0 ? _display.first : null);
    _scroller.animateTo(0.0,
        duration: Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  setLocation(LocationModel item, {bool open = false}) async {
    if (item == null) {
      setState(() {
        _selected = null;
        _markers = [];
      });

      return;
    }

    var loc = LatLng(item.latitude, item.longitude);
    setState(() {
      _selected = item;
      _markers = [
        Marker(markerId: MarkerId(item.id.toString()), position: loc)
      ];
    });

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLng(loc));

    if (open && Theme.of(context).platform == TargetPlatform.iOS) {
      launch('https://maps.apple.com?q=${loc.latitude},${loc.longitude}',
          forceSafariVC: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var locations = _filter == 'exposed'
        ? _locations.where((l) => l.exposure).toList()
        : _locations;

    return Scaffold(
        appBar: AppBar(title: Text('Location History')),
        body: Column(children: [
          Flexible(
              flex: 2,
              child: GoogleMap(
                mapType: MapType.normal,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                initialCameraPosition: _camera,
                markers: _markers.toSet(),
                onMapCreated: (GoogleMapController controller) {
                  _controller.complete(controller);
                },
              )),
          Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: CupertinoSlidingSegmentedControl(
                  padding: EdgeInsets.all(5),
                  groupValue: _filter,
                  children: {
                    'all': Text('All Locations'),
                    'exposed': Text('Potential Exposures'),
                  },
                  onValueChanged: setFilter)),
          Flexible(
              flex: 4,
              child: RefreshIndicator(
                  onRefresh: loadLocations,
                  child: ListView.builder(
                    controller: _scroller,
                    itemCount: locations.length,
                    itemBuilder: (context, i) {
                      var item = locations[i];
                      var timestamp = item.timestamp.toLocal();
                      var selected = _selected.id == item.id;

                      return Column(children: [
                        ListTileTheme(
                            selectedColor: Colors.black,
                            child: Container(
                                color: selected
                                    ? Colors.grey[200]
                                    : Colors.transparent,
                                child: ListTile(
                                  selected: selected,
                                  onLongPress: () =>
                                      setLocation(item, open: true),
                                  onTap: () => setLocation(item),
                                  title: Text(
                                      '${DateFormat.Md().format(timestamp)}'),
                                  subtitle: Text(
                                      '${DateFormat.jms().format(timestamp)}'),
                                  trailing: Icon(
                                      item.exposure
                                          ? Icons.warning
                                          : Icons.place,
                                      color: selected
                                          ? Colors.red
                                          : item.exposure
                                              ? Colors.orange
                                              : Colors.grey),
                                ))),
                        Divider(height: 0),
                      ]);
                    },
                  )))
        ]));
  }
}
