import 'package:covidtrace/storage/location.dart';
import 'debug_locations.dart';
import 'listen_location.dart';
import 'package:covidtrace/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'send_report.dart';
import 'settings.dart';
import 'state.dart';
import 'storage/user.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  runApp(ChangeNotifierProvider(
      create: (context) => ReportState(), child: CovidTraceApp()));

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
              title: 'CovidTrace',
              theme: ThemeData(primarySwatch: primaryColor),
              routes: {
                '/onboarding': (context) => Onboarding(),
                '/home': (context) => MainPage(),
                '/send_report': (context) => SendReport(),
                '/debug': (context) => DebugLocations(),
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
  int navBarIndex = 0;

  _showInfoDialog() {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('CovidTrace'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
            Image.asset('assets/app_icon.png', fit: BoxFit.contain, height: 40),
            Text('CovidTrace')
          ]),
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.info_outline),
              onPressed: _showInfoDialog,
            ),
            IconButton(
              icon: Icon(Icons.bug_report),
              onPressed: () => Navigator.pushNamed(context, '/debug'),
            )
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: Icon(Icons.add_circle),
          label: Text('REPORT SYMPTOMS'),
          onPressed: () => Navigator.pushNamed(context, '/send_report'),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        bottomNavigationBar: BottomNavigationBar(
            currentIndex: navBarIndex,
            onTap: (index) => setState(() => navBarIndex = index),
            items: [
              BottomNavigationBarItem(
                  icon: Icon(Icons.home), title: Text('Home')),
              BottomNavigationBarItem(
                  icon: Icon(Icons.assignment), title: Text('Reports')),
              BottomNavigationBarItem(
                  icon: Icon(Icons.settings), title: Text('Settings')),
            ]),
        body: {
          0: ListenLocationWidget(),
          2: ChangeNotifierProvider(
              create: (context) => SettingsState(), child: Settings())
        }[navBarIndex]);
  }
}
