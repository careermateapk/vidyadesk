import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Turns a Google Drive / Docs / Sheets / Slides share link into a direct
/// download link. Other links are returned as they are.
String directDownloadUrl(String url) {
  var u = url.trim();
  if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
  final doc = RegExp(r'docs\.google\.com/(document|spreadsheets|presentation)/d/([A-Za-z0-9_-]{10,})').firstMatch(u);
  if (doc != null) {
    final id = doc.group(2);
    switch (doc.group(1)) {
      case 'document':
        return 'https://docs.google.com/document/d/$id/export?format=pdf';
      case 'spreadsheets':
        return 'https://docs.google.com/spreadsheets/d/$id/export?format=xlsx';
      default:
        return 'https://docs.google.com/presentation/d/$id/export/pdf';
    }
  }
  final id = driveFileId(u);
  if (id != null) return 'https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t';
  return u;
}

/// File id from a Google Drive file link, or null (folders return null).
String? driveFileId(String u) {
  if (!u.contains('drive.google.com') && !u.contains('drive.usercontent.google.com')) return null;
  final m = RegExp(r'/file/d/([A-Za-z0-9_-]{10,})').firstMatch(u) ?? RegExp(r'[?&]id=([A-Za-z0-9_-]{10,})').firstMatch(u);
  return m?.group(1);
}

class LinkFile {
  LinkFile(this.bytes, this.name, this.mime);
  final Uint8List bytes;
  final String name, mime;
}

/// Thrown when the link gives a web page instead of a file (private file,
/// folder, or a site that needs login). The app then opens it in the browser.
class NotAFile implements Exception {}

const _mimes = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'csv': 'text/csv',
  'txt': 'text/plain',
  'zip': 'application/zip',
  'mp4': 'video/mp4',
  'mp3': 'audio/mpeg',
};

const _exts = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
  'text/csv': 'csv',
  'text/plain': 'txt',
  'application/zip': 'zip',
  'video/mp4': 'mp4',
};

String? _nameFrom(String? cd) {
  if (cd == null) return null;
  final star = RegExp(r"filename\*=(?:UTF-8|utf-8)''([^;]+)").firstMatch(cd);
  if (star != null) {
    try {
      return Uri.decodeComponent(star.group(1)!.trim());
    } catch (_) {}
  }
  final m = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
  return m?.group(1)?.trim();
}

String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_').trim();

/// Downloads any file link. [onProgress] gets 0..1 (or -1 when size is unknown).
Future<LinkFile> fetchLinkFile(String url, String title, void Function(double) onProgress) async {
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(directDownloadUrl(url)));
    final res = await client.send(req);
    if (res.statusCode >= 400) throw NotAFile();
    var mime = (res.headers['content-type'] ?? '').split(';').first.trim().toLowerCase();
    if (mime == 'text/html') throw NotAFile();
    final total = res.contentLength ?? -1;
    final b = BytesBuilder(copy: false);
    var got = 0;
    await for (final chunk in res.stream) {
      b.add(chunk);
      got += chunk.length;
      onProgress(total > 0 ? got / total : -1);
    }
    var name = _safe(_nameFrom(res.headers['content-disposition']) ?? '');
    if (name.isEmpty) {
      final last = Uri.parse(res.request?.url.toString() ?? url).pathSegments.where((e) => e.isNotEmpty).lastOrNull ?? '';
      name = last.contains('.') ? _safe(Uri.decodeComponent(last)) : _safe(title.isEmpty ? 'file' : title);
    }
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (mime.isEmpty || mime == 'application/octet-stream' || mime == 'binary/octet-stream') {
      mime = _mimes[ext] ?? 'application/octet-stream';
    }
    if (ext.isEmpty && _exts[mime] != null) name = '$name.${_exts[mime]}';
    return LinkFile(b.takeBytes(), name, mime);
  } finally {
    client.close();
  }
}
