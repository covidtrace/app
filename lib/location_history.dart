import 'dart:async';
import 'package:covidtrace/helper/location.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'storage/location.dart';
import 'storage/user.dart';
import 'package:latlong/latlong.dart' as lt;

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
  LatLng _currentLocation;
  bool _nearHome;
  Completer<GoogleMapController> _controller = Completer();
  ScrollController _scroller = ScrollController();
  List<Marker> _markers = [];
  UserModel _user;

  @override
  void initState() {
    super.initState();
    loadInitState();
  }

  Future<void> loadInitState() async {
    await loadLocations();
    await loadUser();
    var position = await currentLocation();
    var nearHome = await UserModel.isInHome(position);
    setState(() => _nearHome = nearHome);
  }

  loadUser() async {
    var user = await UserModel.find();
    setState(() => _user = user);
  }

  Future<LatLng> currentLocation() async {
    var loc = await locateCurrentPosition();
    setState(() => _currentLocation = loc);

    return loc;
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
        Marker(
            markerId: MarkerId(item.id.toString()),
            position: loc,
            onTap: () => launchMapsApp(loc))
      ];
    });

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLng(loc));

    if (open && Theme.of(context).platform == TargetPlatform.iOS) {
      launchMapsApp(loc);
    }
  }

  lt.LatLng toLtLatLng(LatLng loc) {
    return lt.LatLng(loc.latitude, loc.longitude);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Location History')),
        body: Column(children: [
          _nearHome != null
              ? Container(
                  color: Colors.blueGrey,
                  child: ListTileTheme(
                    textColor: Colors.white,
                    iconColor: Colors.white,
                    child: ListTile(
                      trailing: Icon(
                        _nearHome ? Icons.location_off : Icons.location_on,
                        size: 35,
                      ),
                      title: Text(_nearHome
                          ? 'Near your home'
                          : 'Location tracking on'),
                      subtitle: Text(_nearHome
                          ? 'Location tracking is off.'
                          : 'The location history is only on your phone.'),
                    ),
                  ))
              : Container(),
          Flexible(
              flex: 2,
              child: Stack(children: [
                (_selected != null || _currentLocation != null)
                    ? GoogleMap(
                        mapType: MapType.normal,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        initialCameraPosition: CameraPosition(
                            target: _selected != null
                                ? _selected.latLng
                                : _currentLocation,
                            zoom: 16),
                        markers: _markers.toSet(),
                        circles: _user?.home != null
                            ? [
                                new Circle(
                                    circleId: CircleId('home'),
                                    center: _user.home,
                                    radius: _user.homeRadius,
                                    fillColor: Colors.red.withOpacity(.2),
                                    strokeColor: Colors.red,
                                    strokeWidth: 2)
                              ].toSet()
                            : Set(),
                        onMapCreated: (GoogleMapController controller) {
                          _controller.complete(controller);
                        },
                      )
                    : Container(),
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 15.0,
                    child: Center(
                        child: CupertinoSlidingSegmentedControl(
                            backgroundColor: Color(0xCCCCCCCC),
                            padding: EdgeInsets.all(5),
                            groupValue: _filter,
                            children: {
                              'all': Text('All Locations'),
                              'exposed': Text('Potential Exposures'),
                            },
                            onValueChanged: setFilter))),
              ])),
          Divider(
            height: 0,
            color: Colors.grey,
          ),
          Flexible(
              flex: 3,
              child: RefreshIndicator(
                  onRefresh: loadLocations,
                  child: ListView.builder(
                    controller: _scroller,
                    physics: AlwaysScrollableScrollPhysics(),
                    itemCount: _display.length,
                    itemBuilder: (context, i) {
                      var item = _display[i];
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
                                      '${DateFormat.jm().format(timestamp)}'),
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
