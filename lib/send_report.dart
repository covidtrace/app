import 'package:csv/csv.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'storage/location.dart';
import 'storage/report.dart';
import 'storage/user.dart';

class SendReport extends StatefulWidget {
  SendReport({Key key}) : super(key: key);

  @override
  SendReportState createState() => SendReportState();
}

class SendReportState extends State<SendReport> {
  var _fever = false;
  var _cough = false;
  var _breathing = false;
  var _days = 1.0;
  var _gender;
  var _age;
  var _tested;
  var _loading = false;
  var _step = 0;

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
      setState(() {
        _loading = false;
      });
    }

    return success;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Report Symptoms')),
        body: Builder(builder: (BuildContext context) {
          return Stepper(
              currentStep: _step,
              onStepContinue: () => setState(() => _step++),
              onStepTapped: (index) {
                if (index < _step) {
                  setState(() => _step = index);
                }
              },
              onStepCancel: () =>
                  _step == 0 ? Navigator.pop(context) : setState(() => _step--),
              controlsBuilder: (context, {onStepContinue, onStepCancel}) {
                return _step < 3
                    ? ButtonBar(alignment: MainAxisAlignment.start, children: [
                        FlatButton(
                            color: ButtonTheme.of(context).colorScheme.primary,
                            textColor: Colors.white,
                            onPressed: onStepContinue,
                            child: Text('Continue')),
                        FlatButton(
                            onPressed: onStepCancel, child: Text('Cancel')),
                      ])
                    : SizedBox.shrink();
              },
              steps: [
                Step(
                    isActive: _step == 0,
                    state: _step > 0 ? StepState.complete : StepState.indexed,
                    title: Text('Have you tested POSITIVE for COVID-19?'),
                    content: Container(
                      child: DropdownButton(
                          value: _tested,
                          onChanged: (value) => setState(() => _tested = value),
                          hint: Text('Select an option'),
                          isExpanded: true,
                          items: ['Yes', 'No', 'Pending', 'Not Tested']
                              .map((label) => DropdownMenuItem(
                                  value: label, child: Text(label)))
                              .toList()),
                    )),
                Step(
                    isActive: _step == 1,
                    state: _step > 1 ? StepState.complete : StepState.indexed,
                    title: Text('Symptoms'),
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
                  title: Text('Optional research'),
                  state: _step > 2 ? StepState.complete : StepState.indexed,
                  content: Column(children: [
                    DropdownButton(
                        value: _age,
                        onChanged: (value) => setState(() => _age = value),
                        hint: Text('Age'),
                        isExpanded: true,
                        items: [
                          '< 2 years',
                          '2 - 4',
                          '5 - 9',
                          '10 - 18',
                          '19 - 29',
                          '30 - 39',
                          '40 - 49',
                          '50 - 59',
                          '60 - 69',
                          '70 - 79',
                          '80+'
                        ]
                            .map((label) => DropdownMenuItem(
                                value: label, child: Text(label)))
                            .toList()),
                    SizedBox(height: 10),
                    DropdownButton(
                        value: _gender,
                        onChanged: (value) => setState(() => _gender = value),
                        hint: Text('Gender'),
                        isExpanded: true,
                        items: ['Female', 'Male', 'Other']
                            .map((label) => DropdownMenuItem(
                                value: label, child: Text(label)))
                            .toList()),
                  ]),
                ),
                Step(
                    isActive: _step == 3,
                    title: Text('Send report'),
                    content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(5),
                                  color: Colors.orange),
                              padding: EdgeInsets.all(10),
                              child: Row(children: [
                                Icon(Icons.warning, color: Colors.white),
                                SizedBox(width: 10),
                                Text('Be Responsible',
                                    style: Theme.of(context)
                                        .textTheme
                                        .subhead
                                        .apply(color: Colors.white)),
                              ])),
                          SizedBox(height: 10),
                          Text(
                              'I acknowlege that by submitting my report, I am making other people aware of a potential infection in the areas covered by my location history.'),
                          ButtonBar(
                              alignment: MainAxisAlignment.start,
                              children: [
                                RaisedButton(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 40),
                                    color: Colors.blue,
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
  }
}
