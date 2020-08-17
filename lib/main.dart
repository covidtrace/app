import 'dart:io';

import 'package:animations/animations.dart';
import 'package:background_fetch/background_fetch.dart';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/dashboard.dart';
import 'package:covidtrace/helper/check_exposures.dart';
import 'package:covidtrace/intl.dart';
import 'package:covidtrace/onboarding.dart';
import 'package:covidtrace/send_report.dart';
import 'package:covidtrace/state.dart';
import 'package:covidtrace/storage/exposure.dart';
import 'package:covidtrace/storage/report.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:package_info/package_info.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock/wakelock.dart';

void main() async {
  await Config.load();

  GactPlugin.setup();

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
      onSelectNotification: (notice) async {
    NotificationState.instance.onNotice(notice);
  });
}

class CovidTraceApp extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => CovidTraceAppState();
}

class CovidTraceAppState extends State {
  @override
  Widget build(BuildContext context) {
    var theme = Config.get()['theme'];
    var swatch = theme['primarySwatch'];
    var colorMap = Map.fromEntries((swatch as Map<String, dynamic>)
        .map((key, value) => MapEntry(int.parse(key), Color(int.parse(value))))
        .entries);

    return Consumer<AppState>(builder: (context, state, _) {
      if (state.user != null) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: [
            const IntlDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: [
            const Locale('en', 'US'),
            const Locale('es', 'US'),
          ],
          initialRoute: state.user.onboarding == true ? '/onboarding' : '/home',
          onGenerateTitle: (BuildContext context) =>
              Intl.of(context).get(theme['title']),
          theme: ThemeData(
              primarySwatch: MaterialColor(colorMap[500].value, colorMap)),
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

    await BackgroundFetch.scheduleTask(TaskConfig(
        taskId: enTaskID,
        delay: 1000 * 60 * (kReleaseMode ? 120 : 15),
        periodic: true));
  }

  @override
  void initState() {
    super.initState();
    if (!kReleaseMode) {
      Wakelock.enable();
    }

    initBackgroundFetch();
    NotificationState.instance.addListener(() {
      // Goto exposure tab
      onBottomNavTap(0);
    });
  }

  void closeDrawer(AppState state, Function(AppState) callback) {
    Navigator.of(context).pop();
    if (callback != null) {
      callback(state);
    }
  }

  testExposure(AppState state) async {
    var rows = await ExposureModel.findAll(limit: 1, orderBy: 'date DESC');
    var exposure;
    if (rows.isEmpty) {
      exposure = ExposureModel(
        date: DateTime.now(),
        duration: Duration(minutes: 5),
        totalRiskScore: 6,
        transmissionRiskLevel: 0,
      );
      await exposure.insert();
    } else {
      exposure = rows.first;
    }

    state.setExposure(exposure);
  }

  resetExposure(AppState state) async {
    await state.resetInfections();
  }

  testReport(AppState state) async {
    await state.saveReport(
        ReportModel(lastExposureKey: 'test-key', timestamp: DateTime.now()));
    onBottomNavTap(1);
  }

  resetReport(AppState state) async {
    await state.clearReport();
  }

  resetOnboarding(AppState state) async {
    var user = state.user;
    user.firstRun = true;
    user.onboarding = true;
    await state.saveUser(user);
    Navigator.of(context).pushReplacementNamed('/onboarding');
  }

  void testNotification(AppState state) async {
    await Future.delayed(Duration(seconds: 3));
    testExposure(state);
    showExposureNotification(
      ExposureInfo(DateTime.now(), Duration(minutes: 10), 6, 0),
    );
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
    var intl = Intl.of(context);
    var config = Config.get();
    var theme = Theme.of(context);
    var selectedColor = theme.primaryColor;
    var defaultColor = theme.textTheme.caption.color;

    return Consumer<AppState>(
        builder: (context, state, _) => Scaffold(
              appBar: AppBar(
                centerTitle: true,
                title: Row(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset(config['theme']['icon'],
                      fit: BoxFit.contain, height: 40),
                  SizedBox(width: 5),
                  Text(intl.get(config['theme']['title'])),
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
                          config['nav']['dashboard']['icon'],
                          height: 25,
                          color: _navIndex == 0 ? selectedColor : defaultColor,
                        ),
                      ),
                      title:
                          Text(intl.get(config['nav']['dashboard']['title']))),
                  BottomNavigationBarItem(
                      icon: Padding(
                        padding: EdgeInsets.only(bottom: 5),
                        child: Image.asset(
                          config['nav']['report']['icon'],
                          height: 25,
                          color: _navIndex == 1 ? selectedColor : defaultColor,
                        ),
                      ),
                      title: Text(intl.get(config['nav']['report']['title']))),
                  BottomNavigationBarItem(
                    icon: Padding(
                      padding: EdgeInsets.only(bottom: 5),
                      child: Image.asset(
                        config['nav']['about']['icon'],
                        height: 25,
                        color: _navIndex == 2 ? selectedColor : defaultColor,
                      ),
                    ),
                    title: Text(intl.get(config['nav']['about']['title'])),
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
                        onTap: () => closeDrawer(state, testExposure),
                      ),
                      ListTile(
                        leading: Icon(Icons.restore),
                        title: Text('Reset Exposure'),
                        onTap: () => closeDrawer(state, resetExposure),
                      ),
                      ListTile(
                        leading: Icon(Icons.notifications),
                        title: Text('Test Notification'),
                        onTap: () => closeDrawer(state, testNotification),
                      ),
                      ListTile(
                        leading: Icon(Icons.assignment),
                        title: Text('Test Report'),
                        onTap: () => closeDrawer(state, testReport),
                      ),
                      ListTile(
                        leading: Icon(Icons.delete_forever),
                        title: Text('Reset Report'),
                        onTap: () => closeDrawer(state, resetReport),
                      ),
                      ListTile(
                        leading: Icon(Icons.power_settings_new),
                        title: Text('Reset Onboarding'),
                        onTap: () => closeDrawer(state, resetOnboarding),
                      ),
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
