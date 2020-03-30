import 'dart:async';
import 'helper/check_exposures.dart';
import 'helper/location.dart';
import 'package:covidtrace/operator.dart';
import 'package:covidtrace/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'verify_phone.dart';

class Dashboard extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => DashboardState();
}

class DashboardState extends State with TickerProviderStateMixin {
  bool _exposed;
  bool _expandHeader = false;
  bool _sendingExposure = false;
  bool _hideReport = true;
  Completer<GoogleMapController> _mapController = Completer();
  AnimationController reportController;
  CurvedAnimation reportAnimation;
  AnimationController expandController;
  CurvedAnimation animation;

  void initState() {
    super.initState();
    expandController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 200));
    animation =
        CurvedAnimation(parent: expandController, curve: Curves.fastOutSlowIn);

    reportController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 200), value: 1);
    reportAnimation =
        CurvedAnimation(parent: reportController, curve: Curves.fastOutSlowIn);

    Provider.of<AppState>(context, listen: false).addListener(onStateChange);
  }

  @override
  void dispose() {
    expandController.dispose();
    super.dispose();
  }

  void onStateChange() async {
    AppState state = Provider.of<AppState>(context, listen: false);
    if (state.report != null) {
      expandController.forward();
      setState(() => _expandHeader = true);
    }

    if ((state.exposure?.reported ?? false) && !reportController.isAnimating) {
      setState(() => _hideReport = false);
      await Future.delayed(Duration(seconds: 1));
      await reportController.reverse();
      setState(() => _hideReport = true);
    }
  }

  Future<void> refreshExposures(AppState state) async {
    var currentExposed = state.exposure != null;
    var found = await checkExposures();
    var location = await state.checkExposure();

    if (location != null) {
      var controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newLatLng(
          LatLng(location.latitude, location.longitude)));
    }

    setState(() => _exposed = location != null);
    // checkEposures also sends a notification if it found one.
    // Since we have debug functionality for testing infections
    // we special case showing a notice here.
    if (_exposed && currentExposed != true && !found) {
      showExposureNotification(location);
    }
  }

  Future<void> sendExposure(AppState state) async {
    var token = Token(
        token: state.user.verifyToken, refreshToken: state.user.refreshToken);

    if (!token.valid) {
      token = await verifyPhone();

      if (token != null && token.valid) {
        state.user.verifyToken = token.token;
        state.user.refreshToken = token.refreshToken;
        await state.saveUser(state.user);
      }
    }

    if (!token.valid) {
      return;
    }

    setState(() => _sendingExposure = true);
    await state.sendExposure(token);
    setState(() => _sendingExposure = false);
    Scaffold.of(context).showSnackBar(
        SnackBar(content: Text('Your report was successfully submitted')));
  }

  Future<Token> verifyPhone() {
    return showModalBottomSheet(
      context: context,
      builder: (context) => VerifyPhone(),
      isScrollControlled: true,
    );
  }

  Future<void> showExposureDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Exposure Report'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    "The COVID Trace app does not automatically notify us about an exposure alert. When you hit \"Send Report\", we will be able to count in your area the number of people potentially exposed.\n\nCounting your alert helps health officials know how much COVID-19 may be spreading."),
              ],
            ),
          ),
          actions: <Widget>[
            FlatButton(
              child: Text('Ok'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var subhead = Theme.of(context).textTheme.subhead;
    var alertText = TextStyle(color: Colors.white);
    var imageIcon = (String name) => ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.asset(name, width: 50, height: 50, fit: BoxFit.contain));

    return Consumer<AppState>(builder: (context, state, _) {
      if (state.report != null) {
        return Padding(
          padding: EdgeInsets.all(15),
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
                                  Text('Report Submitted',
                                      style: Theme.of(context)
                                          .textTheme
                                          .title
                                          .merge(alertText)),
                                  Text(
                                      DateFormat.Md()
                                          .add_jm()
                                          .format(state.report.timestamp),
                                      style: alertText)
                                ])),
                            Image.asset('assets/clinic_medical_icon.png',
                                height: 40),
                          ]),
                          SizeTransition(
                              child: Column(children: [
                                SizedBox(height: 15),
                                Divider(height: 0, color: Colors.white),
                                SizedBox(height: 15),
                                Text(
                                    'Thank you for submitting your anonymized location history. Your data will help people at risk respond faster.',
                                    style: alertText)
                              ]),
                              axisAlignment: 1.0,
                              sizeFactor: animation),
                        ])))),
            SizedBox(height: 40),
            Center(child: Text('WHAT TO DO NEXT', style: subhead)),
            SizedBox(height: 10),
            Card(
                child: Column(children: [
              ListTile(
                isThreeLine: true,
                title: Text('Protect others from getting sick'),
                subtitle: Text(
                    'Stay away from others for at least 7 days from when your symptoms first appeared'),
                onTap: () => launch(
                    'https://www.cdc.gov/coronavirus/2019-ncov/if-you-are-sick/steps-when-sick.html'),
              ),
              Divider(height: 0),
              ListTile(
                isThreeLine: true,
                title: Text('Monitor your symptoms'),
                subtitle: Text(
                    'If your symptoms get worse, contact your doctor’s office'),
                onTap: () => launch(
                    'https://www.cdc.gov/coronavirus/2019-ncov/if-you-are-sick/steps-when-sick.html'),
              ),
              Divider(height: 0),
              ListTile(
                isThreeLine: true,
                title: Text('Caring for yourself at home'),
                subtitle:
                    Text('10 things you can do to manage your health at home'),
                onTap: () => launch(
                    'https://www.cdc.gov/coronavirus/2019-ncov/if-you-are-sick/caring-for-yourself-at-home.html'),
              ),
              Divider(height: 0),
              FlatButton(
                child: Text('FIND OUT FROM THE CDC',
                    style: TextStyle(decoration: TextDecoration.underline)),
                onPressed: () => launch(
                    'https://www.cdc.gov/coronavirus/2019-ncov/specific-groups/get-ready.html'),
              )
            ])),
          ]),
        );
      }

      var location = state.exposure;
      if (location == null) {
        return Padding(
            padding: EdgeInsets.all(15),
            child: RefreshIndicator(
                onRefresh: () => refreshExposures(state),
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
                                  Image.asset('assets/people_arrows_icon.png',
                                      height: 40),
                                ]),
                                SizeTransition(
                                    child: Column(children: [
                                      SizedBox(height: 15),
                                      Divider(height: 0, color: Colors.white),
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
                      onTap: () => launch('https://www.stayhomesavelives.us'),
                    ),
                    Divider(height: 0),
                    ListTile(
                      isThreeLine: true,
                      leading: imageIcon('assets/do_the_five.gif'),
                      title: Text('Do The Five.'),
                      subtitle: Text('Help Stop Coronavirus'),
                      onTap: () =>
                          launch('https://www.google.com/covid19/#safety-tips'),
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
              onRefresh: () => refreshExposures(state),
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
                          Marker(
                              markerId: MarkerId('1'),
                              position: loc,
                              onTap: () => launchMapsApp(loc))
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
                  SizedBox(height: 10),
                  ListTile(
                    onTap: () => launchMapsApp(loc),
                    isThreeLine: false,
                    title: Text(
                        '${DateFormat.Md().format(timestamp)} ${DateFormat('ha').format(timestamp).toLowerCase()} - ${DateFormat('ha').format(timestamp.add(Duration(hours: 1))).toLowerCase()}'),
                    subtitle: Text(
                        'Your location overlapped with someone who reported as having COVID-19.'),
                  ),
                  location.reported && _hideReport
                      ? Container()
                      : SizeTransition(
                          axisAlignment: 1,
                          sizeFactor: reportAnimation,
                          child: Row(children: [
                            Expanded(
                                child: Stack(children: [
                              Center(
                                  child: OutlineButton(
                                child: _sendingExposure
                                    ? SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          value: null,
                                          valueColor: AlwaysStoppedAnimation(
                                              Theme.of(context)
                                                  .textTheme
                                                  .button
                                                  .color),
                                        ))
                                    : Text(
                                        'SEND REPORT',
                                      ),
                                onPressed: () => sendExposure(state),
                              )),
                              Positioned(
                                  right: 0,
                                  child: IconButton(
                                      icon: Icon(Icons.info_outline,
                                          color: Colors.grey),
                                      onPressed: showExposureDialog)),
                            ])),
                          ])),
                  SizedBox(height: 8),
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
                      title: Text('Stay in touch with others by phone/email'),
                      subtitle: Text(
                          'You may need to ask for help from friends, family, neighbors, etc. if you become sick.')),
                  Divider(height: 0),
                  ListTile(
                      title: Text('Determine who can care for you'),
                      subtitle: Text('if your caregiver gets sick')),
                  Divider(height: 0),
                  FlatButton(
                    child: Text('FIND OUT MORE',
                        style: TextStyle(decoration: TextDecoration.underline)),
                    onPressed: () => launch(
                        'https://www.cdc.gov/coronavirus/2019-ncov/specific-groups/get-ready.html'),
                  )
                ])),
                SizedBox(height: 100), // Account for floating action button
              ])));
    });
  }
}
