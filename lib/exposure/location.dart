import 'package:covidtrace/exposure/exposure.dart';
import 'package:covidtrace/helper/datetime.dart';
import 'package:covidtrace/storage/location.dart';
import 'package:csv/csv.dart';

class LocationExposure extends Exposure<LocationModel> {
  Map<String, Map<int, List<LocationModel>>> _lookup;

  LocationExposure(List<LocationModel> locations, int level)
      : super(locations) {
    locations.forEach((location) {
      var timestamp = ceilUnixSeconds(location.timestamp, 60);
      var cellID = location.cellID.parent(level).toToken();
      if (_lookup[cellID] == null) {
        _lookup[cellID] = new Map();
      }
      if (_lookup[cellID][timestamp] == null) {
        _lookup[cellID][timestamp] = [];
      }
      _lookup[cellID][timestamp].add(location);
    });
  }

  @override
  Future<List<LocationModel>> getExposures(String data) async {
    var rows =
        CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(data);

    var exposures = List<LocationModel>();

    await Future.forEach(rows, (row) async {
      var timestamp = ceilUnixSeconds(
          DateTime.fromMillisecondsSinceEpoch(int.parse(row[0]) * 1000), 60);

      // Note: aggregate point CSVs look like [timestamp, cellID, verified]
      String cellID = row[1];

      var locationsbyTimestamp = _lookup[cellID];
      if (locationsbyTimestamp != null) {
        var locations = locationsbyTimestamp[timestamp];
        if (locations != null) {
          exposures.addAll(locations);
        }
      }
    });

    return exposures;
  }
}
