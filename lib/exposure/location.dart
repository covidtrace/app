import 'package:covidtrace/exposure/exposure.dart';
import 'package:covidtrace/helper/datetime.dart';
import 'package:covidtrace/storage/location.dart';
import 'package:csv/csv.dart';

class LocationExposure extends Exposure<LocationModel> {
  Map<String, Map<int, List<LocationModel>>> _lookup = {};
  Duration _timeResolution;

  LocationExposure(
      List<LocationModel> locations, int level, Duration timeResolution)
      : super(locations) {
    _timeResolution = timeResolution;
    locations.forEach((location) {
      var timestamp =
          ceilUnixSeconds(location.timestamp, _timeResolution.inMinutes);
      var cellID = location.cellID.parent(level).toToken();
      _lookup[cellID] ??= new Map();
      _lookup[cellID][timestamp] ??= [];
      _lookup[cellID][timestamp].add(location);
    });
  }

  @override
  Future<List<LocationModel>> getExposures(String data) async {
    var exposures = List<LocationModel>();

    var rows =
        CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(data);

    // Note: `row` looks like [timestamp, cellID, verified]
    rows.forEach((row) {
      var timestamp = ceilUnixSeconds(
          DateTime.fromMillisecondsSinceEpoch(int.parse(row[0]) * 1000),
          _timeResolution.inMinutes);
      String cellID = row[1];

      var locationsbyTimestamp = _lookup[cellID];
      if (locationsbyTimestamp != null) {
        var locations = locationsbyTimestamp[timestamp];
        exposures.addAll(locations ?? []);
      }
    });

    return exposures;
  }
}
