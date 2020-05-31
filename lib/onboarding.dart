import 'package:app_settings/app_settings.dart';
import 'package:covidtrace/config.dart';
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

    AuthorizationStatus status;
    try {
      status = await GactPlugin.authorizationStatus;
      print('enable exposure notification $status');

      if (status != AuthorizationStatus.Authorized) {
        status = await GactPlugin.enableExposureNotification();
      }

      if (status != AuthorizationStatus.Authorized) {
        setState(() => _linkToSettings = true);
      }
    } catch (err) {
      print(err);
      if (errorFromException(err) == ErrorCode.notAuthorized) {
        setState(() => _linkToSettings = true);
      }
    }

    setState(() => _requestExposure = status == AuthorizationStatus.Authorized);
  }

  void requestNotifications(bool selected) async {
    var plugin = FlutterLocalNotificationsPlugin();
    bool allowed = await plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        .requestPermissions(alert: true, sound: true);

    setState(() => _requestNotification = allowed);
    var user = await UserModel.find();
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
        .bodyText2
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
                            style: Theme.of(context).textTheme.headline5,
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
                          "COVID Trace is an early warning app to let people know if they've recently been potentially exposed to COVID-19. COVID Trace is an online way to do instant contact tracing. Contact tracing is one of the most effective ways to combat the spread of the disease. By participating, you help save lives by flattening the curve.",
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
                        Row(children: [
                          Expanded(
                              child: Text('Enable Exposure Notifications',
                                  style:
                                      Theme.of(context).textTheme.headline5)),
                          Icon(Icons.near_me, size: 40, color: Colors.black38)
                        ]),
                        SizedBox(height: 10),
                        RichText(
                          text: TextSpan(style: bodyText, children: [
                            TextSpan(
                              text:
                                  "COVID Trace’s early detection works by using Bluetooth to see if you have come in contact with people who reported positive test results. COVID Trace does this all on your phone to maintain your privacy. Limited information is shared when reporting an infection or potential exposure.\n",
                            ),
                            TextSpan(
                                text: 'Find out more here',
                                style: TextStyle(
                                    decoration: TextDecoration.underline),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    try {
                                      launch(Config.get()['onboarding']
                                          ['en_faq_link']);
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
                                        onChanged: requestPermission)))),
                        SizedBox(height: 30),
                        BlockButton(
                            label: 'Continue',
                            onPressed: _requestExposure ? nextPage : null)
                      ])),
                  Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                          'What To Expect',
                          style: Theme.of(context).textTheme.headline5,
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
                                    onTap: () =>
                                        requestNotifications(!_requestExposure),
                                    child: Row(children: [
                                      Expanded(
                                          child: Text('Enable notifications',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headline6)),
                                      Switch.adaptive(
                                          value: _requestNotification,
                                          onChanged: requestNotifications),
                                    ])))
                            : Container(),
                        SizedBox(height: 30),
                        BlockButton(onPressed: finish, label: 'Finish'),
                      ])),
                ]),
          ),
        ),
      ),
    );
  }
}
