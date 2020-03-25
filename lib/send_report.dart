import 'config.dart';
import 'dart:convert';
import 'package:covidtrace/state.dart';
import 'package:csv/csv.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'storage/location.dart';
import 'storage/report.dart';
import 'storage/user.dart';

class SendReport extends StatefulWidget {
  SendReport({Key key}) : super(key: key);

  @override
  SendReportState createState() => SendReportState();
}

class SendReportState extends State<SendReport> {
  var _fever;
  var _cough;
  var _breathing;
  var _days;
  var _confirm = false;

  var _loading = false;
  var _step = 0;

  void initState() {
    var state = Provider.of<ReportState>(context, listen: false).getAll();
    _fever = state['fever'];
    _cough = state['cough'];
    _breathing = state['breathing'];
    _days = state['days'];

    super.initState();
  }

  Future<bool> _sendReport(BuildContext context) async {
    setState(() {
      _loading = true;
    });

    var success = false;
    try {
      var config = await getConfig();

      var user = await UserModel.find();
      var latestReport = await ReportModel.findLatest();
      String where =
          latestReport != null ? 'id > ${latestReport.lastLocationId}' : null;

      List<LocationModel> locations =
          await LocationModel.findAll(orderBy: 'id ASC', where: where);

      List<List<dynamic>> headers = [
        ['timestamp', 's2geo', 'status']
      ];

      var object = '${user.uuid}.csv';
      var contentType = 'text/csv; charset=utf-8';

      var signUri = Uri.parse(config['notaryUrl']).replace(queryParameters: {
        'contentType': contentType,
        'object': object,
      });

      var signResp = await http.post(signUri, body: {});
      if (signResp.statusCode != 200) {
        return false;
      }

      var signJson = jsonDecode(signResp.body);
      var signedUrl = signJson['signed_url'];
      if (signedUrl == null) {
        return false;
      }

      // Upload to Cloud Storage
      var uploadResp = await http.put(signedUrl,
          headers: <String, String>{
            'Content-Type': contentType,
          },
          body: ListToCsvConverter()
              .convert(headers + locations.map((l) => l.toCSV()).toList()));

      if (uploadResp.statusCode != 200) {
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
      setState(() => _loading = false);
    }

    return success;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReportState>(builder: (context, state, child) {
      var enableContinue = false;
      switch (_step) {
        case 0:
          enableContinue = state.get('tested') != null;
          break;
        case 1:
          enableContinue = _fever || _cough || _breathing;
      }

      var textTheme = Theme.of(context).textTheme;
      var stepTextTheme =
          textTheme.subhead.merge(TextStyle(color: Colors.black54));

      return Scaffold(
          appBar: AppBar(
              title: Text('Self Report'),
              leading: IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () {
                    state.reset();
                    Navigator.pop(context);
                  })),
          body: Builder(builder: (context) {
            return SingleChildScrollView(
                child: Column(children: [
              Padding(
                  padding: EdgeInsets.only(top: 20, left: 30, right: 30),
                  child: Text(
                      'When you report, you help others, save lives, and end the COVID-19 crisis sooner.',
                      style: textTheme.subhead)),
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
                        state:
                            _step > 0 ? StepState.complete : StepState.indexed,
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
                              .map((value) => RadioListTile(
                                  controlAffinity:
                                      ListTileControlAffinity.trailing,
                                  groupValue: state.get('tested'),
                                  value: value,
                                  title: Text(value),
                                  onChanged: (value) {
                                    state.set({'tested': value});
                                    if (value == 'Tested Positive') {
                                      setState(() => _confirm = true);
                                    }
                                  }))
                              .toList()
                        ])),
                    Step(
                        isActive: _step == 1,
                        state:
                            _step > 1 ? StepState.complete : StepState.indexed,
                        title: Text('Symptoms', style: textTheme.title),
                        content: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('What symptoms are you experiencing?',
                                  style: stepTextTheme),
                              CheckboxListTile(
                                value: _fever,
                                onChanged: (selected) =>
                                    setState(() => _fever = selected),
                                title: Text('Fever (101°F or above)'),
                              ),
                              CheckboxListTile(
                                value: _cough,
                                onChanged: (selected) =>
                                    setState(() => _cough = selected),
                                title: Text('Dry cough'),
                              ),
                              CheckboxListTile(
                                value: _breathing,
                                onChanged: (selected) =>
                                    setState(() => _breathing = selected),
                                title: Text('Difficulty breathing'),
                              ),
                              ListTile(
                                title: Text('Days with symptoms'),
                                trailing: Text(
                                    '${_days.round() == 10 ? '10+' : _days.round()}',
                                    style: textTheme.title),
                              ),
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
                              InkWell(
                                  onTap: () =>
                                      setState(() => _confirm = !_confirm),
                                  child: Row(
                                    children: [
                                      Expanded(
                                          child: Text(
                                              'I strongly believe I have COVID-19',
                                              style: textTheme.subtitle)),
                                      Checkbox(
                                        value: _confirm,
                                        onChanged: (selected) =>
                                            setState(() => _confirm = selected),
                                      )
                                    ],
                                  )),
                              ButtonBar(
                                  alignment: MainAxisAlignment.start,
                                  children: [
                                    RaisedButton(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 40),
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
                                                if (await _sendReport(
                                                    context)) {
                                                  snackbar = SnackBar(
                                                      content: Text(
                                                          'Your report was submitted successfully'));
                                                } else {
                                                  snackbar = SnackBar(
                                                      backgroundColor:
                                                          Colors.red,
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
    });
  }
}
