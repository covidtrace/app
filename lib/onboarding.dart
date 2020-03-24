import 'dart:async';

import 'package:covidtrace/storage/user.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_settings/app_settings.dart';

class BlockButton extends StatelessWidget {
  final onPressed;
  final String label;

  BlockButton({this.onPressed, this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child: RaisedButton(
              child: Text(label, style: TextStyle(fontSize: 20)),
              onPressed: onPressed,
              textColor: Colors.white,
              color: Theme.of(context).buttonTheme.colorScheme.primary,
              shape: StadiumBorder(),
              padding: EdgeInsets.all(15)))
    ]);
  }
}

class Onboarding extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => OnboardingState();
}

class OnboardingState extends State {
  var _pageController = PageController();
  var _requestLocation = false;
  var _requestNotification = false;
  var _linkToSettings = false;
  Completer<GoogleMapController> _mapController = Completer();

  @override
  void initState() {
    super.initState();

    bg.BackgroundGeolocation.onProviderChange((event) {
      var allowed = statusChange(event.status);
      setState(() => _linkToSettings = !allowed);
    });
  }

  bool statusChange(int status) {
    var allowed = false;
    switch (status) {
      case bg.Config.AUTHORIZATION_STATUS_ALWAYS:
      case bg.Config.AUTHORIZATION_STATUS_WHEN_IN_USE:
        allowed = true;
        break;
    }

    setState(() => _requestLocation = allowed);
    return allowed;
  }

  void nextPage() => _pageController.nextPage(
      duration: Duration(milliseconds: 250), curve: Curves.easeOut);

  void requestPermission(bool selected) async {
    if (_linkToSettings) {
      AppSettings.openAppSettings();
      return;
    }

    setState(() => _requestLocation = true);
    try {
      var status = await bg.BackgroundGeolocation.requestPermission();
      var allowed = statusChange(status);

      if (allowed) {
        bg.BackgroundGeolocation.start();
      } else {
        setState(() => _linkToSettings = true);
      }
    } catch (err) {
      // TODO(wes): Prompt user to change settings?
      statusChange(bg.Config.AUTHORIZATION_STATUS_DENIED);
    }
  }

  Future<LatLng> locateCurrentPosition() async {
    // Get current positon to show on map for marking home
    var current = await bg.BackgroundGeolocation.getCurrentPosition(
        timeout: 15, maximumAge: 10000);
    var latlng = LatLng(current.coords.latitude, current.coords.longitude);
    var mapController = await _mapController.future;
    mapController.animateCamera(CameraUpdate.newLatLng(latlng));

    return latlng;
  }

  // TODO(wes): Don't need to do this on Android
  void requestNotifications(bool selected) async {
    var plugin = FlutterLocalNotificationsPlugin();
    bool allowed = await plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        .requestPermissions(alert: true);

    setState(() => _requestNotification = allowed);
  }

  void setHome() async {
    var position = await locateCurrentPosition();
    var user = await UserModel.find();

    user.latitude = position.latitude;
    user.longitude = position.longitude;
    await user.save();

    nextPage();
  }

  @override
  Widget build(BuildContext context) {
    var bodyText = Theme.of(context)
        .textTheme
        .body1
        .merge(TextStyle(fontSize: 18, height: 1.4));

    return Container(
        color: Colors.white,
        child: Padding(
            padding: EdgeInsets.all(30),
            child: PageView(
                controller: _pageController,
                physics: NeverScrollableScrollPhysics(),
                children: [
                  Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                          'Flatten The Curve',
                          style: Theme.of(context).textTheme.headline,
                        ),
                        SizedBox(height: 10),
                        Text(
                          "CovidTrace is an early warning app to let people know if they've recently been potentially exposed to COVID-19. CovidTrace is an online way to do instant contact tracing. Contact tracing is one of the most effective ways to combat the spread of the disease. By participating, you help save lives by flattening the curve.",
                          style: bodyText,
                        ),
                        SizedBox(height: 30),
                        BlockButton(onPressed: nextPage, label: 'Get Started'),
                      ])),
                  Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Icon(Icons.near_me, size: 40),
                        Text('Sharing Your Location',
                            style: Theme.of(context).textTheme.headline),
                        SizedBox(height: 10),
                        RichText(
                          text: TextSpan(style: bodyText, children: [
                            TextSpan(
                              text:
                                  "CovidTrace’s early detection works by checking where you've been recently against the time and place of people who reported positive test results. CovidTrace does this all on your phone to maintain your privacy. Limited information is shared when reporting an infection, symptoms or exposure.\n",
                            ),
                            TextSpan(
                                text: 'Find out more here',
                                style: TextStyle(
                                    decoration: TextDecoration.underline),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    try {
                                      launch('https://covidtrace.com');
                                    } catch (err) {}
                                  })
                          ]),
                        ),
                        SizedBox(height: 30),
                        Center(
                            child: Transform.scale(
                                scale: 1.5,
                                child: Switch.adaptive(
                                    value: _requestLocation,
                                    onChanged: requestPermission))),
                        SizedBox(height: 30),
                        BlockButton(
                            label: 'Continue',
                            onPressed: _requestLocation ? nextPage : null)
                      ])),
                  Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Icon(Icons.home, size: 40),
                        Text(
                          'Mark Your Home',
                          style: Theme.of(context).textTheme.headline,
                        ),
                        SizedBox(height: 10),
                        Text(
                            'CovidTrace does not record any data when it determines you’re near your home. We do not want your home to be part of any of the recorded time and place data.',
                            style: bodyText),
                        SizedBox(height: 30),
                        ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                                height: 300,
                                child: GoogleMap(
                                  mapType: MapType.normal,
                                  myLocationEnabled: _requestLocation,
                                  myLocationButtonEnabled: _requestLocation,
                                  initialCameraPosition: CameraPosition(
                                      target: LatLng(39.5, -98.35), zoom: 18),
                                  minMaxZoomPreference:
                                      MinMaxZoomPreference(10, 18),
                                  onMapCreated: (controller) {
                                    if (!_mapController.isCompleted) {
                                      _mapController.complete(controller);
                                    }
                                    locateCurrentPosition();
                                  },
                                ))),
                        SizedBox(height: 30),
                        BlockButton(
                            label: 'Set as My Home', onPressed: setHome),
                        SizedBox(height: 10),
                        Center(
                            child: FlatButton(
                                child: Text('Skip'), onPressed: nextPage))
                      ])),
                  Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                          'What To Expect',
                          style: Theme.of(context).textTheme.headline,
                        ),
                        SizedBox(height: 10),
                        Text(
                          "CovidTrace is now monitoring your location. You will get a notification if you were potentially exposed to COVID-19.",
                          style: bodyText,
                        ),
                        SizedBox(height: 20),
                        Image.asset('assets/ios_notification.png'),
                        Row(children: [
                          Expanded(
                              child: Text('Enable notifications',
                                  style: Theme.of(context).textTheme.title)),
                          Switch.adaptive(
                              value: _requestNotification,
                              onChanged: requestNotifications),
                        ]),
                        SizedBox(height: 10),
                        RichText(
                            text: TextSpan(style: bodyText, children: [
                          TextSpan(
                            text:
                                "Your phone will periodically remind you that your location is being tracked by this app. It is important to ",
                          ),
                          TextSpan(
                            text: 'Always Allow',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                              text:
                                  ' CovidTrace to have access to your location data.')
                        ])),
                        SizedBox(height: 30),
                        BlockButton(onPressed: nextPage, label: 'Continue'),
                      ])),
                  Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                          'Thank You',
                          style: Theme.of(context).textTheme.headline,
                        ),
                        SizedBox(height: 10),
                        Text(
                          "CovidTrace will now alert you when you're potentially exposed to COVID-19. If you do get sick, let us know so that we can help others.\n\nCovidTrace cannot prevent you from getting exposed. It can only help us react faster when exposures happen.",
                          style: bodyText,
                        ),
                        SizedBox(height: 20),
                        Center(
                            child: FractionallySizedBox(
                                widthFactor: .5,
                                child: Image.asset('assets/do_the_five.gif'))),
                        SizedBox(height: 20),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: {
                              1: 'HANDS Wash them often',
                              2: 'ELBOW Cough into it',
                              3: 'FACE Don\'t touch it',
                              4: 'SPACE Keep safe distance',
                              5: 'HOME Stay if you can',
                            }
                                .map((step, text) {
                                  return MapEntry(
                                      step,
                                      Padding(
                                          padding: EdgeInsets.only(bottom: 10),
                                          child: Row(children: [
                                            Container(
                                                width: 25,
                                                height: 25,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Theme.of(context)
                                                        .primaryColor),
                                                child: Center(
                                                    child: Text('$step',
                                                        style: TextStyle(
                                                            color: Colors.white,
                                                            decoration:
                                                                TextDecoration
                                                                    .none,
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)))),
                                            SizedBox(width: 10),
                                            Text(text, style: bodyText)
                                          ])));
                                })
                                .values
                                .toList()),
                        SizedBox(height: 30),
                        BlockButton(
                            onPressed: () => Navigator.of(context)
                                .pushReplacementNamed('/home'),
                            label: 'Finish'),
                      ])),
                ])));
  }
}
