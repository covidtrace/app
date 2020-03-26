import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'helper/check_exposures.dart';
import 'storage/location.dart';

class Dashboard extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => DashboardState();
}

class DashboardState extends State with SingleTickerProviderStateMixin {
  var _exposed;
  var _recentExposure;
  var _expandHeader = false;
  Completer<GoogleMapController> _mapController = Completer();
  AnimationController expandController;
  CurvedAnimation animation;

  void initState() {
    super.initState();
    _recentExposure = loadExposures();
    expandController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 200));
    animation =
        CurvedAnimation(parent: expandController, curve: Curves.fastOutSlowIn);
  }

  @override
  void dispose() {
    expandController.dispose();
    super.dispose();
  }

  Future<LocationModel> loadExposures() async {
    var date = DateTime.now().subtract(Duration(days: 7));
    var timestamp = DateFormat('yyyy-MM-dd').format(date);

    var locations = await LocationModel.findAll(
        limit: 1,
        where: 'DATE(timestamp) > DATE(?) and exposure = 1',
        whereArgs: [timestamp],
        orderBy: 'timestamp DESC');

    return locations.isEmpty ? null : locations.first;
  }

  Future<void> refreshExposures() async {
    var found = await checkExposures();

    var load = loadExposures();
    setState(() {
      _recentExposure = load;
      return;
    });

    var location = await load;
    if (location != null) {
      var controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newLatLng(
          LatLng(location.latitude, location.longitude)));
    }

    var currentExposed = _exposed;
    setState(() => _exposed = location != null);
    // checkEposures also sends a notification if it found one.
    // Since we have debug functionality for testing infections
    // we special case showing a notice here.
    if (_exposed && currentExposed != true && !found) {
      showExposureNotification(location);
    }
  }

  @override
  Widget build(BuildContext context) {
    var subhead = Theme.of(context).textTheme.subhead;
    var alertText = TextStyle(color: Colors.white);
    var imageIcon = (String name) => ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.asset(name, width: 50, height: 50, fit: BoxFit.contain));

    return FutureBuilder(
        future: _recentExposure,
        builder: (context, AsyncSnapshot<LocationModel> snapshot) {
          if (!snapshot.hasData) {
            return Container();
          }

          var location = snapshot.data;
          if (location == null) {
            return Padding(
                padding: EdgeInsets.all(15),
                child: RefreshIndicator(
                    onRefresh: refreshExposures,
                    child: ListView(children: [
                      Container(
                          decoration: BoxDecoration(
                              color: Colors.blueGrey,
                              borderRadius: BorderRadius.circular(10)),
                          child: InkWell(
                              onTap: () {
                                setState(() => _expandHeader = !_expandHeader);
                                _expandHeader
                                    ? expandController.forward()
                                    : expandController.reverse();
                              },
                              child: Padding(
                                  padding: EdgeInsets.all(15),
                                  child: Column(children: [
                                    Row(children: [
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text('No Exposures Found',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .title
                                                    .merge(alertText)),
                                            Text('In the last 7 days',
                                                style: alertText)
                                          ])),
                                      Image.asset(
                                          'assets/people_arrows_icon.png',
                                          height: 40),
                                    ]),
                                    SizeTransition(
                                        child: Column(children: [
                                          SizedBox(height: 15),
                                          Divider(
                                              height: 0, color: Colors.white),
                                          SizedBox(height: 15),
                                          Text(
                                              'We\'ve compared your location history to infected reports and have found no overlapping history. This does not mean you have not been exposed.',
                                              style: alertText)
                                        ]),
                                        axisAlignment: 1.0,
                                        sizeFactor: animation),
                                  ])))),
                      SizedBox(height: 40),
                      Center(child: Text('TIPS & RESOURCES', style: subhead)),
                      SizedBox(height: 10),
                      Card(
                          child: Column(children: [
                        ListTile(
                          isThreeLine: true,
                          leading: imageIcon('assets/stay_home_save_lives.png'),
                          title: Text('Stay Home, Save Lives'),
                          subtitle: Text(
                              'Let frontline workers do their jobs. #StayHome'),
                          onTap: () =>
                              launch('https://www.stayhomesavelives.us'),
                        ),
                        Divider(height: 0),
                        ListTile(
                          isThreeLine: true,
                          leading: imageIcon('assets/do_the_five.gif'),
                          title: Text('Do The Five.'),
                          subtitle: Text('Help Stop Coronavirus'),
                          onTap: () => launch(
                              'https://www.google.com/covid19/#safety-tips'),
                        ),
                        Divider(height: 0),
                        ListTile(
                          isThreeLine: true,
                          leading: imageIcon('assets/who_logo.jpg'),
                          title: Text('World Health Organization'),
                          subtitle: Text('Get the latest updates on COVID-19'),
                          onTap: () => launch(
                              'https://www.who.int/emergencies/diseases/novel-coronavirus-2019'),
                        ),
                        Divider(height: 0),
                        ListTile(
                          isThreeLine: true,
                          leading: imageIcon('assets/crisis_test_line.png'),
                          title: Text('Crisis Text Line'),
                          subtitle: Text(
                              "Free, 24/7 support at your fingertips. We're only a text away."),
                          onTap: () => launch('https://www.crisistextline.org'),
                        ),
                      ]))
                    ])));
          }

          var timestamp = location.timestamp.toLocal();
          var loc = LatLng(location.latitude, location.longitude);

          return Padding(
              padding: EdgeInsets.all(15),
              child: RefreshIndicator(
                  onRefresh: refreshExposures,
                  child: ListView(children: [
                    Container(
                        decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(10)),
                        child: InkWell(
                            onTap: () {
                              setState(() => _expandHeader = !_expandHeader);
                              _expandHeader
                                  ? expandController.forward()
                                  : expandController.reverse();
                            },
                            child: Padding(
                                padding: EdgeInsets.all(15),
                                child: Column(children: [
                                  Row(children: [
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text('Possible Exposure',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .title
                                                  .merge(alertText)),
                                          Text('In the last 7 days',
                                              style: alertText)
                                        ])),
                                    Image.asset('assets/shield_virus_icon.png',
                                        height: 40),
                                  ]),
                                  SizeTransition(
                                      child: Column(children: [
                                        SizedBox(height: 15),
                                        Divider(height: 0, color: Colors.white),
                                        SizedBox(height: 15),
                                        Text(
                                            "We determine the potential for exposure by comparing your location history against the history of people who have reported as having COVID-19.",
                                            style: alertText)
                                      ]),
                                      axisAlignment: 1.0,
                                      sizeFactor: animation),
                                ])))),
                    SizedBox(height: 10),
                    Card(
                        child: Column(children: [
                      SizedBox(
                          height: 150,
                          child: GoogleMap(
                            mapType: MapType.normal,
                            myLocationEnabled: false,
                            myLocationButtonEnabled: false,
                            initialCameraPosition:
                                CameraPosition(target: loc, zoom: 16),
                            minMaxZoomPreference: MinMaxZoomPreference(10, 18),
                            markers: [
                              Marker(markerId: MarkerId('1'), position: loc)
                            ].toSet(),
                            gestureRecognizers: [
                              Factory(() => PanGestureRecognizer()),
                              Factory(() => ScaleGestureRecognizer()),
                              Factory(() => TapGestureRecognizer()),
                            ].toSet(),
                            onMapCreated: (controller) {
                              if (!_mapController.isCompleted) {
                                _mapController.complete(controller);
                              }
                            },
                          )),
                      ListTile(
                        isThreeLine: true,
                        title: Text(
                            '${DateFormat.Md().format(timestamp)} ${DateFormat('ha').format(timestamp).toLowerCase()} - ${DateFormat('ha').format(timestamp.add(Duration(hours: 1))).toLowerCase()}'),
                        subtitle: Text(
                            'Your location overlapped with someone who reported as having COVID-19.'),
                      ),
                    ])),
                    SizedBox(height: 20),
                    Center(
                        child: Text('HAVE A PLAN FOR IF YOU GET SICK',
                            style: subhead)),
                    SizedBox(height: 20),
                    Card(
                        child: Column(children: [
                      ListTile(
                          isThreeLine: true,
                          title: Text('Consult with your healthcare provider'),
                          subtitle: Text(
                              'for more information about monitoring your health for symptoms suggestive of COVID-19')),
                      Divider(height: 0),
                      ListTile(
                          isThreeLine: true,
                          title:
                              Text('Stay in touch with others by phone/email'),
                          subtitle: Text(
                              'You may need to ask for help from friends, family, neighbors, etc. if you become sick.')),
                      Divider(height: 0),
                      ListTile(
                          title: Text('Determine who can care for you'),
                          subtitle: Text('if your caregiver gets sick')),
                      Divider(height: 0),
                      FlatButton(
                        child: Text('FIND OUT MORE',
                            style: TextStyle(
                                decoration: TextDecoration.underline)),
                        onPressed: () => launch(
                            'https://www.cdc.gov/coronavirus/2019-ncov/specific-groups/get-ready.html'),
                      )
                    ])),
                    SizedBox(height: 100), // Account for floating action button
                  ])));
        });
  }
}
