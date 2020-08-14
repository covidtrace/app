import 'package:covidtrace/code_pin.dart';
import 'package:covidtrace/config.dart';
import 'package:covidtrace/info_card.dart';
import 'package:covidtrace/intl.dart' as locale;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'state.dart';

class PinState extends ChangeNotifier {
  String _pin;

  String get pin => _pin;

  void onChange(String value) {
    _pin = value;
    notifyListeners();
  }

  void reset() {
    _pin = '';
    notifyListeners();
  }
}

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
  var _pinState = PinState();
  AnimationController expandController;
  CurvedAnimation animation;

  void initState() {
    super.initState();
    expandController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 200));
    animation =
        CurvedAnimation(parent: expandController, curve: Curves.fastOutSlowIn);

    _pinState.addListener(() => onCodeChange(_pinState.pin));
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
    var intl = locale.Intl.of(context);
    var err = await sendReport(state);

    if (err != null) {
      Scaffold.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(
              intl.get('report.submit.error', args: [intl.get(err.trim())]))));
    } else {
      Scaffold.of(context).showSnackBar(
          SnackBar(content: Text(intl.get('report.submit.success'))));
    }
  }

  Future<String> sendReport(AppState state) async {
    setState(() => _loading = true);
    var error;
    try {
      await state.sendReport(_verificationCode);
    } catch (err) {
      error = err is String ? err : 'errors.no_connection';
    }

    setState(() => _loading = false);

    if (error != null) {
      _pinState.reset();
    }

    return error;
  }

  void onCodeChange(String code) {
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
      Center(
          child: Text(locale.Intl.of(context).get(authority['name']),
              style: textTheme.caption)),
      SizedBox(height: 10),
      Center(child: Text(title, style: subhead)),
      SizedBox(height: 10),
    ];
  }

  Widget buildReportedView(BuildContext context, AppState state) {
    var intl = locale.Intl.of(context);
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
                          Text(intl.get('report.submitted.notice.title'),
                              style: Theme.of(context)
                                  .textTheme
                                  .headline6
                                  .merge(alertText)),
                          SizedBox(height: 2),
                          Text(
                              intl.get('report.submitted.notice.date', args: [
                                DateFormat.yMMMd()
                                    .add_jm()
                                    .format(state.report.timestamp)
                              ]),
                              style: alertText)
                        ])),
                    Image.asset('assets/clinic_medical_icon.png',
                        height: 40, color: textColor),
                  ]),
                  SizeTransition(
                      child: Column(children: [
                        Divider(height: 20, color: textColor),
                        Text(intl.get('report.submitted.notice.body'),
                            style: alertText)
                      ]),
                      axisAlignment: 1.0,
                      sizeFactor: animation),
                ],
              ),
            ),
          ),
        ),
        ...getHeading(intl.get('report.submitted.faqs.title')),
        ...config["faqs"]["reported"].map((item) => InfoCard(item: item)),
        SizedBox(height: 10),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    var intl = locale.Intl.of(context);
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
                                        child: Text(intl.get(
                                            'report.submit.steps_$_step.cta'))),
                                  ])
                            : SizedBox.shrink();
                      },
                      steps: [
                        Step(
                          isActive: _step == 0,
                          state: _step > 0
                              ? StepState.complete
                              : StepState.indexed,
                          title: Text(intl.get('report.submit.steps_0.title'),
                              style: textTheme.headline6),
                          content: Text(intl.get('report.submit.steps_0.body'),
                              style: stepTextTheme),
                        ),
                        Step(
                            isActive: _step == 1,
                            state: _step > 1
                                ? StepState.complete
                                : StepState.indexed,
                            title: Text(intl.get('report.submit.steps_1.title'),
                                style: textTheme.headline6),
                            content: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(intl.get('report.submit.steps_1.body'),
                                      style: stepTextTheme),
                                ])),
                        Step(
                            isActive: _step == 2,
                            title: Text(intl.get('report.submit.steps_2.title'),
                                style: textTheme.headline6),
                            content: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(intl.get('report.submit.steps_2.body'),
                                      style: stepTextTheme),
                                  CodePin(size: 8, pinState: _pinState),
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
                                                : Text(intl.get(
                                                    'report.submit.steps_2.cta')),
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
