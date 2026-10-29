import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Why we could not get the phone's location.
enum LocError { serviceOff, denied, deniedForever, mocked, timeout }

class LocResult {
  const LocResult({this.lat = 0, this.lng = 0, this.accuracy = 0, this.error});
  final double lat, lng, accuracy;
  final LocError? error;
  bool get ok => error == null;
}

/// Asks for permission if needed and reads the current GPS position.
Future<LocResult> currentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return const LocResult(error: LocError.serviceOff);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) return const LocResult(error: LocError.deniedForever);
    if (perm == LocationPermission.denied) return const LocResult(error: LocError.denied);
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
    // A "fake GPS" app must not be used to check in from home.
    if (p.isMocked) return const LocResult(error: LocError.mocked);
    return LocResult(lat: p.latitude, lng: p.longitude, accuracy: p.accuracy);
  } catch (_) {
    return const LocResult(error: LocError.timeout);
  }
}

Future<void> openLocationSettings() async {
  try {
    await Geolocator.openLocationSettings();
  } catch (_) {}
}

Future<void> openAppSettings() async {
  try {
    await Geolocator.openAppSettings();
  } catch (_) {}
}

/// Distance in metres between two points.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

String distanceText(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
