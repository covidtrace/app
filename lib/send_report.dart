import 'package:covidtrace/code_pin.dart';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/info_card.dart';
import 'package:covidtrace/operator.dart';
import 'package:covidtrace/verify_phone.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'state.dart';

class SendReport extends StatefulWidget {
  SendReport({Key key}) : super(key: key);

  @override
  SendReportState createState() => SendReportState();
}

class SendReportState extends State<SendReport> with TickerProviderStateMixin {
  var _loading = false;
  var _step = 0;
  var _verificationCode = '';
  bool _expandHeader = false;
  AnimationController expandController;
  CurvedAnimation animation;

  void initState() {
    super.initState();
    expandController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 200));
    animation =
        CurvedAnimation(parent: expandController, curve: Curves.fastOutSlowIn);

    Provider.of<AppState>(context, listen: false).addListener(onStateChange);
  }

  void onStateChange() async {
    AppState state = Provider.of<AppState>(context, listen: false);
    if (state.report != null) {
      expandController.forward();
      setState(() => _expandHeader = true);
    }
  }

  void onSubmit(context, AppState state) async {
    if (!await sendReport(state)) {
      Scaffold.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('There was an error submitting your report')));
    } else {
      Scaffold.of(context).showSnackBar(
          SnackBar(content: Text('Your report was successfully submitted')));
    }
  }

  Future<bool> sendReport(AppState state) async {
    setState(() => _loading = true);
    var success = await state.sendReport(_verificationCode);
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

  void onCodeChange(context, String code) {
    setState(() => _verificationCode = code);

    if (codeComplete) {
      FocusScope.of(context).unfocus();
    }
  }

  bool get codeComplete => _verificationCode.length == 8;

  List<Widget> getHeading(String title) {
    var textTheme = Theme.of(context).textTheme;
    var subhead = Theme.of(context)
        .textTheme
        .subtitle1
        .merge(TextStyle(fontWeight: FontWeight.bold));

    var authority = Config.get()["healthAuthority"];

    return [
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
  }

  Widget buildReportedView(BuildContext context, AppState state) {
    var config = Config.get();
    var theme = config['theme']['dashboard'];

    var bgColor = Color(int.parse(theme['reported_background']));
    var textColor = Color(int.parse(theme['reported_text']));
    var alertText = TextStyle(color: textColor);

    return Padding(
      padding: EdgeInsets.only(left: 15, right: 15),
      child: ListView(children: [
        SizedBox(height: 15),
        Container(
          decoration: BoxDecoration(
              color: bgColor, borderRadius: BorderRadius.circular(10)),
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
                children: [
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Report Submitted',
                              style: Theme.of(context)
                                  .textTheme
                                  .headline6
                                  .merge(alertText)),
                          SizedBox(height: 2),
                          Text(
                              'On ${DateFormat.yMMMd().add_jm().format(state.report.timestamp)}',
                              style: alertText)
                        ])),
                    Image.asset('assets/clinic_medical_icon.png',
                        height: 40, color: textColor),
                  ]),
                  SizeTransition(
                      child: Column(children: [
                        Divider(height: 20, color: textColor),
                        Text(
                            'Thank you for submitting your anonymized exposure history. Your data will help people at risk respond faster.',
                            style: alertText)
                      ]),
                      axisAlignment: 1.0,
                      sizeFactor: animation),
                ],
              ),
            ),
          ),
        ),
        ...getHeading('What To Do Next'),
        ...Config.get()["faqs"]["reported"].map((item) => InfoCard(item: item)),
        SizedBox(height: 10),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    var enableContinue = true;
    var textTheme = Theme.of(context).textTheme;
    var stepTextTheme = textTheme.subtitle1;

    return Consumer<AppState>(
      builder: (context, state, _) {
        if (state.report != null) {
          return Scaffold(body: buildReportedView(context, state));
        }

        return Scaffold(
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Builder(builder: (context) {
              return SingleChildScrollView(
                child: Column(children: [
                  Stepper(
                      physics: NeverScrollableScrollPhysics(),
                      currentStep: _step,
                      onStepContinue: () => setState(() => _step++),
                      onStepTapped: (index) {
                        setState(() => _step = index);
                      },
                      onStepCancel: () =>
                          _step == 0 ? null : setState(() => _step--),
                      controlsBuilder: (context,
                          {onStepContinue, onStepCancel}) {
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
                              Text('Notify Others', style: textTheme.headline6),
                          content: Text(
                              'If you have tested postive for COVID-19, anonymously sharing your diagnosis will help your community contain the spread of the virus.\n\nThis submission is optional.',
                              style: stepTextTheme),
                        ),
                        Step(
                            isActive: _step == 1,
                            state: _step > 1
                                ? StepState.complete
                                : StepState.indexed,
                            title: Text('What Will Be Shared',
                                style: textTheme.headline6),
                            content: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'The random IDs generated by your phone and anonymously exchanged with others you have interacted with over the last 14 days will be shared.\n\nThis app neither collects nor shares any user identifiable information.',
                                      style: stepTextTheme),
                                ])),
                        Step(
                            isActive: _step == 2,
                            title: Text('Verify Diagnosis',
                                style: textTheme.headline6),
                            content: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Enter the verification code provided by your health official to submit your report.',
                                      style: stepTextTheme),
                                  CodePin(
                                      size: 8,
                                      onChange: (value) =>
                                          onCodeChange(context, value)),
                                  SizedBox(height: 10),
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
                                            onPressed: codeComplete
                                                ? () => onSubmit(context, state)
                                                : null),
                                      ]),
                                ])),
                      ])
                ]),
              );
            }),
          ),
        );
      },
    );
  }
}
