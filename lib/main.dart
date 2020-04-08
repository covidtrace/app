import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'beacon.dart';
import 'dashboard.dart';
import 'location_history.dart';
import 'helper/check_exposures.dart';
import 'onboarding.dart';
import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'send_report.dart';
import 'settings.dart';
import 'state.dart';
import 'storage/location.dart';
import 'storage/user.dart';
import 'package:wakelock/wakelock.dart';

void main() async {
  runApp(ChangeNotifierProvider(
      create: (context) => AppState(), child: CovidTraceApp()));

  BackgroundFetch.registerHeadlessTask((String id) async {
    await checkExposures();
    BackgroundFetch.finish(id);
  });

  var notificationPlugin = FlutterLocalNotificationsPlugin();
  notificationPlugin.initialize(
      InitializationSettings(
          AndroidInitializationSettings('ic_launcher'),
          IOSInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false)),
      onSelectNotification: (notice) async {});

  bg.BackgroundGeolocation.onLocation((bg.Location l) async {
    var coords = l.coords;
    if (await UserModel.isInHome(LatLng(coords.latitude, coords.longitude))) {
      return;
    }

    if (l.sample || coords.accuracy > 100) {
      return;
    }

    await LocationModel(
            longitude: coords.longitude,
            latitude: coords.latitude,
            activity: l.activity.type,
            sample: l.sample ? 1 : 0,
            speed: coords.speed,
            timestamp: DateTime.parse(l.timestamp))
        .insert();
  }, (bg.LocationError error) {
    // Do nothing
  });

  bg.BackgroundGeolocation.onProviderChange((bg.ProviderChangeEvent event) {
    print('[providerchange] - $event');
  });

  bg.BackgroundGeolocation.ready(bg.Config(
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      enableHeadless: true,
      stopOnTerminate: false,
      startOnBoot: true,
      fastestLocationUpdateInterval: 1000 * 60 * 5,
      persistMode: bg.Config.PERSIST_MODE_NONE,
      logLevel: bg.Config.LOG_LEVEL_OFF));

  var user = await UserModel.find();
  if (!user.onboarding) {
    setupBeaconScanning();
  }
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

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      if (state.user != null) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          initialRoute: state.user.onboarding == true ? '/onboarding' : '/home',
          title: 'COVID Trace',
          theme: ThemeData(primarySwatch: primaryColor),
          routes: {
            '/onboarding': (context) => Onboarding(),
            '/home': (context) => MainPage(),
            '/settings': (context) => SettingsView(),
            '/location_history': (context) => LocationHistory(),
            '/beacon': (context) => BeaconHistory()
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
  Future<void> initBackgroundFetch() async {
    await BackgroundFetch.configure(
        BackgroundFetchConfig(
          enableHeadless: true,
          minimumFetchInterval: 60,
          requiredNetworkType: NetworkType.ANY,
          requiresBatteryNotLow: true,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: true,
          startOnBoot: true,
          stopOnTerminate: false,
        ), (String id) async {
      await checkExposures();
      BackgroundFetch.finish(id);
    });
  }

  @override
  void initState() {
    super.initState();
    if (!kReleaseMode) {
      Wakelock.enable();
    }

    initBackgroundFetch();
  }

  showInfoDialog() {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('COVID Trace'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    'Find out more about COVID Trace and how it works on our website.'),
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

  void showSendReport(context) async {
    var sent = await Navigator.push(
        context,
        MaterialPageRoute(
            fullscreenDialog: true, builder: (context) => SendReport()));

    if (sent == true) {
      Scaffold.of(context).showSnackBar(
          SnackBar(content: Text('Your report was successfully submitted')));
    }
  }

  testInfection() async {
    Navigator.of(context).pop();
    var locs = await LocationModel.findAll(limit: 1, orderBy: 'timestamp DESC');
    if (locs.length > 0) {
      locs.first.exposure = true;
      await locs.first.save();
    }
  }

  resetInfection() async {
    Navigator.of(context).pop();
    var locs = await LocationModel.findAll(where: 'exposure = 1');
    if (locs.length > 0) {
      await Future.forEach(locs, (location) async {
        location.exposure = false;
        await location.save();
      });
    }
  }

  resetReport(AppState state) async {
    Navigator.of(context).pop();
    await state.clearReport();
  }

  resetOnboarding(AppState state) async {
    var user = state.user;
    user.onboarding = true;
    await state.saveUser(user);
    Navigator.of(context).pushReplacementNamed('/onboarding');
  }

  void testNotification() async {
    showExposureNotification((await LocationModel.findAll(limit: 1)).first);
  }

  resetVerified(AppState state) async {
    Navigator.of(context).pop();
    var user = state.user;
    user.token = null;
    await state.saveUser(user);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
        builder: (context, state, _) => Scaffold(
            appBar: AppBar(
              title: Row(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/app_icon.png',
                    fit: BoxFit.contain, height: 40),
                Text('COVID Trace'),
              ]),
              actions: <Widget>[Container()], // Hides debug end drawer
            ),
            floatingActionButtonAnimator: FloatingActionButtonAnimator.scaling,
            floatingActionButton: state.report != null
                ? null
                : Builder(
                    builder: (context) => FloatingActionButton.extended(
                          icon: Image.asset('assets/self_report_icon.png',
                              height: 25),
                          label: Text('Self Report',
                              style: TextStyle(
                                  letterSpacing: 0,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500)),
                          onPressed: () => showSendReport(context),
                        )),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
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
                    onTap: () => Navigator.of(context)
                        .popAndPushNamed('/location_history')),
                ListTile(
                    leading: Icon(Icons.bluetooth_searching),
                    title: Text('Beacons'),
                    onTap: () =>
                        Navigator.of(context).popAndPushNamed('/beacon')),
                ListTile(
                    leading: Icon(Icons.lock),
                    title: Text('Privacy Policy'),
                    onTap: () {
                      Navigator.of(context).pop();
                      launch('https://covidtrace.com/privacy-policy');
                    }),
                ListTile(
                    leading: Icon(Icons.info),
                    title: Text('About COVID Trace'),
                    onTap: () {
                      Navigator.of(context).pop();
                      showInfoDialog();
                    }),
              ]),
            ),
            endDrawer: Drawer(
                child: ListView(children: [
              ListTile(
                  leading: Icon(Icons.location_on),
                  title: Text('Start Tracking'),
                  onTap: () => bg.BackgroundGeolocation.start()),
              ListTile(
                  leading: Icon(Icons.location_off),
                  title: Text('Stop Tracking'),
                  onTap: () => bg.BackgroundGeolocation.stop()),
              ListTile(
                  leading: Icon(Icons.bug_report),
                  title: Text('Test Infection'),
                  onTap: testInfection),
              ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('Reset Infection'),
                  onTap: resetInfection),
              ListTile(
                leading: Icon(Icons.notifications),
                title: Text('Test Notification'),
                onTap: testNotification,
              ),
              ListTile(
                  leading: Icon(Icons.delete_forever),
                  title: Text('Reset Report'),
                  onTap: () => resetReport(state)),
              ListTile(
                  leading: Icon(Icons.verified_user),
                  title: Text('Reset Verified'),
                  onTap: () => resetVerified(state)),
              ListTile(
                  leading: Icon(Icons.power_settings_new),
                  title: Text('Reset Onboarding'),
                  onTap: () => resetOnboarding(state)),
            ])),
            body: Dashboard()));
  }
}
