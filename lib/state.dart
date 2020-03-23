import 'package:flutter/foundation.dart';
import 'storage/user.dart';

class AppState extends ChangeNotifier {}

class SettingsState with ChangeNotifier {
  static UserModel _user = UserModel(trackLocation: false);

  SettingsState() {
    UserModel.find().then((user) {
      _user = user;
      notifyListeners();
    });
  }

  UserModel getUser() {
    return _user;
  }

  Future<void> setUser(user) async {
    _user = user;
    _user.save();
    notifyListeners();
  }
}

class ReportState extends ChangeNotifier {
  static final Map<String, dynamic> defaults = {
    'fever': false,
    'cough': false,
    'breathing': false,
    'days': 1.0,
    'gender': null,
    'age': null,
    'tested': null
  };

  final Map<String, dynamic> state = {};

  ReportState() {
    state.addAll(defaults);
  }

  Map<String, dynamic> getAll() {
    return state;
  }

  dynamic get(String key) {
    return state[key];
  }

  void set(Map<String, dynamic> changes) {
    state.addAll(changes);
    notifyListeners();
  }

  void reset() {
    state.removeWhere((key, value) => true);
    state.addAll(defaults);
    notifyListeners();
  }
}
