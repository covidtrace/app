import 'dart:io';

import 'package:covidtrace/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PrivacyPolicy extends StatefulWidget {
  @override
  PrivacyPolicyState createState() => PrivacyPolicyState();
}

class PrivacyPolicyState extends State<PrivacyPolicy> {
  File _file;

  @override
  void initState() {
    super.initState();

    loadPolicy();
  }

  void loadPolicy() async {
    String privacyLink =
        Config.get()['onboarding']['privacy']['privacy_policy'];
    var data = await rootBundle.load(privacyLink);
    var dir = await getApplicationDocumentsDirectory();
    var file = File('${dir.path}/${privacyLink.split('/')[1]}');

    await file.writeAsBytes(data.buffer.asUint8List());
    setState(() {
      _file = file;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text('Privacy Policy'),
        ),
        body: _file != null
            ? WebView(initialUrl: _file.uri.toString())
            : Container());
  }
}
