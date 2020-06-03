import 'dart:async';

import 'package:covidtrace/config.dart';
import 'package:covidtrace/info_card.dart';
import 'package:covidtrace/storage/exposure.dart';
import 'package:covidtrace/test_facilities.dart';
import 'package:url_launcher/url_launcher.dart';

import 'operator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'state.dart';
import 'verify_phone.dart';

class Dashboard extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => DashboardState();
}

class DashboardState extends State with TickerProviderStateMixin {
  bool _sendingExposure = false;
  ExposureModel _oldest;

  void initState() {
    super.initState();
    loadOldest();
  }

  void loadOldest() async {
    var exposures = await ExposureModel.findAll(limit: 1, orderBy: 'date');
    setState(() => _oldest = exposures.isNotEmpty ? exposures.first : null);
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

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;
    var subhead = Theme.of(context)
        .textTheme
        .subtitle1
        .merge(TextStyle(fontWeight: FontWeight.bold));
    var alertText = TextStyle(color: Colors.white);

    var config = Config.get();
    var authority = config["healthAuthority"];
    var faqs = config["faqs"];

    var heading = (String title) => [
          SizedBox(height: 20),
          Center(child: Text(authority['name'], style: textTheme.caption)),
          Center(
              child: Text(
                  'Updated ${DateFormat.yMMMd().format(DateTime.parse(authority['updated']))}',
                  style: textTheme.caption)),
          SizedBox(height: 10),
          Center(child: Text(title, style: subhead)),
          SizedBox(height: 10),
        ];

    return Consumer<AppState>(builder: (context, state, _) {
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
                child: Padding(
                  padding: EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          Image.asset('assets/people_arrows_icon.png',
                              height: 40),
                        ],
                      ),
                      Divider(height: 20, color: Colors.white),
                      Text(
                          'Last checked: ${DateFormat.jm().format(lastCheck ?? DateTime.now()).toLowerCase()}',
                          style: alertText)
                    ],
                  ),
                ),
              ),
              ...heading('Tips & Resources'),
              ...faqs["non_exposure"].map((item) => InfoCard(item: item)),
              SizedBox(height: 10),
            ]),
          ),
        );
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
              child: Padding(
                padding: EdgeInsets.all(15),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Potential Exposure',
                              style: Theme.of(context)
                                  .textTheme
                                  .headline6
                                  .merge(alertText)),
                          SizedBox(height: 2),
                          Text(
                              'On ${DateFormat.EEEE().add_MMMd().format(exposure.date)}',
                              style: alertText)
                        ])),
                    Image.asset('assets/shield_virus_icon.png', height: 40),
                  ]),
                  Divider(height: 20, color: Colors.white),
                  Text(
                      "You were in close proximity to someone for ${exposure.duration.inMinutes * 2} minutes who tested positive for COVID-19.",
                      style: alertText)
                ]),
              ),
            ),
            ...heading('What To Do Now'),
            Card(
              child: Padding(
                padding: EdgeInsets.all(15),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      clipBehavior: Clip.antiAlias,
                      color: Theme.of(context).primaryColor,
                      child: InkWell(
                        onTap: () => launch('tel:${authority['phone_number']}'),
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child:
                              Icon(Icons.phone, color: Colors.white, size: 25),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            Card(
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (ctx) => TestFacilities()),
                ),
                child: Padding(
                  padding: EdgeInsets.all(15),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Find A Test Facility',
                          style: Theme.of(context)
                              .textTheme
                              .subtitle1
                              .merge(TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 5),
                        child: Image.asset('assets/clinic_medical_icon.png',
                            color: Theme.of(context).primaryColor, height: 30),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 10),
            ...faqs["exposure"].map((item) => InfoCard(item: item)),
            SizedBox(height: 10),
          ]),
        ),
      );
    });
  }
}
