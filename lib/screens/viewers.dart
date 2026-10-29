import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'crop.dart';
import 'file_sheet.dart';

// ---------------------------------------------------------------------------
// YouTube helpers
// ---------------------------------------------------------------------------

/// Video id from any YouTube link (watch, youtu.be, shorts, live, embed), or null.
String? youtubeId(String url) {
  final u = url.trim();
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(u)) return u;
  final pats = [
    RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})'),
    RegExp(r'[?&]v=([A-Za-z0-9_-]{11})'),
    RegExp(r'youtube\.com/(?:shorts|live|embed|v)/([A-Za-z0-9_-]{11})'),
  ];
  for (final p in pats) {
    final m = p.firstMatch(u);
    if (m != null) return m.group(1);
  }
  return null;
}

String youtubeThumb(String id) => 'https://img.youtube.com/vi/$id/mqdefault.jpg';

/// Plays a YouTube video inside the app.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.videoId, required this.title, this.subtitle = '', this.desc = ''});
  final String videoId, title, subtitle, desc;
  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final YoutubePlayerController _c = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    params: const YoutubePlayerParams(showFullscreenButton: false, strictRelatedVideos: true, origin: 'https://com.vidyadesk.app'),
  );

  /// Our own full screen: a sideways page that continues from the same second.
  Future<void> _fullScreen() async {
    double at = 0;
    try {
      at = await _c.currentTime;
    } catch (_) {}
    _c.pauseVideo();
    if (!mounted) return;
    final back = await Navigator.of(context, rootNavigator: true).push<double>(
      PageRouteBuilder(opaque: true, pageBuilder: (_, _, _) => _FullVideo(videoId: widget.videoId, start: at)),
    );
    if (!mounted) return;
    if (back != null) _c.seekTo(seconds: back, allowSeekAhead: true);
    _c.playVideo();
  }

  StreamSubscription<YoutubePlayerValue>? _sub;
  bool _full = false;

  @override
  void initState() {
    super.initState();
    // Full screen → turn the video sideways by itself; back → upright again.
    _sub = _c.stream.listen((v) {
      final f = v.fullScreenOption.enabled;
      if (f == _full) return;
      _full = f;
      _orient(f);
    });
  }

  static void _orient(bool landscape) {
    if (landscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_full) _orient(false);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _c.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: widget.title, subtitle: widget.subtitle.isEmpty ? null : widget.subtitle),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
        ClipRRect(borderRadius: BorderRadius.circular(18), child: YoutubePlayer(controller: _c, aspectRatio: 16 / 9, autoFullScreen: false)),
        const SizedBox(height: 10),
        SoftButton(label: tr('full_screen'), icon: Icons.fullscreen_rounded, onPressed: _fullScreen),
        const SizedBox(height: 16),
        Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        if (widget.desc.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(widget.desc, style: TextStyle(color: p.ink2, height: 1.45)),
        ],
      ]),
    );
  }
}

/// Sideways, edge-to-edge video. Pops with the second it reached.
class _FullVideo extends StatefulWidget {
  const _FullVideo({required this.videoId, required this.start});
  final String videoId;
  final double start;
  @override
  State<_FullVideo> createState() => _FullVideoState();
}

class _FullVideoState extends State<_FullVideo> {
  late final YoutubePlayerController _c = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    startSeconds: widget.start,
    params: const YoutubePlayerParams(showFullscreenButton: false, strictRelatedVideos: true, origin: 'https://com.vidyadesk.app'),
  );
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    double at = widget.start;
    try {
      at = await _c.currentTime;
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(at);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _c.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Center(child: YoutubePlayer(controller: _c, aspectRatio: 16 / 9, autoFullScreen: false)),
          Positioned(
            right: 12,
            top: 12,
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white), tooltip: tr('exit_full_screen'), onPressed: _close),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Web pages / Drive / PDF links
// ---------------------------------------------------------------------------

Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) toast(context, tr('err_open_link'));
}

String _fixUrl(String url) {
  var u = url.trim();
  if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
  // Android WebView cannot show PDF files directly — use Google's viewer.
  if (RegExp(r'\.pdf($|\?)', caseSensitive: false).hasMatch(u)) {
    return 'https://docs.google.com/viewer?embedded=true&url=${Uri.encodeComponent(u)}';
  }
  return u;
}

/// Opens a link (Google Drive, PDF, website) inside the app.
class WebPageScreen extends StatefulWidget {
  const WebPageScreen({super.key, required this.url, required this.title});
  final String url, title;
  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _c;
  int _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) setState(() => _failed = true);
        },
        onNavigationRequest: (r) {
          final u = r.url;
          if (u.startsWith('http://') || u.startsWith('https://')) return NavigationDecision.navigate;
          // intent://, mailto:, upi: … open in the right app
          launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication).catchError((_) => false);
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(_fixUrl(widget.url)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(
        title: widget.title,
        subtitle: Uri.tryParse(_fixUrl(widget.url))?.host,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconBtn(icon: Icons.download_rounded, tooltip: tr('download_file'), onTap: () => downloadLink(context, widget.url, widget.title)),
          const SizedBox(width: 8),
          IconBtn(icon: Icons.open_in_new_rounded, tooltip: tr('open_in_browser'), onTap: () => openExternal(context, widget.url)),
        ]),
      ),
      body: Column(children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 3, color: p.brand, backgroundColor: p.brandTint),
        Expanded(
          child: _failed
              ? ListView(padding: const EdgeInsets.all(24), children: [
                  EmptyState(icon: Icons.wifi_off_rounded, text: tr('err_page_load')),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: tr('try_again'),
                    icon: Icons.refresh_rounded,
                    arrow: false,
                    onPressed: () {
                      setState(() => _failed = false);
                      _c.reload();
                    },
                  ),
                ])
              : WebViewWidget(controller: _c),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Photos
// ---------------------------------------------------------------------------

/// Full-screen swipeable photos with pinch-zoom.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.images, this.start = 0, this.title = ''});
  final List<String> images;
  final int start;
  final String title;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          PageView.builder(
            controller: PageController(initialPage: start),
            itemCount: images.length,
            itemBuilder: (_, i) {
              final b = Avatar.bytesOf(images[i]);
              return InteractiveViewer(
                maxScale: 5,
                child: Center(child: b == null ? const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48) : Image.memory(b, fit: BoxFit.contain)),
              );
            },
          ),
          Positioned(
            left: 12,
            top: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            ),
          ),
          if (title.isNotEmpty)
            Positioned(
              left: 64,
              right: 16,
              top: 18,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
        ]),
      ),
    );
  }
}

/// Small rounded thumbnail of a base64 photo.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb(this.b64, {super.key, this.size = 72, this.onTap, this.onRemove});
  final String b64;
  final double size;
  final VoidCallback? onTap, onRemove;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final b = Avatar.bytesOf(b64);
    return GestureDetector(
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: size,
            height: size,
            color: p.cardAlt,
            child: b == null ? Icon(Icons.image_outlined, color: p.muted) : Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        ),
        if (onRemove != null)
          Positioned(
            right: -6,
            top: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle, border: Border.all(color: p.card, width: 2)),
                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Ask camera or gallery, return small JPEG photos as base64 (max [max]).
/// [crop]: let the person crop each photo (free, square, 4:3…, rotate).
Future<List<String>> pickPhotos(BuildContext context, {int max = 4, bool crop = false}) async {
  final p = context.pal;
  final src = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: IconBox(Icons.photo_camera_outlined, fg: p.brand, bg: p.brandTint),
            title: Text(tr('take_photo'), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pop(c, 'camera'),
          ),
          ListTile(
            leading: IconBox(Icons.photo_library_outlined, fg: p.indigo, bg: p.indigoTint),
            title: Text(tr('choose_gallery'), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pop(c, 'gallery'),
          ),
        ]),
      ),
    ),
  );
  if (src == null) return [];
  final picker = ImagePicker();
  try {
    final size = crop ? 1800.0 : 1000.0;
    final q = crop ? 85 : 50;
    final files = src == 'camera'
        ? [await picker.pickImage(source: ImageSource.camera, maxWidth: size, maxHeight: size, imageQuality: q)].whereType<XFile>().toList()
        : await picker.pickMultiImage(maxWidth: size, maxHeight: size, imageQuality: q);
    final out = <String>[];
    for (final f in files.take(max)) {
      var bytes = await f.readAsBytes();
      if (crop) {
        if (!context.mounted) break;
        final c = await cropPhoto(context, bytes);
        if (c == null) continue;
        bytes = c;
      }
      out.add(base64Encode(bytes));
    }
    return out;
  } catch (e) {
    if (context.mounted) toast(context, tr('err_photo'));
    return [];
  }
}
