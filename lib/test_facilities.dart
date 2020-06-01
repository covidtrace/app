import 'dart:async';
import 'dart:convert';

import 'package:covidtrace/config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock/wakelock.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TestFacilities extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => TestFacilitiesState();
}

class TestFacilitiesState extends State with TickerProviderStateMixin {
  final Completer<WebViewController> _controller =
      Completer<WebViewController>();

  // Needed to get cookies so that subsequent requests are not blocked
  static const INITIAL_URL =
      'https://my.castlighthealth.com/corona-virus-testing-sites';

  static const RESULTS_URL =
      'https://my.castlighthealth.com/corona-virus-testing-sites/data/result.php';

  static const IMAGE_PREFIX =
      'https://my.castlighthealth.com/corona-virus-testing-sites/images';

  static const USER_AGENT =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/81.0.4044.138 Safari/537.36';

  String _webViewContent = '';
  bool _loaded = false;

  Future<void> loadData() async {
    var config = Config.get()['test_facilities'];
    var url = Uri.parse(
        '$RESULTS_URL?county=${config['county']}&state=${config['state']}');

    var response = await http.get(url.toString());
    if (response.statusCode != 200) {
      print(response.body);
      setState(() {
        _webViewContent = '';
      });
      return;
    }

    var imageRe = RegExp(r'\.\/images', multiLine: true);
    setState(() {
      _webViewContent = response.body.replaceAll(imageRe, IMAGE_PREFIX);
    });
  }

  void onPageFinished(String url) async {
    // Make sure initial page is not shown before fade in
    await Future.delayed(Duration(milliseconds: 100));
    setState(() {
      _loaded = true;
    });
  }

  void onWebViewCreated(WebViewController controller) async {
    if (!_controller.isCompleted) {
      _controller.complete(controller);
    }

    var cssFiles = Config.get()['test_facilities']['css'] as List<dynamic>;
    var cssContent = await Future.wait(
        cssFiles.map((name) => rootBundle.loadString(name, cache: false)));

    await loadData();
    var page = base64Encode(utf8.encode('''
      <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>${cssContent.join('\n')}</style>
        </head>
        <body>$_webViewContent</body>
      </html>
    '''));
    controller.loadUrl('data:text/html;base64,$page');
  }

  NavigationDecision navigationDelegate(NavigationRequest request) {
    if (!_loaded) {
      return NavigationDecision.navigate;
    }

    var url = request.url;
    var isMapLink = url.contains(new RegExp(r'maps\.google\.com'));
    if (!isMapLink) {
      launch(url);
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Test Facilities')),
      body: Stack(
        children: [
          AnimatedOpacity(
            opacity: _loaded ? 1 : 0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            child: WebView(
              initialUrl: INITIAL_URL,
              onWebViewCreated: onWebViewCreated,
              onPageFinished: onPageFinished,
              javascriptMode: JavascriptMode.unrestricted,
              navigationDelegate: navigationDelegate,
              userAgent: USER_AGENT,
            ),
          ),
          if (!_loaded)
            Positioned.fill(child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
