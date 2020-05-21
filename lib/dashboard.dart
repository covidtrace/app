import 'dart:async';

import 'package:covidtrace/storage/exposure.dart';

import 'operator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'state.dart';
import 'verify_phone.dart';

const EXPOSURE_FAQ = [
  {
    "title": 'What should I do if I am not sick?',
    "body":
        'You should monitor your health for fever, cough and shortness of breath during the 14 days after the last day you were in close contact with the sick person with COVID-19.',
    "link": "https://coronavirus.wa.gov/",
  },
  {
    "title": 'What should I do if I work in critical infrastructure?',
    "body":
        'Critical infrastructure workers who had close contact with a COVID-19 case can continue to work as long as they remain well without symptoms and if they take the following measures',
    "link": "https://coronavirus.wa.gov/",
  },
  {
    "title": 'What is coronavirus disease 2019 (COVID-19)?',
    "body":
        'COVID-19 is a respiratory disease caused by a new virus called SARS-CoV-2. The most common symptoms of the disease are fever, cough, and shortness of breath.',
    "link": "https://coronavirus.wa.gov/",
  },
];

const NON_EXPOSURE_FAQ = [
  {
    "icon": 'assets/who_logo.jpg',
    "title": 'World Health Organization',
    "body":
        'Stay aware of the latest information on the COVID-19 outbreak, available on the WHO website and through your national and local public health authority.',
    "link": 'https://www.who.int/emergencies/diseases/novel-coronavirus-2019',
  },
  {
    "icon": 'assets/do_the_five.gif',
    "title": 'Do The Five',
    "body":
        '1. STAY home as much as you can\n2. KEEP a safe distance\n3. WASH hands often\n4. COVER your cough\n5. SICK? Call ahead',
    "link": 'https://www.google.com/covid19/#safety-tips',
  },
  {
    "icon": 'assets/stay_home_save_lives.png',
    "title": 'Stay Home, Save Lives',
    "body":
        'Let frontline workers do their jobs. COVID-19 is spreading, and you may not know you’re infected until you’ve already infected others.',
    "link": 'https://www.stayhomesavelives.us',
  },
  {
    "icon": 'assets/crisis_test_line.png',
    "title": 'Crisis Text Line',
    "body":
        "Text HOME to 741741 from anywhere in the United States, anytime. Crisis Text Line is here for any crisis.",
    "link": 'https://www.crisistextline.org',
  }
];

const REPORTED_FAQ = [
  {
    'title': 'Protect others from getting sick',
    'body':
        'Stay away from others for at least 7 days from when your symptoms first appeared',
    'link':
        'https://www.cdc.gov/coronavirus/2019-ncov/if-you-are-sick/steps-when-sick.html',
  },
  {
    'title': 'Monitor your symptoms',
    'body': 'If your symptoms get worse, contact your doctor’s office',
    'link':
        'https://www.cdc.gov/coronavirus/2019-ncov/if-you-are-sick/steps-when-sick.html',
  },
  {
    'title': 'Caring for yourself at home',
    'body': '10 things you can do to manage your health at home',
    'link':
        'https://www.cdc.gov/coronavirus/2019-ncov/if-you-are-sick/caring-for-yourself-at-home.html',
  },
];

var healthAuthority = {
  "name": "State Department of Health",
  "updated": DateTime(2020, 05, 1),
};

class Dashboard extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => DashboardState();
}

class DashboardState extends State with TickerProviderStateMixin {
  bool _expandHeader = false;
  bool _sendingExposure = false;
  ExposureModel _oldest;
  AnimationController reportController;
  CurvedAnimation reportAnimation;
  AnimationController expandController;
  CurvedAnimation animation;

  void initState() {
    super.initState();
    expandController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 200));
    animation =
        CurvedAnimation(parent: expandController, curve: Curves.fastOutSlowIn);

    reportController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 200), value: 1);
    reportAnimation =
        CurvedAnimation(parent: reportController, curve: Curves.fastOutSlowIn);

    Provider.of<AppState>(context, listen: false).addListener(onStateChange);

    loadOldest();
  }

  @override
  void dispose() {
    expandController.dispose();
    super.dispose();
  }

  void loadOldest() async {
    var exposures = await ExposureModel.findAll(limit: 1, orderBy: 'date');
    setState(() => _oldest = exposures.isNotEmpty ? exposures.first : null);
  }

  void onStateChange() async {
    AppState state = Provider.of<AppState>(context, listen: false);
    if (state.report != null) {
      expandController.forward();
      setState(() => _expandHeader = true);
    }
  }

  Future<void> refreshExposures(AppState state) async {
    await state.checkExposures();
  }

  Future<void> sendExposure(AppState state) async {
    if (!state.user.verified) {
      state.user.token = await verifyPhone();
      if (state.user.verified) {
        await state.saveUser(state.user);
      }
    }

    if (!state.user.verified) {
      return;
    }

    setState(() => _sendingExposure = true);
    await state.sendExposure();
    setState(() => _sendingExposure = false);
    Scaffold.of(context).showSnackBar(
        SnackBar(content: Text('Your report was successfully submitted')));
  }

  Future<Token> verifyPhone() {
    return showModalBottomSheet(
      context: context,
      builder: (context) => VerifyPhone(),
      isScrollControlled: true,
    );
  }

  Future<void> showExposureDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Exposure Report'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    "The COVID Trace app does not automatically notify us about an exposure alert. When you hit \"Send Report\", we will be able to count in your area the number of people potentially exposed.\n\nCounting your alert helps health officials know how much COVID-19 may be spreading."),
              ],
            ),
          ),
          actions: <Widget>[
            FlatButton(
              child: Text('Ok'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget cardIcon(String name) {
    return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.asset(name, width: 40, height: 40, fit: BoxFit.contain));
  }

  Widget createCard(BuildContext context, Map<String, String> item) {
    var subhead = Theme.of(context)
        .textTheme
        .subtitle1
        .merge(TextStyle(fontWeight: FontWeight.bold));

    var mainContent = [
      Text(item['title'], style: subhead),
      SizedBox(height: 5),
      Text(item['body']),
    ];

    return Card(
      color: Colors.white,
      elevation: 1,
      margin: EdgeInsets.symmetric(vertical: 10, horizontal: 1),
      child: Padding(
        padding: EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...(item.containsKey('icon'))
                ? [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: mainContent,
                          ),
                        ),
                        SizedBox(width: 10),
                        cardIcon(item['icon']),
                      ],
                    ),
                  ]
                : mainContent,
            ...(item.containsKey('link'))
                ? [
                    Divider(height: 20),
                    InkWell(
                      onTap: () => launch(item['link']),
                      child: Text('Learn more',
                          style: TextStyle(color: Colors.blue)),
                    ),
                  ]
                : [],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;
    var subhead = Theme.of(context)
        .textTheme
        .subtitle1
        .merge(TextStyle(fontWeight: FontWeight.bold));
    var alertText = TextStyle(color: Colors.white);

    var heading = (String title) => [
          SizedBox(height: 20),
          Center(
              child: Text(healthAuthority['name'], style: textTheme.caption)),
          Center(
              child: Text(
                  'Updated ${DateFormat.yMMMd().format(healthAuthority['updated'])}',
                  style: textTheme.caption)),
          SizedBox(height: 10),
          Center(child: Text(title, style: subhead)),
          SizedBox(height: 10),
        ];

    return Consumer<AppState>(builder: (context, state, _) {
      if (state.report != null) {
        return Padding(
          padding: EdgeInsets.only(left: 15, right: 15),
          child: ListView(children: [
            SizedBox(height: 15),
            Container(
                decoration: BoxDecoration(
                    color: Colors.blueGrey,
                    borderRadius: BorderRadius.circular(10)),
                child: InkWell(
                    onTap: () {
                      setState(() => _expandHeader = !_expandHeader);
                      _expandHeader
                          ? expandController.forward()
                          : expandController.reverse();
                    },
                    child: Padding(
                        padding: EdgeInsets.all(15),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text('Report Submitted',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headline6
                                          .merge(alertText)),
                                  Text(
                                      'On ${DateFormat.yMMMd().add_jm().format(state.report.timestamp)}',
                                      style: alertText)
                                ])),
                            Image.asset('assets/clinic_medical_icon.png',
                                height: 40),
                          ]),
                          SizeTransition(
                              child: Column(children: [
                                Divider(height: 20, color: Colors.white),
                                Text(
                                    'Thank you for submitting your anonymized exposure history. Your data will help people at risk respond faster.',
                                    style: alertText)
                              ]),
                              axisAlignment: 1.0,
                              sizeFactor: animation),
                        ])))),
            ...heading('What To Do Next'),
            ...REPORTED_FAQ.map((item) => createCard(context, item)),
            SizedBox(height: 50), // Account for floating action button
          ]),
        );
      }

      var lastCheck = state.user.lastCheck;
      int days = 0;
      int hours = 0;
      if (_oldest != null) {
        var diff = DateTime.now().difference(_oldest.date);
        days = diff.inDays;
        hours = diff.inHours;
      }

      var exposure = state.exposure;
      if (exposure == null) {
        return Padding(
            padding: EdgeInsets.only(left: 15, right: 15),
            child: RefreshIndicator(
                onRefresh: () => refreshExposures(state),
                child: ListView(children: [
                  SizedBox(height: 15),
                  Container(
                      decoration: BoxDecoration(
                          color: Colors.blueGrey,
                          borderRadius: BorderRadius.circular(10)),
                      child: InkWell(
                          onTap: () {
                            setState(() => _expandHeader = !_expandHeader);
                            _expandHeader
                                ? expandController.forward()
                                : expandController.reverse();
                          },
                          child: Padding(
                              padding: EdgeInsets.all(15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text('No Exposures Found',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headline6
                                                    .merge(alertText)),
                                            Text(
                                                days >= 1
                                                    ? 'In the last ${days > 1 ? '$days days' : 'day'}'
                                                    : 'In the last ${hours > 1 ? '$hours hours' : 'hour'}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .subtitle1
                                                    .merge(alertText))
                                          ])),
                                      Image.asset(
                                          'assets/people_arrows_icon.png',
                                          height: 40),
                                    ],
                                  ),
                                  Divider(height: 20, color: Colors.white),
                                  Text(
                                      'Last checked: ${DateFormat.jm().format(lastCheck ?? DateTime.now()).toLowerCase()}',
                                      style: alertText)
                                ],
                              )))),
                  ...heading('Tips & Resources'),
                  ...NON_EXPOSURE_FAQ.map((item) => createCard(context, item)),
                  SizedBox(height: 50), // Account for floating action button
                ])));
      }

      return Padding(
          padding: EdgeInsets.only(left: 15, right: 15),
          child: RefreshIndicator(
              onRefresh: () => refreshExposures(state),
              child: ListView(children: [
                SizedBox(height: 15),
                Container(
                    decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10)),
                    child: InkWell(
                        onTap: () {
                          setState(() => _expandHeader = !_expandHeader);
                          _expandHeader
                              ? expandController.forward()
                              : expandController.reverse();
                        },
                        child: Padding(
                            padding: EdgeInsets.all(15),
                            child: Column(children: [
                              Row(children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text('Potential Exposure',
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline6
                                              .merge(alertText)),
                                      SizedBox(height: 2),
                                      Text(
                                          'On ${DateFormat.EEEE().add_MMMd().format(exposure.date)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .subtitle1
                                              .merge(alertText))
                                    ])),
                                Image.asset('assets/shield_virus_icon.png',
                                    height: 40),
                              ]),
                              Divider(height: 20, color: Colors.white),
                              Text(
                                  "You were in close proximity to someone for ${exposure.duration.inMinutes * 2} minutes who tested positive for COVID-19.",
                                  style: alertText)
                            ])))),
                ...heading('What To Do Now'),
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(15),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('County Health Department', style: subhead),
                            SizedBox(height: 5),
                            Text(
                                'Report potential exposure to your county Department of Health.'),
                          ],
                        ),
                      ),
                      Material(
                        shape: CircleBorder(),
                        color: Theme.of(context).primaryColor,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child:
                              Icon(Icons.phone, color: Colors.white, size: 30),
                        ),
                      ),
                    ]),
                  ),
                ),
                SizedBox(height: 10),
                ...EXPOSURE_FAQ.map((item) => createCard(context, item)),
                SizedBox(height: 50), // Account for floating action button
              ])));
    });
  }
}
