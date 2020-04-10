import 'package:covidtrace/exposure/exposure.dart';
import 'package:covidtrace/helper/datetime.dart';
import 'package:covidtrace/storage/beacon.dart';
import 'package:csv/csv.dart';

class BeaconExposure extends Exposure<BeaconUuid> {
  // Maps uuid => beacons
  Map<String, List<BeaconUuid>> _lookup;

  BeaconExposure(List<BeaconUuid> beacons, int level) : super(beacons) {
    beacons.forEach((beacon) {
      _lookup[beacon.uuid] ??= new List();
      _lookup[beacon.uuid].add(beacon);
    });
  }

  @override
  Future<List<BeaconUuid>> getExposures(String data) async {
    var exposures = List<BeaconUuid>();

    var rows =
        CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(data);

    // Note: `row` looks like [timestamp, uuid, cellID]
    rows.forEach((row) async {
      var timestamp = ceilUnixSeconds(
          DateTime.fromMillisecondsSinceEpoch(int.parse(row[0]) * 1000), 60);

      String uuid = row[1];
      String cellID = row[2];

      var beacons = _lookup[uuid];
      if (beacons != null) {
        exposures.addAll(beacons.where((beacon) {
          // TODO(Wes) extra logic here to filter out dupes, etc.
          return true;
        }));
      }
    });

    return exposures;
  }
}
