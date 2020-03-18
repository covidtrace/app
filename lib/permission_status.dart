import 'package:flutter/material.dart';
import 'package:location/location.dart';

class PermissionStatusWidget extends StatefulWidget {
  PermissionStatusWidget({Key key}) : super(key: key);

  @override
  _PermissionStatusState createState() => _PermissionStatusState();
}

class _PermissionStatusState extends State<PermissionStatusWidget> {
  final Location location = new Location();

  bool _permissionGranted;

  static void backgroundCallback(List<LocationData> locations) {
    print('Location data received from background: $locations');
  }

  _checkPermissions() async {
    try {
      bool permission = await location.hasPermission();
      setState(() {
        _permissionGranted = permission;
      });
    } catch (err) {
      print(err);
    }
  }

  _requestPermission() async {
    if (!_permissionGranted) {
      try {
        bool permission = await location.requestPermission();
        setState(() {
          _permissionGranted = permission;
        });
        if (permission) {
          bool status =
              await location.registerBackgroundLocation(backgroundCallback);
          print('statusBackgroundLocation: $status');
        }
      } catch (err) {
        print(err);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Permission status: ${_permissionGranted ?? "unknown"}',
          style: Theme.of(context).textTheme.body2,
        ),
        Row(
          children: <Widget>[
            Container(
              margin: EdgeInsets.only(right: 42),
              child: RaisedButton(
                child: Text("Check"),
                onPressed: _checkPermissions,
              ),
            ),
            RaisedButton(
              child: Text("Request"),
              onPressed: _permissionGranted == true ? null : _requestPermission,
            )
          ],
        )
      ],
    );
  }
}
