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
  var _tested = false;
  var _loading = false;

  void _sendReport() async {
    setState(() {
      _loading = true;
    });

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
    } catch (err) {
      print(err);
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Report Symptoms')),
        body: Padding(
            padding: EdgeInsets.only(top: 20),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Text('Symptoms', style: Theme.of(context).textTheme.title),
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _fever,
                    onChanged: (selected) => setState(() {
                      _fever = selected;
                    }),
                    title: Text('Fever'),
                  ),
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _cough,
                    onChanged: (selected) => setState(() {
                      _cough = selected;
                    }),
                    title: Text('Coughing'),
                  ),
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _breathing,
                    onChanged: (selected) => setState(() {
                      _breathing = selected;
                    }),
                    title: Text('Shortness of breath'),
                  ),
                  SwitchListTile(
                    value: _tested,
                    onChanged: (selected) => setState(() {
                      _tested = selected;
                    }),
                    title: Text('I have been tested for COVID-19'),
                  ),
                  ButtonBar(alignment: MainAxisAlignment.center, children: [
                    RaisedButton(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      color: Colors.blue,
                      child: _loading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: null,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white)))
                          : Text("Submit"),
                      onPressed: _sendReport,
                    ),
                    CupertinoButton(
                      child: Text('Cancel'),
                      onPressed: () => {Navigator.pop(context)},
                    )
                  ]),
                ])));
  }
}
