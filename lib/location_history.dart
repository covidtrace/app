import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'storage/location.dart';

class LocationHistory extends StatefulWidget {
  LocationHistory({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => LocationHistoryState();
}

class LocationHistoryState extends State<LocationHistory> {
  var _counts = [];

  @override
  void initState() {
    super.initState();
    update();
  }

  Future<void> update() async {
    var results = await LocationModel.findAllRaw(
        orderBy: 'timestamp DESC',
        groupBy: 'DATE(timestamp, \'localtime\')',
        columns: [
          'COUNT(id) as count',
          'DATE(timestamp, \'localtime\') as timestamp'
        ]);
    print(results);

    setState(() => _counts = results);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
        onRefresh: update,
        child: ListView(
            children: ListTile.divideTiles(
                context: context,
                tiles: _counts.map<Widget>((item) {
                  var date = DateTime.parse(item['timestamp']);
                  return ListTile(
                    trailing: Text('${item['count']}',
                        style: Theme.of(context).textTheme.title),
                    subtitle: Text('${DateFormat.MMMd().format(date)}'),
                    title: Text('${DateFormat.E().format(date)}'),
                  );
                })).toList()));
  }
}
