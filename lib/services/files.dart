import 'package:flutter/services.dart';

const _ch = MethodChannel('vidyadesk/files');

/// Saves a file in the phone's Download/VidyaDesk folder.
/// Returns a link the app can open (null on very old phones), or throws
/// PlatformException with code "need_permission" when storage access must be allowed first.
Future<String?> saveToDownloads(Uint8List bytes, String name, String mime) async {
  final r = await _ch.invokeMethod<String>('save', {'name': name, 'mime': mime, 'bytes': bytes});
  if (r == null || r.startsWith('path:')) return null;
  return r;
}

/// Opens a saved file in a viewer app (PDF reader, Excel, Sheets…).
Future<bool> openSaved(String uri, String mime) async {
  try {
    return await _ch.invokeMethod<bool>('open', {'uri': uri, 'mime': mime}) ?? false;
  } catch (_) {
    return false;
  }
}
