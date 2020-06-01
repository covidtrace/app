import 'dart:async';
import 'dart:convert';

import 'package:covidtrace/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
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

  static const SEARCH_URL =
      'https://my.castlighthealth.com/corona-virus-testing-sites/data/result.php';

  static const RESULTS_URL =
      'https://my.castlighthealth.com/corona-virus-testing-sites/data/result.php';

  static const IMAGE_PREFIX =
      'https://my.castlighthealth.com/corona-virus-testing-sites/images';

  static const USER_AGENT =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/81.0.4044.138 Safari/537.36';

  String _webViewContent = '';
  bool _loaded = false;
  bool _showingSheet = false;
  List<String> _counties = [];
  String _selectedCounty;

  void selectCounty(String value) async {
    Navigator.pop(context, value);

    setState(() {
      _selectedCounty = value;
      _loaded = false;
    });

    loadFacilities();
  }

  void showCountySheet(context) async {
    if (_showingSheet) {
      return;
    }
    _showingSheet = true;

    await loadCounties();
    var selected = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          maxChildSize: .9,
          expand: false,
          builder: (context, scroller) => Container(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(15),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(
                        'Choose A County',
                        style: Theme.of(context)
                            .textTheme
                            .subtitle1
                            .merge(TextStyle(fontWeight: FontWeight.bold)),
                      )),
                      Material(
                        color: Colors.grey[300],
                        clipBehavior: Clip.antiAlias,
                        shape: CircleBorder(),
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(Icons.close, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scroller,
                    itemCount: _counties.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        onTap: () => selectCounty(_counties[index]),
                        title: Text(_counties[index]),
                      );
                    },
                    separatorBuilder: (context, index) {
                      return Divider(height: 0);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null && _webViewContent.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  Future<void> loadCounties() async {
    var config = Config.get()['test_facilities'];
    var url = Uri.parse('$RESULTS_URL?state_key=${config['state']}');

    var response = await http.get(url.toString());
    if (response.statusCode != 200) {
      print(response.body);
      return;
    }

    var optionRe =
        RegExp(r'<option value=[^>]+>([^<]+?)</option>', multiLine: true);
    var matches = optionRe
        .allMatches(response.body)
        .where((m) => m.groupCount > 0 && m.group(1).toLowerCase() != 'all')
        .map((m) => m.group(1));

    setState(() {
      _counties = matches.toList();
    });
  }

  Future<void> loadFacilities() async {
    var config = Config.get()['test_facilities'];
    var url = Uri.parse(
        '$RESULTS_URL?county=$_selectedCounty&state=${config['state']}');
    var response = await http.get(url.toString());
    if (response.statusCode != 200) {
      print(response.body);
      setState(() {
        _webViewContent = '';
      });
      return;
    }

    var imageRe = RegExp(r'\.\/images', multiLine: true);
    String sanitized = '';
    try {
      sanitized = response.body.replaceAll(imageRe, IMAGE_PREFIX);
    } catch (err) {
      sanitized = 'Oops something went wrong';
    }

    setState(() {
      _webViewContent = sanitized;
    });

    var cssFiles = config['css'] as List<dynamic>;
    var cssContent = await Future.wait(
        cssFiles.map((name) => rootBundle.loadString(name, cache: false)));

    var page = '''
      <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>${cssContent.join('\n')}</style>
        </head>
        <body>$_webViewContent</body>
      </html>
    ''';

    var controller = await _controller.future;
    controller.loadUrl(Uri.dataFromString(
      page,
      mimeType: 'text/html',
      encoding: Encoding.getByName('utf-8'),
    ).toString());
  }

  void onPageFinished(String url) async {
    // Make sure initial page is not shown before fade in
    await Future.delayed(Duration(milliseconds: 100));
    setState(() {
      _loaded = true;
    });
  }

  void onWebViewCreated(WebViewController controller) async {
    print('onWebViewCreated');
    if (!_controller.isCompleted) {
      _controller.complete(controller);
    }
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
    showCountySheet(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Find A Test Facility'),
        actions: [
          IconButton(
            onPressed: () {
              _showingSheet = false;
              showCountySheet(context);
            },
            icon: Icon(Icons.search, color: Colors.white),
          )
        ],
      ),
      body: Stack(
        children: [
          if (_selectedCounty != null)
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
          if (!_loaded && _selectedCounty != null)
            Positioned.fill(child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
