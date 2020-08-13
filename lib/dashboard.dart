import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/info_card.dart';
import 'package:covidtrace/privacy_policy.dart';
import 'package:covidtrace/storage/exposure.dart';
import 'package:covidtrace/test_facilities.dart';
import 'package:gact_plugin/gact_plugin.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:covidtrace/intl.dart' as locale;
import 'package:provider/provider.dart';
import 'state.dart';

class Dashboard extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => DashboardState();
}

class DashboardState extends State with TickerProviderStateMixin {
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
    await state.checkStatus();

    if (state.status == AuthorizationStatus.Authorized) {
      await state.checkExposures();
    }
  }

  Future<void> refreshStatus(AppState state) async {
    state.checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;
    var subhead = Theme.of(context)
        .textTheme
        .subtitle1
        .merge(TextStyle(fontWeight: FontWeight.bold));

    var config = Config.get();
    var authority = config["healthAuthority"];
    var theme = config['theme']['dashboard'];
    var faqs = config["faqs"];
    var intl = locale.Intl.of(context);

    var heading = (String title) => [
          SizedBox(height: 20),
          Center(
              child:
                  Text(intl.get(authority['name']), style: textTheme.caption)),
          SizedBox(height: 10),
          Center(child: Text(title, style: subhead)),
          SizedBox(height: 10),
        ];

    var privacyPolicy = () {
      return Card(
        margin: EdgeInsets.only(bottom: 15),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                fullscreenDialog: true, builder: (ctx) => PrivacyPolicy()),
          ),
          child: Padding(
            padding: EdgeInsets.all(15),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    intl.get('status.all.privacy.title'),
                    style: Theme.of(context)
                        .textTheme
                        .subtitle1
                        .merge(TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Image.asset('assets/shield_icon.png',
                      color: Theme.of(context).primaryColor, height: 30),
                ),
              ],
            ),
          ),
        ),
      );
    };

    return Consumer<AppState>(builder: (context, state, _) {
      var intl = locale.Intl.of(context);
      var lastCheck = state.user.lastCheck;
      int days = 0;
      int hours = 0;
      if (_oldest != null) {
        var diff = DateTime.now().difference(_oldest.date);
        days = diff.inDays;
        hours = diff.inHours;
      }

      var bgColor = Color(int.parse(theme['not_authorized_background']));
      var textColor = Color(int.parse(theme['not_authorized_text']));
      var alertText = TextStyle(color: textColor);

      var status = state.status;
      if (status != AuthorizationStatus.Authorized) {
        return Padding(
            padding: EdgeInsets.only(left: 15, right: 15),
            child: RefreshIndicator(
              onRefresh: () => refreshStatus(state),
              child: ListView(children: [
                SizedBox(height: 15),
                InkWell(
                  onTap: () {
                    AppSettings.openAppSettings();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                        color: bgColor,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        intl.get(
                                            'status.exposure_disabled.notice.title'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headline6
                                            .merge(alertText)),
                                  ])),
                              Image.asset('assets/virus_slash_icon.png',
                                  height: 40, color: textColor),
                            ],
                          ),
                          Divider(height: 20, color: textColor),
                          Text(intl.get('status.exposure_disabled.notice.body'),
                              style: alertText)
                        ],
                      ),
                    ),
                  ),
                ),
                ...heading(intl.get('status.non_exposure.faqs.title')),
                ...faqs["non_exposure"].map((item) => InfoCard(item: item)),
                SizedBox(height: 10),
                privacyPolicy(),
                SizedBox(height: 10),
              ]),
            ));
      }

      bgColor = Color(int.parse(theme['non_exposure_background']));
      textColor = Color(int.parse(theme['non_exposure_text']));
      alertText = TextStyle(color: textColor);

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
                    color: bgColor, borderRadius: BorderRadius.circular(10)),
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
                                Text(
                                    intl.get(
                                        'status.non_exposure.notice.title'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headline6
                                        .merge(alertText)),
                                Text(
                                    days >= 1
                                        ? intl.get(
                                            'status.non_exposure.notice.since_${days > 1 ? 'days' : 'day'}',
                                            args: [
                                                days.toString()
                                              ])
                                        : intl.get(
                                            'status.non_exposure.notice.since_${hours > 1 ? 'hours' : 'hour'}',
                                            args: [
                                                hours.toString()
                                              ]),
                                    style: Theme.of(context)
                                        .textTheme
                                        .subtitle1
                                        .merge(alertText))
                              ])),
                          Image.asset('assets/people_arrows_icon.png',
                              height: 40, color: textColor),
                        ],
                      ),
                      Divider(height: 20, color: textColor),
                      Text(
                          intl.get('status.non_exposure.notice.last_check',
                              args: [
                                DateFormat.jm()
                                    .format(lastCheck ?? DateTime.now())
                                    .toLowerCase()
                              ]),
                          style: alertText)
                    ],
                  ),
                ),
              ),
              ...heading(intl.get('status.non_exposure.faqs.title')),
              ...faqs["non_exposure"].map((item) => InfoCard(item: item)),
              SizedBox(height: 10),
              privacyPolicy(),
              SizedBox(height: 10),
            ]),
          ),
        );
      }

      bgColor = Color(int.parse(theme['exposure_background']));
      textColor = Color(int.parse(theme['exposure_text']));
      alertText = TextStyle(color: textColor);

      return Padding(
        padding: EdgeInsets.only(left: 15, right: 15),
        child: RefreshIndicator(
          onRefresh: () => refreshExposures(state),
          child: ListView(children: [
            SizedBox(height: 15),
            Container(
              decoration: BoxDecoration(
                  color: bgColor, borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: EdgeInsets.all(15),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(intl.get('status.exposure.notice.title'),
                              style: Theme.of(context)
                                  .textTheme
                                  .headline6
                                  .merge(alertText)),
                          SizedBox(height: 2),
                          Text(
                              intl.get('status.exposure.notice.date', args: [
                                DateFormat.EEEE()
                                    .add_MMMd()
                                    .format(exposure.date)
                              ]),
                              style: alertText)
                        ])),
                    Image.asset('assets/shield_virus_icon.png',
                        height: 40, color: textColor),
                  ]),
                  Divider(height: 20, color: textColor),
                  Text(
                      intl.get('status.exposure.notice.body',
                          args: [exposure.duration.inMinutes.toString()]),
                      style: alertText)
                ]),
              ),
            ),
            ...heading('What To Do Now'),
            Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: () => launch('tel:${authority['phone_number']}'),
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
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child:
                              Icon(Icons.phone, color: Colors.white, size: 25),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 20),
            Card(
              margin: EdgeInsets.zero,
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
            privacyPolicy(),
            SizedBox(height: 10),
          ]),
        ),
      );
    });
  }
}
