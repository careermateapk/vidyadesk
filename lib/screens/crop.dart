import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/strings.dart';

/// Opens the crop screen for a photo. Returns a small JPEG, or null when cancelled.
Future<Uint8List?> cropPhoto(BuildContext context, Uint8List bytes) =>
    Navigator.of(context, rootNavigator: true).push<Uint8List>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ImageCropScreen(bytes: bytes)));

// Work done away from the screen thread (so the app does not freeze).
Uint8List _rotateBytes((Uint8List, int) a) {
  final im = img.decodeImage(a.$1);
  if (im == null) return a.$1;
  return Uint8List.fromList(img.encodeJpg(img.copyRotate(im, angle: a.$2), quality: 90));
}

Uint8List _crop((Uint8List, double, double, double, double) a) {
  final im = img.decodeImage(a.$1)!;
  final x = (a.$2 * im.width).round().clamp(0, im.width - 1);
  final y = (a.$3 * im.height).round().clamp(0, im.height - 1);
  final w = (a.$4 * im.width).round().clamp(1, im.width - x);
  final h = (a.$5 * im.height).round().clamp(1, im.height - y);
  var out = img.copyCrop(im, x: x, y: y, width: w, height: h);
  if (out.width > 1200 || out.height > 1200) {
    out = out.width >= out.height ? img.copyResize(out, width: 1200) : img.copyResize(out, height: 1200);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 70));
}

(int, int) _size(Uint8List b) {
  final im = img.decodeImage(b);
  return im == null ? (1, 1) : (im.width, im.height);
}

class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

enum _Grab { none, move, tl, tr, bl, br }

class _ImageCropScreenState extends State<ImageCropScreen> {
  late Uint8List _img = widget.bytes;
  (int, int)? _px; // image size in pixels
  Rect _r = const Rect.fromLTWH(.05, .05, .9, .9); // crop, 0..1 of the image
  double? _ratio; // width / height, null = free
  bool _busy = true;
  _Grab _grab = _Grab.none;
  Rect _box = Rect.zero; // where the image is drawn on screen

  static const _ratios = [(null, 'crop_free'), (1.0, 'crop_square'), (4 / 3, '4:3'), (3 / 4, '3:4'), (16 / 9, '16:9')];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await compute(_size, _img);
    if (!mounted) return;
    setState(() {
      _px = s;
      _busy = false;
      _applyRatio();
    });
  }

  void _applyRatio() {
    final px = _px;
    if (px == null || _ratio == null) return;
    // ratio in image space → in 0..1 space
    final k = _ratio! * px.$2 / px.$1;
    var w = _r.width, h = w / k;
    if (h > 1) {
      h = .9;
      w = h * k;
    }
    if (w > 1) {
      w = .9;
      h = w / k;
    }
    final c = _r.center;
    _r = Rect.fromCenter(center: c, width: w, height: h);
    _r = _keepIn(_r);
  }

  Rect _keepIn(Rect r) {
    var dx = 0.0, dy = 0.0;
    if (r.left < 0) dx = -r.left;
    if (r.right > 1) dx = 1 - r.right;
    if (r.top < 0) dy = -r.top;
    if (r.bottom > 1) dy = 1 - r.bottom;
    return r.shift(Offset(dx, dy));
  }

  Future<void> _rotate() async {
    setState(() => _busy = true);
    final b = await compute(_rotate90, _img);
    final s = await compute(_size, b);
    if (!mounted) return;
    setState(() {
      _img = b;
      _px = s;
      _r = const Rect.fromLTWH(.05, .05, .9, .9);
      _applyRatio();
      _busy = false;
    });
  }

  static Uint8List _rotate90(Uint8List b) => _rotateBytes((b, 90));

  void _reset() => setState(() {
        _img = widget.bytes;
        _ratio = null;
        _r = const Rect.fromLTWH(.05, .05, .9, .9);
        _busy = true;
        _load();
      });

  Future<void> _done() async {
    setState(() => _busy = true);
    final out = await compute(_crop, (_img, _r.left, _r.top, _r.width, _r.height));
    if (mounted) Navigator.pop(context, out);
  }

  Rect get _screenRect => Rect.fromLTWH(_box.left + _r.left * _box.width, _box.top + _r.top * _box.height, _r.width * _box.width, _r.height * _box.height);

  void _start(Offset p) {
    final s = _screenRect;
    const t = 34.0;
    if ((p - s.topLeft).distance < t) {
      _grab = _Grab.tl;
    } else if ((p - s.topRight).distance < t) {
      _grab = _Grab.tr;
    } else if ((p - s.bottomLeft).distance < t) {
      _grab = _Grab.bl;
    } else if ((p - s.bottomRight).distance < t) {
      _grab = _Grab.br;
    } else if (s.inflate(8).contains(p)) {
      _grab = _Grab.move;
    } else {
      _grab = _Grab.none;
    }
  }

  void _drag(Offset d) {
    if (_grab == _Grab.none || _box.isEmpty) return;
    final dx = d.dx / _box.width, dy = d.dy / _box.height;
    const minW = .08;
    var r = _r;
    if (_grab == _Grab.move) {
      setState(() => _r = _keepIn(r.shift(Offset(dx, dy))));
      return;
    }
    var l = r.left, t = r.top, rr = r.right, b = r.bottom;
    switch (_grab) {
      case _Grab.tl:
        l += dx;
        t += dy;
      case _Grab.tr:
        rr += dx;
        t += dy;
      case _Grab.bl:
        l += dx;
        b += dy;
      case _Grab.br:
        rr += dx;
        b += dy;
      default:
    }
    l = l.clamp(0, rr - minW);
    rr = rr.clamp(l + minW, 1);
    t = t.clamp(0, b - minW);
    b = b.clamp(t + minW, 1);
    if (_ratio != null && _px != null) {
      final k = _ratio! * _px!.$2 / _px!.$1;
      final w = rr - l;
      var h = w / k;
      if (_grab == _Grab.tl || _grab == _Grab.tr) {
        t = b - h;
        if (t < 0) {
          t = 0;
          h = b;
          final nw = h * k;
          if (_grab == _Grab.tl) l = rr - nw; else rr = l + nw;
        }
      } else {
        b = t + h;
        if (b > 1) {
          b = 1;
          h = 1 - t;
          final nw = h * k;
          if (_grab == _Grab.bl) l = rr - nw; else rr = l + nw;
        }
      }
    }
    setState(() => _r = Rect.fromLTRB(l, t, rr, b));
  }

  @override
  Widget build(BuildContext context) {
    final px = _px;
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0C22),
        foregroundColor: Colors.white,
        title: Text(tr('crop_photo'), style: const TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(onPressed: _busy ? null : _done, child: Text(tr('done'), style: const TextStyle(color: Color(0xFFA79BFF), fontWeight: FontWeight.w800, fontSize: 16))),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(builder: (context, c) {
                if (px == null) return const Center(child: CircularProgressIndicator());
                final scale = math.min(c.maxWidth / px.$1, c.maxHeight / px.$2);
                final w = px.$1 * scale, h = px.$2 * scale;
                _box = Rect.fromLTWH((c.maxWidth - w) / 2, (c.maxHeight - h) / 2, w, h);
                return GestureDetector(
                  onPanStart: (d) => _start(d.localPosition),
                  onPanUpdate: (d) => _drag(d.delta),
                  onPanEnd: (_) => _grab = _Grab.none,
                  child: Stack(children: [
                    Positioned.fromRect(rect: _box, child: Image.memory(_img, fit: BoxFit.fill, gaplessPlayback: true)),
                    Positioned.fill(child: CustomPaint(painter: _CropPainter(_screenRect))),
                    if (_busy) const Center(child: CircularProgressIndicator()),
                  ]),
                );
              }),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              for (final r in _ratios)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _ratio = r.$1;
                      _applyRatio();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(color: _ratio == r.$1 ? const Color(0xFF6C5CE7) : Colors.white12, borderRadius: BorderRadius.circular(999)),
                      child: Text(r.$2.contains(':') ? r.$2 : tr(r.$2), style: TextStyle(color: _ratio == r.$1 ? Colors.white : Colors.white70, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _tool(Icons.rotate_90_degrees_cw_outlined, tr('rotate'), _busy ? null : _rotate),
            const SizedBox(width: 36),
            _tool(Icons.restart_alt_rounded, tr('reset'), _busy ? null : _reset),
          ]),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _tool(IconData i, String t, VoidCallback? on) => InkWell(
        onTap: on,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [Icon(i, color: Colors.white), const SizedBox(height: 4), Text(t, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12))]),
        ),
      );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.r);
  final Rect r;
  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(r);
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: .55));
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(r, line);
    final grid = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(r.left + r.width * i / 3, r.top), Offset(r.left + r.width * i / 3, r.bottom), grid);
      canvas.drawLine(Offset(r.left, r.top + r.height * i / 3), Offset(r.right, r.top + r.height * i / 3), grid);
    }
    final c = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const k = 18.0;
    for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final sx = p.dx == r.left ? 1 : -1, sy = p.dy == r.top ? 1 : -1;
      canvas.drawLine(p, p + Offset(k * sx, 0), c);
      canvas.drawLine(p, p + Offset(0, k * sy), c);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.r != r;
}
