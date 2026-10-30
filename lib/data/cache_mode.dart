import 'dart:async';

/// "Phone copy first": while true, the backend reads only what is already
/// saved on the phone (no internet wait). Used to show a page instantly;
/// fresh data from the server follows right after.
bool get cacheOnly => Zone.current[#vdCacheOnly] == true;

Future<T> runCacheOnly<T>(Future<T> Function() f) => runZoned(f, zoneValues: {#vdCacheOnly: true});

/// Thrown when something is not saved on the phone yet.
class CacheMiss implements Exception {
  const CacheMiss();
}
