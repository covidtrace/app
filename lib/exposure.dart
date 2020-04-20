import 'package:covidtrace/storage/beacon.dart';
import 'package:covidtrace/storage/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:s2geometry/s2geometry.dart';

/// Exposure is a convenience class that provides a consistent API for
/// information about an exposure event whether it be location or beacon
/// based.
class Exposure {
  static const LOCATION = 'location';
  static const BEACON = 'beacon';

  BeaconModel _beacon;
  LocationModel _location;

  Exposure(dynamic item) {
    if (item is BeaconModel) {
      _beacon = item;
    } else if (item is LocationModel) {
      _location = item;
    } else {
      throw ('Exposure must be initialized from either a LocationModel or BeaconModel');
    }
  }

  static Future<Exposure> getOne(
      {bool newest = true, bool exposure = true}) async {
    var date = DateTime.now().subtract(Duration(days: 21));
    var timestamp = DateFormat('yyyy-MM-dd').format(date);
    var sort = newest ? 'DESC' : 'ASC';

    var results = await Future.wait([
      BeaconModel.findAll(
          limit: 1,
          where: 'DATE(start) > DATE(?) AND exposure = ?',
          whereArgs: [timestamp, exposure ? 1 : 0],
          orderBy: 'end $sort'),
      LocationModel.findAll(
          limit: 1,
          where: 'DATE(timestamp) > DATE(?) AND exposure = ?',
          whereArgs: [timestamp, exposure ? 1 : 0],
          orderBy: 'timestamp $sort'),
    ]);

    var beacons = results[0];
    var locations = results[1];

    return beacons.isNotEmpty
        ? Exposure(beacons.first)
        : locations.isNotEmpty ? Exposure(locations.first) : null;
  }

  static Future<Exposure> get newest => getOne();
  static Future<Exposure> get oldest => getOne(newest: false);

  String get type => _beacon != null ? BEACON : LOCATION;

  BeaconModel get beacon => _beacon;
  LocationModel get location => _beacon?.location ?? _location;

  double get latitude => location?.latitude;
  double get longitude => location?.longitude;
  LatLng get latlng => location != null ? LatLng(latitude, longitude) : null;

  S2CellId get cellID => location?.cellID;

  DateTime get start {
    return beacon?.start ?? location.timestamp;
  }

  DateTime get end {
    // For location exposures we default to same duration granularity that is reported
    // when self reporting
    return beacon?.end ?? start.add(Duration(hours: 1));
  }

  Duration get duration => end.difference(start);

  bool get reported => beacon?.reported ?? location.reported;

  set reported(bool report) {
    if (beacon != null) {
      beacon.reported = true;
      beacon.location?.reported = true;
    } else {
      location.reported = true;
    }
  }

  bool get exposure => beacon?.exposure ?? location.exposure;

  set exposure(bool report) {
    if (beacon != null) {
      beacon.exposure = true;
      beacon.location?.exposure = true;
    } else {
      location.exposure = true;
    }
  }

  Future<int> save() => beacon?.save() ?? location.save();
}
