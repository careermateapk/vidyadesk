import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// Bottom sheet: take photo / choose from gallery / remove → crop → save.
Future<void> changeProfilePhoto(BuildContext context) async {
  final p = context.pal;
  final app = context.appRead;
  final has = (app.profile?.photo ?? '').isNotEmpty;
  final pick = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('profile_photo'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text(tr('profile_photo_sub'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          _opt(c, p, 'camera', Icons.photo_camera_outlined, tr('take_photo'), p.brand, p.brandTint),
          _opt(c, p, 'gallery', Icons.photo_library_outlined, tr('choose_gallery'), p.indigo, p.indigoTint),
          if (has) _opt(c, p, 'remove', Icons.delete_outline_rounded, tr('remove_photo'), p.danger, p.dangerTint),
        ]),
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  String photo = '';
  if (pick != 'remove') {
    final x = await ImagePicker().pickImage(source: pick == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 1400, maxHeight: 1400, imageQuality: 90);
    if (x == null || !context.mounted) return;
    final bytes = await x.readAsBytes();
    if (!context.mounted) return;
    final cropped = await push<Uint8List>(context, PhotoCropScreen(bytes: bytes));
    if (cropped == null) return;
    photo = base64Encode(cropped);
  }
  try {
    await app.setPhoto(photo);
    if (context.mounted) toast(context, photo.isEmpty ? tr('photo_removed') : tr('photo_saved'));
  } catch (e) {
    if (context.mounted) toast(context, errorMessage(e));
  }
}

Widget _opt(BuildContext c, Palette p, String id, IconData icon, String label, Color fg, Color bg) => InkWell(
      onTap: () => Navigator.pop(c, id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          IconBox(icon, fg: fg, bg: bg),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: id == 'remove' ? p.danger : p.ink))),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      ),
    );

/// Pinch / drag the photo inside a circle, then save a small square image.
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final _boundary = GlobalKey();
  final _ctrl = TransformationController();
  int _turns = 0;
  bool _flip = false;
  bool _busy = false;
  double _zoom = 1;
  Size? _src; // picture size in pixels
  double _circle = 300;

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.bytes).then((img) {
      if (!mounted) return;
      setState(() => _src = Size(img.width.toDouble(), img.height.toDouble()));
      WidgetsBinding.instance.addPostFrameCallback((_) => _center());
    });
    _ctrl.addListener(() {
      final z = _ctrl.value.getMaxScaleOnAxis();
      if ((z - _zoom).abs() > .01) setState(() => _zoom = z);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// The picture's size on screen (after rotation) so that it just covers the circle.
  Size _childSize() {
    final src = _src ?? const Size(1, 1);
    final w = _turns.isOdd ? src.height : src.width;
    final h = _turns.isOdd ? src.width : src.height;
    final c = _circle;
    return w >= h ? Size(c * w / h, c) : Size(c, c * h / w);
  }

  /// Move/zoom so the picture always fills the whole circle — no empty edges.
  void _apply(double z, double tx, double ty) {
    final cs = _childSize();
    final c = _circle;
    tx = tx.clamp(c - cs.width * z, 0.0).toDouble();
    ty = ty.clamp(c - cs.height * z, 0.0).toDouble();
    _ctrl.value = Matrix4.diagonal3Values(z, z, 1)..setTranslationRaw(tx, ty, 0);
  }

  void _center() {
    final cs = _childSize();
    _apply(1, (_circle - cs.width) / 2, (_circle - cs.height) / 2);
  }

  void _setZoom(double z) {
    final m = _ctrl.value;
    final s0 = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    final c = _circle / 2;
    final cx = (c - t.x) / s0, cy = (c - t.y) / s0;
    _apply(z, c - cx * z, c - cy * z);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final ro = _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final size = ro.size.width;
      final img = await ro.toImage(pixelRatio: 320 / size);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || data == null) return;
      Navigator.of(context).pop(data.buffer.asUint8List());
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final box = w;
    _circle = w * .76;
    final circle = _circle;
    final cs = _childSize();
    return Scaffold(
      backgroundColor: const Color(0xFF0B0A14),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              _darkBtn(Icons.close_rounded, () => Navigator.of(context).pop()),
              Expanded(child: Text(tr('crop_photo'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
              _darkBtn(Icons.restart_alt_rounded, () {
                setState(() {
                  _turns = 0;
                  _flip = false;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) => _center());
              }),
            ]),
          ),
          const Spacer(),
          SizedBox(
            width: box,
            height: box,
            child: Stack(children: [
              Center(
                child: _src == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : RepaintBoundary(
                        key: _boundary,
                        child: ClipRect(
                          child: SizedBox(
                            width: circle,
                            height: circle,
                            child: InteractiveViewer(
                              transformationController: _ctrl,
                              minScale: 1,
                              maxScale: 5,
                              constrained: false,
                              boundaryMargin: EdgeInsets.zero,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: cs.width,
                                height: cs.height,
                                child: RotatedBox(
                                  quarterTurns: _turns,
                                  child: Transform.flip(flipX: _flip, child: Image.memory(widget.bytes, fit: BoxFit.fill, gaplessPlayback: true)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              IgnorePointer(child: CustomPaint(size: Size(box, box), painter: _CircleMask(circle / 2))),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: IgnorePointer(child: Text(tr('pinch_zoom'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w600))),
              ),
            ]),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(children: [
              const Icon(Icons.photo_size_select_small_rounded, color: Colors.white54, size: 18),
              Expanded(
                child: Slider(
                  value: _zoom.clamp(1, 5),
                  min: 1,
                  max: 5,
                  activeColor: const Color(0xFF8B7CF6),
                  inactiveColor: Colors.white24,
                  onChanged: _src == null ? null : _setZoom,
                ),
              ),
              const Icon(Icons.photo_size_select_large_rounded, color: Colors.white, size: 22),
            ]),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _tool(Icons.rotate_right_rounded, tr('rotate'), () {
              setState(() => _turns = (_turns + 1) % 4);
              WidgetsBinding.instance.addPostFrameCallback((_) => _center());
            }),
            const SizedBox(width: 18),
            _tool(Icons.flip_rounded, tr('flip'), () => setState(() => _flip = !_flip)),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(16)),
                    child: Text(tr('cancel'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: PrimaryButton(label: tr('save_photo'), icon: Icons.check_rounded, arrow: false, busy: _busy, onPressed: _src == null ? null : _save)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _darkBtn(IconData i, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
          child: Icon(i, color: Colors.white, size: 22),
        ),
      );

  Widget _tool(IconData i, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(16)),
            child: Icon(i, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _CircleMask extends CustomPainter {
  _CircleMask(this.r);
  final double r;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = Path()..addRect(Offset.zero & size);
    final hole = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(Path.combine(PathOperation.difference, outer, hole), Paint()..color = const Color(0xB00B0A14));
    final sq = Rect.fromCircle(center: c, radius: r);
    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(sq), hole), Paint()..color = const Color(0xB00B0A14));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white);
    final grid = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), grid);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), grid);
  }

  @override
  bool shouldRepaint(_CircleMask old) => old.r != r;
}
