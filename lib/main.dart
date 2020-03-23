import 'listen_location.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'state.dart';
import 'send_report.dart';
import 'settings.dart';
import 'debug_locations.dart';

void main() => runApp(
    ChangeNotifierProvider(create: (context) => ReportState(), child: MyApp()));

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      title: 'Covid Trace',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      routes: {
        '/': (context) => MyHomePage(title: 'Covid Trace'),
        '/send_report': (context) => SendReport(),
        '/debug': (context) => DebugLocations(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);
  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
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
          icon: Icon(Icons.add),
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
        body: {0: ListenLocationWidget(), 2: Settings()}[navBarIndex]);
  }
}
