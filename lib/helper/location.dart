import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:google_maps_flutter/google_maps_flutter.dart';

Future<LatLng> locateCurrentPosition() async {
  // Get current positon to show on map for marking home
  var current = await bg.BackgroundGeolocation.getCurrentPosition(
      timeout: 15, maximumAge: 10000);
  var latlng = LatLng(current.coords.latitude, current.coords.longitude);

  return latlng;
}
