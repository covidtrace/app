import 'dart:io';

import 'package:animations/animations.dart';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/storage/exposure.dart';
import 'package:covidtrace/storage/report.dart';
import 'package:flutter/foundation.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:package_info/package_info.dart';
import 'package:provider/provider.dart';

import 'dashboard.dart';
import 'helper/check_exposures.dart';
import 'onboarding.dart';
import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'send_report.dart';
import 'state.dart';
import 'package:wakelock/wakelock.dart';

void main() async {
  await Config.load();

  runApp(ChangeNotifierProvider(
      create: (context) => AppState(), child: CovidTraceApp()));

  if (Platform.isAndroid) {
    BackgroundFetch.registerHeadlessTask((String id) async {
      await checkExposures();
      BackgroundFetch.finish(id);
    });
  }

  var notificationPlugin = FlutterLocalNotificationsPlugin();
  notificationPlugin.initialize(
      InitializationSettings(
          AndroidInitializationSettings('ic_launcher'),
          IOSInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false)),
      onSelectNotification: (notice) async {});
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
  int _navIndex = 0;

  Future<void> initBackgroundFetch() async {
    /// This Task ID must match the bundle ID that has the granted entitlements
    /// and end in `exposure-notification`. See:
    /// https://developer.apple.com/documentation/exposurenotification/building_an_app_to_notify_users_of_covid-19_exposure
    var packageName = (await PackageInfo.fromPlatform()).packageName;
    var enTaskID = '$packageName.exposure-notification';

    await BackgroundFetch.configure(
        BackgroundFetchConfig(
          enableHeadless: true,
          minimumFetchInterval: 15,
          requiredNetworkType: NetworkType.ANY,
          requiresBatteryNotLow: true,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: true,
          startOnBoot: true,
          stopOnTerminate: false,
        ), (String taskId) async {
      if (taskId == enTaskID) {
        await checkExposures();
      }
      BackgroundFetch.finish(taskId);
    });

    await BackgroundFetch.scheduleTask(
        TaskConfig(taskId: enTaskID, delay: 1000 * 60 * 15, periodic: true));
  }

  @override
  void initState() {
    super.initState();
    if (!kReleaseMode) {
      Wakelock.enable();
    }

    initBackgroundFetch();
  }

  testInfection() async {
    Navigator.of(context).pop();
    var exp = await ExposureModel.findAll(limit: 1, orderBy: 'date DESC');
    if (exp.isEmpty) {
      await ExposureModel(
        date: DateTime.now(),
        duration: Duration(minutes: 5),
        totalRiskScore: 6,
        transmissionRiskLevel: 0,
      ).insert();
    }
  }

  resetInfection(AppState state) async {
    Navigator.of(context).pop();
    await state.resetInfections();
  }

  testReport(AppState state) async {
    Navigator.of(context).pop();
    await state.saveReport(
        ReportModel(lastExposureKey: 'test-key', timestamp: DateTime.now()));
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
    Navigator.of(context).pop();
    showExposureNotification(
        ExposureInfo(DateTime.now(), Duration(minutes: 5), 6, 0));
  }

  resetVerified(AppState state) async {
    Navigator.of(context).pop();
    var user = state.user;
    user.token = null;
    await state.saveUser(user);
  }

  onBottomNavTap(int index) async {
    if (index == 2) {
      launch(Config.get()['healthAuthority']['link']);
      return;
    }

    setState(() {
      _navIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var selectedColor = theme.primaryColor;
    var defaultColor = theme.textTheme.caption.color;

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
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _navIndex,
                onTap: (value) => onBottomNavTap(value),
                items: [
                  BottomNavigationBarItem(
                      icon: Padding(
                        padding: EdgeInsets.only(bottom: 5),
                        child: Image.asset(
                          'assets/people_arrows_icon.png',
                          height: 25,
                          color: _navIndex == 0 ? selectedColor : defaultColor,
                        ),
                      ),
                      title: Text('Exposures')),
                  BottomNavigationBarItem(
                      icon: Padding(
                        padding: EdgeInsets.only(bottom: 5),
                        child: Image.asset(
                          'assets/self_report_icon.png',
                          height: 25,
                          color: _navIndex == 1 ? selectedColor : defaultColor,
                        ),
                      ),
                      title: Text('Notify Others')),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.info_outline, size: 30),
                    title: Text('About'),
                  ),
                ],
              ),
              endDrawer: kReleaseMode
                  ? null
                  : Drawer(
                      child: ListView(children: [
                      ListTile(
                          leading: Icon(Icons.bug_report),
                          title: Text('Test Exposure'),
                          onTap: testInfection),
                      ListTile(
                          leading: Icon(Icons.restore),
                          title: Text('Reset Exposure'),
                          onTap: () => resetInfection(state)),
                      ListTile(
                        leading: Icon(Icons.notifications),
                        title: Text('Test Notification'),
                        onTap: testNotification,
                      ),
                      ListTile(
                          leading: Icon(Icons.assignment),
                          title: Text('Test Report'),
                          onTap: () => testReport(state)),
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
              body: PageTransitionSwitcher(
                transitionBuilder:
                    (child, primaryAnimation, secondaryAnimation) {
                  return FadeThroughTransition(
                    child: child,
                    animation: primaryAnimation,
                    secondaryAnimation: secondaryAnimation,
                  );
                },
                child: _navIndex == 0 ? Dashboard() : SendReport(),
              ),
            ));
  }
}
