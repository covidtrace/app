import 'dart:io';

import 'package:covidtrace/intl.dart';
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

  void loadPolicy() async {
    String privacyLink = Intl.of(context).get('privacy_policy.content');
    var data = await rootBundle.load(privacyLink);
    var dir = await getApplicationDocumentsDirectory();
    var file = File('${dir.path}/${privacyLink.split('/').last}');

    await file.writeAsBytes(data.buffer.asUint8List());
    setState(() {
      _file = file;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_file == null) {
      loadPolicy();
    }

    return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(Intl.of(context).get('privacy_policy.title')),
        ),
        body: _file != null
            ? WebView(initialUrl: _file.uri.toString())
            : Container());
  }
}
