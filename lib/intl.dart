import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Intl {
  Intl(this.locale);

  final Locale locale;

  static Intl of(BuildContext context) {
    return Localizations.of<Intl>(context, Intl);
  }

  Map<String, dynamic> _localizedValues = {};

  String get(str, {List<String> args}) {
    if (!_localizedValues.containsKey(str)) {
      return '<$str>';
    }

    if (args == null) {
      return _localizedValues[str];
    }

    String raw = _localizedValues[str];
    args.asMap().forEach((index, value) {
      var re = new RegExp(r'\$' + index.toString());
      raw = raw.replaceAll(re, value);
    });
    return raw;
  }

  Future<void> load() async {
    try {
      String data = await rootBundle
          .loadString('assets/locale/${locale.languageCode}.json');
      _localizedValues = jsonDecode(data);
    } catch (err) {
      print(err);
    }
  }
}

class IntlDelegate extends LocalizationsDelegate<Intl> {
  const IntlDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'es'].contains(locale.languageCode);

  @override
  Future<Intl> load(Locale locale) async {
    var localization = Intl(locale);
    await localization.load();

    return localization;
  }

  @override
  bool shouldReload(IntlDelegate old) => false;
}
