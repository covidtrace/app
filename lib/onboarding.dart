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

import 'helper/location.dart';
import 'storage/location.dart';

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

    bg.BackgroundGeolocation.onProviderChange(onProviderChange);
  }

  @override
  void dispose() {
    super.dispose();
    bg.BackgroundGeolocation.removeListener(onProviderChange);
  }

  void onProviderChange(event) async {
    var allowed = await statusChange(event.status);
    setState(() => _linkToSettings = !allowed);
  }

  Future<bool> statusChange(int status) async {
    var allowed = false;
    switch (status) {
      case bg.Config.AUTHORIZATION_STATUS_ALWAYS:
      case bg.Config.AUTHORIZATION_STATUS_WHEN_IN_USE:
        allowed = true;
        break;
    }

    setState(() => _requestLocation = allowed);
    var user = await UserModel.find();
    user.trackLocation = allowed;
    user.save();

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
      var allowed = await statusChange(status);

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

  // TODO(wes): Don't need to do this on Android
  void requestNotifications(bool selected) async {
    var plugin = FlutterLocalNotificationsPlugin();
    bool allowed = await plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        .requestPermissions(alert: true);

    setState(() => _requestNotification = allowed);
    var user = await UserModel.find();
    user.trackLocation = true;
    await user.save();
  }

  void setHome() async {
    var position = await locateCurrentPosition();
    await UserModel.setHome(position.latitude, position.longitude);
    await LocationModel.deleteInArea(
        position, 40); // TODO(wes): Allow configuration of radius

    nextPage();
  }

  void finish() async {
    var user = await UserModel.find();
    user.onboarding = false;
    await user.save();

    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    var bodyText = Theme.of(context)
        .textTheme
        .body1
        .merge(TextStyle(fontSize: 16, height: 1.4));

    var platform = Theme.of(context).platform;

    return Container(
        color: Colors.white,
        child: SafeArea(
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
                            Row(children: [
                              Expanded(
                                  child: Text(
                                'Flatten The Curve',
                                style: Theme.of(context).textTheme.headline,
                              )),
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: Container(
                                    color: Colors.black,
                                    child: Image.asset('assets/app_icon.png',
                                        height: 40, fit: BoxFit.contain),
                                  )),
                            ]),
                            SizedBox(height: 10),
                            Text(
                              "Covid Trace is an early warning app to let people know if they've recently been potentially exposed to COVID-19. Covid Trace is an online way to do instant contact tracing. Contact tracing is one of the most effective ways to combat the spread of the disease. By participating, you help save lives by flattening the curve.",
                              style: bodyText,
                            ),
                            SizedBox(height: 30),
                            BlockButton(
                                onPressed: nextPage, label: 'Get Started'),
                          ])),
                      SingleChildScrollView(
                          child: Center(
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                            Row(children: [
                              Expanded(
                                  child: Text('Sharing Your Location',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headline)),
                              Icon(Icons.near_me,
                                  size: 40, color: Colors.black38)
                            ]),
                            SizedBox(height: 10),
                            RichText(
                              text: TextSpan(style: bodyText, children: [
                                TextSpan(
                                  text:
                                      "Covid Trace’s early detection works by checking where you've been recently against the time and place of people who reported positive test results. Covid Trace does this all on your phone to maintain your privacy. Limited information is shared when reporting an infection, symptoms or exposure.\n",
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
                                    child: Material(
                                        color: Colors.white,
                                        child: Switch.adaptive(
                                            value: _requestLocation,
                                            onChanged: requestPermission)))),
                            SizedBox(height: 30),
                            BlockButton(
                                label: 'Continue',
                                onPressed: _requestLocation ? nextPage : null)
                          ]))),
                      Center(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Text(
                                'Mark Your Home',
                                style: Theme.of(context).textTheme.headline,
                              )),
                              Icon(Icons.home, size: 40, color: Colors.black38)
                            ]),
                            SizedBox(height: 10),
                            Text(
                                'Covid Trace does not record any data when it determines you’re near your home. We do not want your home to be part of any of the recorded location history.',
                                style: bodyText),
                            SizedBox(height: 30),
                            ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                    height: 250,
                                    child: _requestLocation
                                        ? FutureBuilder(
                                            future: locateCurrentPosition(),
                                            builder: (context, snapshot) {
                                              if (!snapshot.hasData) {
                                                return Container();
                                              }

                                              return GoogleMap(
                                                mapType: MapType.normal,
                                                myLocationEnabled:
                                                    _requestLocation,
                                                myLocationButtonEnabled:
                                                    _requestLocation,
                                                initialCameraPosition:
                                                    CameraPosition(
                                                        target: snapshot.data,
                                                        zoom: 18),
                                                minMaxZoomPreference:
                                                    MinMaxZoomPreference(
                                                        10, 18),
                                                onMapCreated: (controller) {
                                                  if (!_mapController
                                                      .isCompleted) {
                                                    _mapController
                                                        .complete(controller);
                                                  }
                                                },
                                              );
                                            })
                                        : Container())),
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
                              "Covid Trace is now monitoring your location. You will get a notification if you were potentially exposed to COVID-19.",
                              style: bodyText,
                            ),
                            SizedBox(height: 20),
                            Image.asset(platform == TargetPlatform.iOS
                                ? 'assets/ios_notification.png'
                                : 'assets/android_notification.png'),
                            SizedBox(height: 20),
                            platform == TargetPlatform.iOS
                                ? Material(
                                    color: Colors.white,
                                    child: InkWell(
                                        onTap: () => requestNotifications(
                                            !_requestLocation),
                                        child: Row(children: [
                                          Expanded(
                                              child: Text(
                                                  'Enable notifications',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .title)),
                                          Switch.adaptive(
                                              value: _requestNotification,
                                              onChanged: requestNotifications),
                                        ])))
                                : Container(),
                            SizedBox(height: 10),
                            RichText(
                                text: TextSpan(style: bodyText, children: [
                              TextSpan(
                                text:
                                    "Your phone may remind you that your location is being tracked by this app. It is important to ",
                              ),
                              TextSpan(
                                text: 'Always Allow',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                  text:
                                      ' Covid Trace to have access to your location data.')
                            ])),
                            SizedBox(height: 30),
                            BlockButton(onPressed: nextPage, label: 'Continue'),
                          ])),
                      SingleChildScrollView(
                          child: Center(
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
                              "Covid Trace will now alert you when you're potentially exposed to COVID-19. If you do get sick, let us know so that we can help others.\n\nCovid Trace cannot prevent you from getting exposed. It can only help us react faster when exposures happen.",
                              style: bodyText,
                            ),
                            SizedBox(height: 20),
                            Center(
                                child: FractionallySizedBox(
                                    widthFactor: .5,
                                    child:
                                        Image.asset('assets/do_the_five.gif'))),
                            SizedBox(height: 20),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: {
                                  1: ['HANDS', 'Wash them often'],
                                  2: ['ELBOW', 'Cough into it'],
                                  3: ['FACE', 'Don\'t touch it'],
                                  4: ['SPACE', 'Keep safe distance'],
                                  5: ['HOME', 'Stay if you can'],
                                }
                                    .map((step, text) {
                                      var lead = text[0];
                                      var title = text[1];

                                      return MapEntry(
                                          step,
                                          Padding(
                                              padding:
                                                  EdgeInsets.only(bottom: 10),
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
                                                                color: Colors
                                                                    .white,
                                                                decoration:
                                                                    TextDecoration
                                                                        .none,
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold)))),
                                                SizedBox(width: 10),
                                                Text(lead,
                                                    style: bodyText.merge(
                                                        TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold))),
                                                SizedBox(width: 5),
                                                Text(title, style: bodyText)
                                              ])));
                                    })
                                    .values
                                    .toList()),
                            SizedBox(height: 30),
                            BlockButton(onPressed: finish, label: 'Finish'),
                          ]))),
                    ]))));
  }
}
