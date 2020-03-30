import 'package:covidtrace/operator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class VerifyPhone extends StatefulWidget {
  VerifyPhone({Key key}) : super(key: key);

  @override
  VerifyPhoneState createState() => VerifyPhoneState();
}

class VerifyPhoneState extends State with SingleTickerProviderStateMixin {
  final _phoneForm = GlobalKey<FormState>();
  final _codeForm = GlobalKey<FormState>();
  final phoneController = TextEditingController();
  final codeController = TextEditingController();
  FocusNode codeFocus;
  AnimationController slideController;
  var animation;
  String _phoneToken;
  String _phoneError;
  String _codeError;
  bool _loading = false;

  void initState() {
    super.initState();
    codeFocus = FocusNode();
    slideController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 500));
    animation = Tween<Offset>(begin: Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: slideController, curve: Curves.fastOutSlowIn));
  }

  @override
  void dispose() {
    codeFocus.dispose();
    slideController.dispose();
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  Future<void> requestCode(String number) async {
    setState(() => _loading = true);
    var token = await Operator.init(number);
    setState(() => _loading = false);

    if (token == null) {
      setState(() => _phoneError = 'There was an error requesting a code');
      return;
    }

    _phoneToken = token;
    slideController.forward();
    codeFocus.requestFocus();
  }

  Future<void> verifyCode(String code) async {
    setState(() => _loading = true);
    var token = await Operator.verify(_phoneToken, code);
    setState(() => _loading = false);

    if (token == null) {
      setState(() => _codeError = 'The code provided was incorrect');
      codeController.text = '';
      return;
    }

    if (token.valid) {
      Navigator.pop(context, token);
    } else {
      setState(() => _codeError = 'Something went wrong');
      codeController.text = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;
    var bodyText = textTheme.subhead.merge(TextStyle(height: 1.4));

    var loadIndicator = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
            strokeWidth: 2,
            value: null,
            valueColor: AlwaysStoppedAnimation(
                Theme.of(context).textTheme.button.color)));

    return SingleChildScrollView(
        child: Padding(
            padding: EdgeInsets.only(
                top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
            child: Stack(children: [
              Padding(
                  padding: EdgeInsets.symmetric(horizontal: 30),
                  child: Form(
                      key: _phoneForm,
                      child: Column(children: [
                        Text(
                            'We need to verify your app the first time you submit data. Enter your phone number to receive a verification code.',
                            style: bodyText),
                        TextFormField(
                            autofocus: true,
                            decoration: InputDecoration(
                                labelText: 'Phone number',
                                errorText: _phoneError),
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            onChanged: (value) =>
                                setState(() => _phoneError = null),
                            validator: (String value) {
                              if (value.isEmpty) {
                                return 'Please enter a valid US phone number';
                              }
                              return null;
                            }),
                        SizedBox(height: 20),
                        RaisedButton(
                            onPressed: () {
                              if (_phoneForm.currentState.validate()) {
                                requestCode(phoneController.text);
                              }
                            },
                            child: _loading ? loadIndicator : Text('Submit')),
                      ]))),
              Positioned.fill(
                  child: SlideTransition(
                      position: animation,
                      child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 30),
                          child: Material(
                              child: Form(
                            key: _codeForm,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Enter the code sent to your phone',
                                    style: bodyText, textAlign: TextAlign.left),
                                TextFormField(
                                    focusNode: codeFocus,
                                    decoration: InputDecoration(
                                        labelText: 'Code',
                                        errorText: _codeError),
                                    controller: codeController,
                                    keyboardType: TextInputType.number,
                                    onChanged: (value) {
                                      setState(() => _codeError = null);
                                      if (value.length == 6 &&
                                          _codeForm.currentState.validate()) {
                                        verifyCode(codeController.text);
                                      }
                                    },
                                    validator: (String value) {
                                      if (value.isEmpty) {
                                        return 'Please enter a valid code';
                                      }
                                      return null;
                                    }),
                                SizedBox(height: 20),
                                Center(
                                    child: RaisedButton(
                                        onPressed: () {
                                          if (_codeForm.currentState
                                              .validate()) {
                                            verifyCode(codeController.text);
                                          }
                                        },
                                        child: _loading
                                            ? loadIndicator
                                            : Text('Submit'))),
                              ],
                            ),
                          ))))),
            ])));
  }
}
