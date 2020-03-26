import 'config.dart';
import 'dart:convert';
import 'helper/signed_upload.dart';
import 'package:csv/csv.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'storage/location.dart';
import 'storage/report.dart';
import 'storage/user.dart';

class SendReport extends StatefulWidget {
  SendReport({Key key}) : super(key: key);

  @override
  SendReportState createState() => SendReportState();
}

class SendReportState extends State<SendReport> {
  var _tested;
  var _fever = false;
  var _cough = false;
  var _breathing = false;
  var _days = 1.0;
  var _confirm = false;

  var _loading = false;
  var _submitted = false;
  var _step = 0;

  Future<bool> _sendReport(BuildContext context) async {
    setState(() {
      _loading = true;
    });

    var success = false;
    try {
      var config = await getConfig();

      var user = await UserModel.find();

      var symptomBucket = config['symptomBucket'];
      if (symptomBucket == null) {
        symptomBucket = 'covidtrace-symptoms';
      }

      var contentType = 'application/json; charset=utf-8';
      var symptomSuccess = await signedUpload(config,
          query: {
            'bucket': symptomBucket,
            'contentType': contentType,
            'object': '${Uuid().v4()}.json'
          },
          headers: {'Content-Type': contentType},
          body: jsonEncode({
            'breathing': _breathing,
            'cough': _cough,
            'days': _days,
            'fever': _fever,
            'tested': _tested,
          }));

      if (!symptomSuccess) {
        return false;
      }

      var latestReport = await ReportModel.findLatest();
      String where =
          latestReport != null ? 'id > ${latestReport.lastLocationId}' : null;

      List<LocationModel> locations =
          await LocationModel.findAll(orderBy: 'id ASC', where: where);

      List<List<dynamic>> headers = [
        ['timestamp', 's2geo', 'status']
      ];

      var holdingBucket = config['holdingBucket'];
      if (holdingBucket == null) {
        holdingBucket = 'covidtrace-holding';
      }

      contentType = 'text/csv; charset=utf-8';
      var uploadSuccess = await signedUpload(config,
          query: {
            'bucket': holdingBucket,
            'contentType': contentType,
            'object': '${user.uuid}.csv',
          },
          headers: {
            'Content-Type': contentType,
          },
          body: ListToCsvConverter()
              .convert(headers + locations.map((l) => l.toCSV()).toList()));

      if (!uploadSuccess) {
        return false;
      }

      var report = ReportModel(
          lastLocationId: locations.last.id, timestamp: DateTime.now());
      await report.create();

      success = true;
    } catch (err) {
      print(err);
      success = false;
    } finally {
      setState(() {
        _loading = false;
        _submitted = success;
      });
    }

    return success;
  }

  @override
  Widget build(BuildContext context) {
    var enableContinue = false;
    switch (_step) {
      case 0:
        enableContinue = _tested != null;
        break;
      case 1:
        enableContinue = _fever || _cough || _breathing;
    }

    var textTheme = Theme.of(context).textTheme;
    var stepTextTheme =
        textTheme.subhead.merge(TextStyle(color: Colors.black54));
    var bodyText = textTheme.subhead.merge(TextStyle(height: 1.4));

    return Scaffold(
        appBar: AppBar(
            title: Text('Self Report'),
            leading: IconButton(
                icon: Icon(Icons.close),
                onPressed: () {
                  Navigator.pop(context);
                })),
        body: Builder(builder: (context) {
          if (_submitted) {
            return Padding(
                padding: EdgeInsets.only(top: 20, left: 30, right: 30),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sorry you\'re not feeling well',
                          style: Theme.of(context).textTheme.headline),
                      SizedBox(height: 10),
                      Text(
                          'Thank you for submitting your anonymized location history. Your data will help people at risk respond faster.',
                          style: bodyText),
                      SizedBox(height: 40),
                      Text('What you do next is important',
                          style: Theme.of(context).textTheme.headline),
                      SizedBox(height: 10),
                      Text('Take a look at suggestions by the CDC:',
                          style: textTheme.subhead),
                      InkWell(
                          onTap: () => launch(
                              'https://www.cdc.gov/coronavirus/2019-ncov/if-you-are-sick/steps-when-sick.html'),
                          child: Text('Protect others from getting sick',
                              style: textTheme.subhead.merge(TextStyle(
                                  height: 2,
                                  decoration: TextDecoration.underline)))),
                      InkWell(
                          onTap: () => launch(
                              'https://www.cdc.gov/coronavirus/2019-ncov/if-you-are-sick/caring-for-yourself-at-home.html'),
                          child: Text('10 ways to manage your health at home',
                              style: textTheme.subhead.merge(TextStyle(
                                  height: 2,
                                  decoration: TextDecoration.underline)))),
                      SizedBox(height: 40),
                      Center(
                          child: RaisedButton(
                              child: Text('Done'),
                              onPressed: () => Navigator.pop(context)))
                    ]));
          }

          return SingleChildScrollView(
              child: Column(children: [
            Padding(
                padding: EdgeInsets.only(top: 20, left: 30, right: 30),
                child: Text(
                    'When you report, you help others, save lives, and end the COVID-19 crisis sooner.',
                    style: bodyText)),
            Stepper(
                currentStep: _step,
                onStepContinue: () => setState(() => _step++),
                onStepTapped: (index) {
                  if (index < _step) {
                    setState(() => _step = index);
                  }
                },
                onStepCancel: () => _step == 0
                    ? Navigator.pop(context)
                    : setState(() => _step--),
                controlsBuilder: (context, {onStepContinue, onStepCancel}) {
                  return _step < 2
                      ? ButtonBar(
                          alignment: MainAxisAlignment.start,
                          children: [
                              RaisedButton(
                                  elevation: 0,
                                  color: Theme.of(context)
                                      .buttonTheme
                                      .colorScheme
                                      .primary,
                                  onPressed:
                                      enableContinue ? onStepContinue : null,
                                  child: Text('Continue')),
                              FlatButton(
                                  onPressed: onStepCancel,
                                  child: Text('Cancel')),
                            ])
                      : SizedBox.shrink();
                },
                steps: [
                  Step(
                      isActive: _step == 0,
                      state: _step > 0 ? StepState.complete : StepState.indexed,
                      title: Text('Official Testing', style: textTheme.title),
                      content: Column(children: [
                        Text('Have you tested positive for COVID-19?',
                            style: stepTextTheme),
                        ...[
                          'Tested Positive',
                          'Tested Negative',
                          'Pending',
                          'Not Tested'
                        ]
                            .map((value) => ListTileTheme(
                                contentPadding: EdgeInsets.all(0),
                                child: RadioListTile(
                                    controlAffinity:
                                        ListTileControlAffinity.trailing,
                                    groupValue: _tested,
                                    value: value,
                                    title: Text(value),
                                    onChanged: (value) {
                                      setState(() => _tested = value);
                                      if (value == 'Tested Positive') {
                                        setState(() => _confirm = true);
                                      }
                                    })))
                            .toList()
                      ])),
                  Step(
                      isActive: _step == 1,
                      state: _step > 1 ? StepState.complete : StepState.indexed,
                      title: Text('Symptoms', style: textTheme.title),
                      content: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('What symptoms are you experiencing?',
                                style: stepTextTheme),
                            ListTileTheme(
                                contentPadding: EdgeInsets.all(0),
                                child: CheckboxListTile(
                                  value: _fever,
                                  onChanged: (selected) =>
                                      setState(() => _fever = selected),
                                  title: Text('Fever (101°F or above)'),
                                )),
                            ListTileTheme(
                                contentPadding: EdgeInsets.all(0),
                                child: CheckboxListTile(
                                  value: _cough,
                                  onChanged: (selected) =>
                                      setState(() => _cough = selected),
                                  title: Text('Dry cough'),
                                )),
                            ListTileTheme(
                                contentPadding: EdgeInsets.all(0),
                                child: CheckboxListTile(
                                  value: _breathing,
                                  onChanged: (selected) =>
                                      setState(() => _breathing = selected),
                                  title: Text('Difficulty breathing'),
                                )),
                            ListTileTheme(
                                contentPadding: EdgeInsets.only(right: 10),
                                child: ListTile(
                                  title: Text('Days with symptoms'),
                                  trailing: Text(
                                      '${_days.round() == 10 ? '10+' : _days.round()}',
                                      style: textTheme.title),
                                )),
                            Slider(
                                min: 1,
                                max: 10,
                                value: _days,
                                onChanged: (value) =>
                                    setState(() => _days = value)),
                          ])),
                  Step(
                      isActive: _step == 2,
                      title: Text('Send Report', style: textTheme.title),
                      content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'I understand that my anonymized location history outside my home will alert others who were nearby at the time of a possible infection.'),
                            ListTileTheme(
                                contentPadding: EdgeInsets.all(0),
                                child: CheckboxListTile(
                                  value: _confirm,
                                  title: Text(
                                      'I strongly believe I have COVID-19',
                                      style: textTheme.subtitle),
                                  onChanged: (selected) =>
                                      setState(() => _confirm = selected),
                                )),
                            ButtonBar(
                                alignment: MainAxisAlignment.start,
                                children: [
                                  RaisedButton(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 40),
                                      color: Theme.of(context)
                                          .buttonTheme
                                          .colorScheme
                                          .primary,
                                      child: _loading
                                          ? SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  value: null,
                                                  valueColor:
                                                      AlwaysStoppedAnimation(
                                                          Colors.white)))
                                          : Text("Submit"),
                                      onPressed: _confirm
                                          ? () async {
                                              SnackBar snackbar;
                                              if (await _sendReport(context)) {
                                                snackbar = SnackBar(
                                                    content: Text(
                                                        'Your report was submitted successfully'));
                                              } else {
                                                snackbar = SnackBar(
                                                    backgroundColor: Colors.red,
                                                    content: Text(
                                                        'There was an error submitting your report'));
                                              }
                                              Scaffold.of(context)
                                                  .showSnackBar(snackbar);
                                            }
                                          : null),
                                  FlatButton(
                                    child: Text('Cancel'),
                                    onPressed: () => {Navigator.pop(context)},
                                  )
                                ]),
                          ])),
                ])
          ]));
        }));
  }
}
