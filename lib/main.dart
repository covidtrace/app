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
  // TODO(wes): Use FutureBuilder in CovidTraceApp to show blank container while loading user data
  WidgetsFlutterBinding.ensureInitialized();
  var user = await UserModel.find();

  runApp(ChangeNotifierProvider(
      create: (context) => ReportState(),
      child: CovidTraceApp(
        initialRoute: user.onboarding ? '/onboarding' : '/home',
      )));

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

class CovidTraceApp extends StatelessWidget {
  final String initialRoute;

  CovidTraceApp({Key key, @required this.initialRoute}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      title: 'CovidTrace',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      routes: {
        '/onboarding': (context) => Onboarding(),
        '/home': (context) => MainPage(title: 'CovidTrace'),
        '/send_report': (context) => SendReport(),
        '/debug': (context) => DebugLocations(),
      },
    );
  }
}

class MainPage extends StatefulWidget {
  MainPage({Key key, this.title}) : super(key: key);
  final String title;

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
          title: Text(widget.title),
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
