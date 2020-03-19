import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

class AppModel extends ChangeNotifier {
  final List<LatLng> _locations = [];

  UnmodifiableListView<LatLng> get items => UnmodifiableListView(_locations);

  void add(LatLng item) {
    _locations.add(item);
    notifyListeners();
  }

  void removeAll() {
    _locations.clear();
    notifyListeners();
  }
}

final model = AppModel();

void backgroundCallback(List<LocationData> locations) async {
  locations.forEach((l) {
    model.add(LatLng(l.longitude, l.latitude));
  });

  print('Total locations ${model.items.length}');
}
