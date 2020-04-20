import 'package:covidtrace/exposure/exposure.dart';
import 'package:covidtrace/storage/beacon.dart';
import 'package:csv/csv.dart';

class BeaconExposure extends Exposure<BeaconModel> {
  // TODO(wes): Make exposure duration configurable?
  static const EXPOSURE_DURATION = Duration(minutes: 5);

  // Maps uuid => beacons
  Map<String, List<BeaconModel>> _lookup = {};

  BeaconExposure(List<BeaconModel> beacons, int level) : super(beacons) {
    beacons.forEach((beacon) {
      _lookup[beacon.uuid] ??= new List();
      _lookup[beacon.uuid].add(beacon);
    });
  }

  @override
  Future<List<BeaconModel>> getExposures(String data) async {
    var exposures = List<BeaconModel>();

    var rows =
        CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(data);

    // Note: `row` looks like [timestamp, uuid, cellID]
    rows.forEach((row) {
      String uuid = row[1];
      var beacons = _lookup[uuid] ?? [];
      exposures.addAll(beacons.where(
          (b) => b.end.difference(b.start).compareTo(EXPOSURE_DURATION) >= 0));
    });

    return exposures;
  }
}
