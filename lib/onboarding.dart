import 'package:app_settings/app_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:url_launcher/url_launcher.dart';

import 'storage/user.dart';

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
  var _requestExposure = false;
  var _requestNotification = false;
  var _linkToSettings = false;

  void nextPage() => _pageController.nextPage(
      duration: Duration(milliseconds: 250), curve: Curves.easeOut);

  void requestPermission(bool selected) async {
    if (_linkToSettings) {
      AppSettings.openAppSettings();
      return;
    }

    setState(() => _requestExposure = true);
    try {
      await GactPlugin.startTracing();
      bool allowed = (await GactPlugin.authorizationStatus) ==
          AuthorizationStatus.Authorized;

      if (!allowed) {
        setState(() => _linkToSettings = true);
      }
    } catch (err) {
      // TODO(wes): Prompt user to change settings?
    }
  }

  void requestNotifications(bool selected) async {
    var plugin = FlutterLocalNotificationsPlugin();
    bool allowed = await plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        .requestPermissions(alert: true, sound: true);

    setState(() => _requestNotification = allowed);
    var user = await UserModel.find();
    user.trackLocation = true;
    await user.save();
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
    var brightness = MediaQuery.platformBrightnessOf(context);

    return AnnotatedRegion(
        value: brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        child: Container(
            color: Colors.white,
            child: SafeArea(
                child: Padding(
                    padding: EdgeInsets.only(top: 30, left: 30, right: 30),
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
                                        child: Image.asset(
                                            'assets/app_icon.png',
                                            height: 40,
                                            fit: BoxFit.contain),
                                      )),
                                ]),
                                SizedBox(height: 10),
                                Text(
                                  "COVID Trace is an early warning app to let people know if they've recently been potentially exposed to COVID-19. COVID Trace is an online way to do instant contact tracing. Contact tracing is one of the most effective ways to combat the spread of the disease. By participating, you help save lives by flattening the curve.",
                                  style: bodyText,
                                ),
                                SizedBox(height: 30),
                                BlockButton(
                                    onPressed: nextPage, label: 'Get Started'),
                              ])),
                          Center(
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Expanded(
                                      child: Text('Enable Contact Tracing',
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
                                          "COVID Trace’s early detection works by using Bluetooth contact tracing to see if you have come in contact with people who reported positive test results. COVID Trace does this all on your phone to maintain your privacy. Limited information is shared when reporting an infection, symptoms or exposure.\n",
                                    ),
                                    TextSpan(
                                        text: 'Find out more here',
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline),
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
                                                value: _requestExposure,
                                                onChanged:
                                                    requestPermission)))),
                                SizedBox(height: 30),
                                BlockButton(
                                    label: 'Continue',
                                    onPressed:
                                        _requestExposure ? nextPage : null)
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
                                  "COVID Trace is now monitoring for exposures. You will get a notification if you were potentially exposed to COVID-19.",
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
                                                !_requestExposure),
                                            child: Row(children: [
                                              Expanded(
                                                  child: Text(
                                                      'Enable notifications',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .title)),
                                              Switch.adaptive(
                                                  value: _requestNotification,
                                                  onChanged:
                                                      requestNotifications),
                                            ])))
                                    : Container(),
                                SizedBox(height: 30),
                                BlockButton(
                                    onPressed: nextPage, label: 'Continue'),
                              ])),
                          SingleChildScrollView(
                              child: Center(
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                Text(
                                  "COVID Trace will now alert you when you're potentially exposed to COVID-19. If you do get sick, let us know so that we can help others.\n\nCOVID Trace cannot prevent you from getting exposed. It can only help us react faster when exposures happen.",
                                  style: bodyText,
                                ),
                                SizedBox(height: 20),
                                Center(
                                    child: Image.asset('assets/do_the_five.gif',
                                        height: 80)),
                                SizedBox(height: 20),
                                Center(
                                    child: Text('DO THE FIVE',
                                        style:
                                            Theme.of(context).textTheme.title)),
                                SizedBox(height: 20),
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                                  padding: EdgeInsets.only(
                                                      bottom: 10),
                                                  child: Row(children: [
                                                    Container(
                                                        width: 25,
                                                        height: 25,
                                                        decoration: BoxDecoration(
                                                            shape: BoxShape
                                                                .circle,
                                                            color: Theme
                                                                    .of(context)
                                                                .primaryColor),
                                                        child: Center(
                                                            child: Text('$step',
                                                                style: TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    decoration:
                                                                        TextDecoration
                                                                            .none,
                                                                    fontSize:
                                                                        14,
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
                                SizedBox(height: 30),
                              ]))),
                        ])))));
  }
}
