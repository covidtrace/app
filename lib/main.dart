import 'package:covidtrace/storage/location.dart';
import 'dashborad.dart';
import 'debug_locations.dart';
import 'package:covidtrace/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'send_report.dart';
import 'settings.dart';
import 'storage/user.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  runApp(CovidTraceApp());

  var notificationPlugin = FlutterLocalNotificationsPlugin();
  notificationPlugin.initialize(
      InitializationSettings(
          AndroidInitializationSettings(
              'app_icon'), // TODO(wes): Configure this
          IOSInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false)),
      onSelectNotification: (notice) async {});

  bg.BackgroundGeolocation.onLocation((bg.Location l) {
    print('[location] - $l');
    LocationModel model = LocationModel(
        longitude: l.coords.longitude,
        latitude: l.coords.latitude,
        activity: l.activity.type,
        sample: l.sample ? 1 : 0,
        speed: l.coords.speed,
        timestamp: DateTime.parse(l.timestamp));
    LocationModel.insert(model);
  }, (bg.LocationError error) {
    print('[location_error] - $error');
  });

  bg.BackgroundGeolocation.onProviderChange((bg.ProviderChangeEvent event) {
    print('[providerchange] - $event');
  });

  bg.BackgroundGeolocation.ready(bg.Config(
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      stopOnTerminate: false,
      startOnBoot: true,
      logLevel: bg.Config.LOG_LEVEL_OFF));
}

class CovidTraceApp extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => CovidTraceAppState();
}

class CovidTraceAppState extends State {
  static final primaryValue = 0xFFFC4349;
  // Created by: https://www.colorbox.io/#steps=11#hue_start=348#hue_end=334#hue_curve=easeInQuad#sat_start=4#sat_end=90#sat_curve=easeOutQuad#sat_rate=130#lum_start=100#lum_end=53#lum_curve=easeOutQuad#lock_hex=#FC4349#minor_steps_map=none
  static final primaryColor = MaterialColor(
    primaryValue,
    <int, Color>{
      50: Color(0xFFFFF2F4),
      100: Color(0xFFFFC8D1),
      200: Color(0xFFFF9EAA),
      300: Color(0xFFFF7884),
      400: Color(0xFFFF5A63),
      500: Color(primaryValue),
      600: Color(0xFFEA2237),
      700: Color(0xFFD5173A),
      800: Color(0xFFBD0E3D),
      900: Color(0xFFA2063D),
    },
  );

  Future<UserModel> _user;

  @override
  void initState() {
    _user = UserModel.find();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _user,
        builder: (context, AsyncSnapshot<UserModel> snapshot) {
          if (snapshot.hasData) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              initialRoute: snapshot.data.onboarding ? '/onboarding' : '/home',
              title: 'Covid Trace',
              theme: ThemeData(primarySwatch: primaryColor),
              routes: {
                '/onboarding': (context) => Onboarding(),
                '/home': (context) => MainPage(),
                '/settings': (context) => SettingsView(),
                '/location_history': (context) => DebugLocations(),
              },
            );
          } else {
            return Container(color: Colors.white);
          }
        });
  }
}

class MainPage extends StatefulWidget {
  @override
  MainPageState createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  _showInfoDialog() {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Covid Trace'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Created by Josh Gummersall, Dudley Carr, Wes Carr'),
                SizedBox(height: 10),
                InkWell(
                  child: Text(
                    'covidtrace.com',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  onTap: () => launch("https://covidtrace.com"),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            FlatButton(
              child: Text('Ok'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  showSendReport() {
    Navigator.push(
        context,
        PageRouteBuilder(
            pageBuilder: (context, animation, _) => SendReport(),
            transitionsBuilder: (context, animation, _, child) {
              var tween = Tween(begin: Offset(0.0, 1.0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.ease));

              return SlideTransition(
                  position: animation.drive(tween), child: child);
            }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/app_icon.png',
                    fit: BoxFit.contain, height: 40),
                Text('Covid Trace'),
              ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: Image.asset('assets/self_report_icon.png', height: 25),
          label: Text('Self Report',
              style: TextStyle(
                  letterSpacing: 0, fontSize: 20, fontWeight: FontWeight.w500)),
          onPressed: showSendReport,
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        // Use an empty bottom sheet to better control positiong of floating action button
        bottomSheet: BottomSheet(
            onClosing: () {},
            builder: (context) {
              return SizedBox(height: 50);
            }),
        drawer: Drawer(
          child: ListView(children: [
            ListTile(
                leading: Icon(Icons.home),
                title: Text('Set My Home'),
                onTap: () =>
                    Navigator.of(context).popAndPushNamed('/settings')),
            ListTile(
                leading: Icon(Icons.location_on),
                title: Text('Location History'),
                onTap: () =>
                    Navigator.of(context).popAndPushNamed('/location_history')),
            ListTile(
                leading: Icon(Icons.lock),
                title: Text('Privacy Policy'),
                onTap: () => launch('https://covidtrace.com/privacy')),
            ListTile(
                leading: Icon(Icons.info),
                title: Text('About Covid Trace'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showInfoDialog();
                }),
          ]),
        ),
        body: Dashboard());
  }
}
