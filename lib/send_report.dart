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
      var user = await UserModel.find();
      var latestReport = await ReportModel.findLatest();
      String where =
          latestReport != null ? 'id > ${latestReport.lastLocationId}' : null;

      List<LocationModel> locations =
          await LocationModel.findAll(orderBy: 'id ASC', where: where);

      List<List<dynamic>> headers = [
        ['timestamp', 's2geo', 'status']
      ];

      // Upload to Cloud Storage
      var response = await http.put(
          'https://covidtrace-holding.storage.googleapis.com/${user.uuid}.csv',
          headers: <String, String>{
            'Content-Type': 'text/csv',
          },
          body: ListToCsvConverter()
              .convert(headers + locations.map((l) => l.toCSV()).toList()));

      // TODO(Josh) report errors?
      print(response.statusCode);
      print(response.body);

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

      return Scaffold(
          appBar: AppBar(
              title: Text('Report Symptoms'),
              leading: IconButton(
                  icon: Icon(Icons.arrow_back),
                  onPressed: () {
                    state.reset();
                    Navigator.pop(context);
                  })),
          body: Builder(builder: (context) {
            return Stepper(
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
                      title: Text('Official Testing'),
                      subtitle: Text('Have you tested positive for COVID-19?'),
                      content: Column(
                          children: [
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
                              .toList())),
                  Step(
                      isActive: _step == 1,
                      state: _step > 1 ? StepState.complete : StepState.indexed,
                      title: Text('Symptoms'),
                      subtitle: Text('What symptoms are you experiencing?'),
                      content: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            CheckboxListTile(
                              value: _fever,
                              onChanged: (selected) =>
                                  setState(() => _fever = selected),
                              title: Text('Fever'),
                            ),
                            CheckboxListTile(
                              value: _cough,
                              onChanged: (selected) =>
                                  setState(() => _cough = selected),
                              title: Text('Coughing'),
                            ),
                            CheckboxListTile(
                              value: _breathing,
                              onChanged: (selected) =>
                                  setState(() => _breathing = selected),
                              title: Text('Difficulty breating'),
                            ),
                            ListTile(
                              title: Text('Days with symptoms'),
                              trailing: Text(
                                  '${_days.round() == 10 ? '10+' : _days.round()}',
                                  style: Theme.of(context).textTheme.title),
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
                      title: Text('Send Report'),
                      subtitle: Text('Review and submit your report'),
                      content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'I acknowlege that by submitting my report, I am making other people aware of a potential infection in the areas covered by my location history.'),
                            InkWell(
                                onTap: () =>
                                    setState(() => _confirm = !_confirm),
                                child: Row(
                                  children: [
                                    Expanded(
                                        child: Text(
                                            'I strongly believe I have COVID-19',
                                            style: Theme.of(context)
                                                .textTheme
                                                .subtitle)),
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
                                      onPressed: () async {
                                        SnackBar snackbar;
                                        if (await _sendReport(context)) {
                                          snackbar = SnackBar(
                                              content: Text(
                                                  'You\'re report was submitted successfully'));
                                        } else {
                                          snackbar = SnackBar(
                                              backgroundColor: Colors.red,
                                              content: Text(
                                                  'There was an error submitting your report'));
                                        }
                                        Scaffold.of(context)
                                            .showSnackBar(snackbar);
                                      }),
                                  FlatButton(
                                    child: Text('Cancel'),
                                    onPressed: () => {Navigator.pop(context)},
                                  )
                                ]),
                          ])),
                ]);
          }));
    });
  }
}
