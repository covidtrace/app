import 'package:covidtrace/operator.dart';
import 'package:covidtrace/verify_phone.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state.dart';

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
  var _step = 0;
  Token _token;

  void onSubmit(context, AppState state) async {
    _token = Token(
        token: state.user.verifyToken, refreshToken: state.user.refreshToken);

    if (!_token.valid) {
      _token = await verifyPhone();
      if (_token != null && _token.valid) {
        state.user.verifyToken = _token.token;
        state.user.refreshToken = _token.refreshToken;
        await state.saveUser(state.user);
      }
    }

    if (_token == null || !_token.valid) {
      return;
    }

    if (!await sendReport(state)) {
      Scaffold.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.deepOrange,
          content: Text('There was an error submitting your report')));
    } else {
      Navigator.pop(context, true);
    }
  }

  Future<bool> sendReport(AppState state) async {
    setState(() => _loading = true);
    var success = await state.sendReport(_token, {
      'breathing': _breathing,
      'cough': _cough,
      'days': _days,
      'fever': _fever,
      'tested': _tested,
    });
    setState(() => _loading = false);

    return success;
  }

  Future<Token> verifyPhone() {
    return showModalBottomSheet(
      context: context,
      builder: (context) => VerifyPhone(),
      isScrollControlled: true,
    );
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

    return Consumer<AppState>(
        builder: (context, state, _) => Scaffold(
            appBar: AppBar(title: Text('Self Report')),
            body: Builder(builder: (context) {
              return SingleChildScrollView(
                  child: Column(children: [
                Padding(
                    padding: EdgeInsets.only(top: 20, left: 30, right: 30),
                    child: Text(
                        'When you report, you help others, save lives, and end the COVID-19 crisis sooner.',
                        style: bodyText)),
                Stepper(
                    physics: NeverScrollableScrollPhysics(),
                    currentStep: _step,
                    onStepContinue: () => setState(() => _step++),
                    onStepTapped: (index) {
                      if (index < _step) {
                        setState(() => _step = index);
                      }
                    },
                    onStepCancel: () => _step == 0
                        ? Navigator.pop(context, false)
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
                                      onPressed: enableContinue
                                          ? onStepContinue
                                          : null,
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
                          state: _step > 0
                              ? StepState.complete
                              : StepState.indexed,
                          title:
                              Text('Official Testing', style: textTheme.title),
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
                          state: _step > 1
                              ? StepState.complete
                              : StepState.indexed,
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
                                Slider.adaptive(
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
                                              ? () => onSubmit(context, state)
                                              : null),
                                      FlatButton(
                                        child: Text('Cancel'),
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                      )
                                    ]),
                              ])),
                    ])
              ]));
            })));
  }
}
