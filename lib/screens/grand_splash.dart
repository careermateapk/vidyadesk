import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../ui/mascot.dart';

/// The big opening: a star bursts, pieces spiral in, BOOM — Vidu pops out,
/// the cap flips, the name drops in letter by letter, with sound.
/// Everything is driven by one clock ([_t], seconds) so Skip can jump ahead.
class GrandSplash extends StatefulWidget {
  const GrandSplash({super.key, required this.ready, required this.onStart});
  /// When false the button shows a small spinner (the app is still starting).
  final bool ready;
  final VoidCallback onStart;
  @override
  State<GrandSplash> createState() => _GrandSplashState();
}

class _GrandSplashState extends State<GrandSplash> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _t = ValueNotifier<double>(0);
  double _offset = 0;
  AudioPlayer? _player;
  bool _sound = true;
  bool _boomBuzz = false;

  static const _end = 6.9; // everything is on screen by now

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      final v = d.inMicroseconds / 1e6 + _offset;
      _t.value = v;
      if (!_boomBuzz && v > 2.62) {
        _boomBuzz = true;
        HapticFeedback.heavyImpact();
      }
    })
      ..start();
    _sound = context.appRead.splashSound;
    _waitThenPlay();
  }

  /// Sound only for someone who isn't logged in yet (a returning user just
  /// sees the start for a moment while the app loads).
  Future<void> _waitThenPlay() async {
    for (var i = 0; i < 40 && mounted; i++) {
      final app = context.appRead;
      if (app.ready) {
        if (app.signedIn == null && _sound && _player == null) _play();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _play() async {
    try {
      final p = AudioPlayer();
      _player = p;
      // "sonification": follows the phone's silent / vibrate mode.
      await p.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          usageType: AndroidUsageType.assistanceSonification,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ));
      await p.play(AssetSource('sounds/splash.mp3'), position: Duration(milliseconds: (_t.value * 1000).round()));
    } catch (_) {}
  }

  void _toggleSound() {
    setState(() => _sound = !_sound);
    context.appRead.setSplashSound(_sound);
    if (_sound) {
      if (_t.value < 8.5 && context.appRead.signedIn == null) _play();
    } else {
      _player?.stop();
    }
  }

  void _skip() {
    if (_t.value >= _end) return;
    _offset += _end - _t.value;
    _boomBuzz = true;
    _player?.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _player?.dispose();
    _t.dispose();
    super.dispose();
  }

  static double _c01(double x) => x.clamp(0.0, 1.0);
  static double _seg(double t, double a, double b) => _c01((t - a) / (b - a));
  static double _out(double x) => Curves.easeOutCubic.transform(_c01(x));

  static const _tiles = <(Object, Color)>[
    ('✓', Color(0xFF12B886)),
    ('₹', Color(0xFFE8930C)),
    ('?', Color(0xFF6C5CE7)),
    ('A+', Color(0xFFF0466E)),
    (Icons.menu_book_rounded, Color(0xFF3B9EF5)),
    (Icons.notifications_rounded, Color(0xFF8B7CF6)),
    (Icons.calendar_month_rounded, Color(0xFF0EA5B7)),
    ('%', Color(0xFF12B886)),
    (Icons.school_rounded, Color(0xFF4B3FC4)),
    ('₹', Color(0xFFE8930C)),
    ('✓', Color(0xFF6C5CE7)),
    (Icons.groups_rounded, Color(0xFFF0466E)),
  ];

  Widget _tile(int i, double scale, double angle, double opacity) {
    final t = _tiles[i];
    return Opacity(
      opacity: _c01(opacity),
      child: Transform.rotate(
        angle: angle,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [t.$2, t.$2.withValues(alpha: .75)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 10), spreadRadius: -6)],
            ),
            child: t.$1 is IconData
                ? Icon(t.$1 as IconData, color: Colors.white, size: 21)
                : Text(t.$1 as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF07051A),
      body: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final c = Offset(w / 2, h * .37);
        const owlSize = 240.0;
        return ValueListenableBuilder<double>(
          valueListenable: _t,
          builder: (context, t, _) {
            // camera: close-up, a shake on the boom, then pulls back
            final shake = t > 2.6 && t < 2.85 ? math.sin(t * 90) * 4 * (1 - _seg(t, 2.6, 2.85)) : 0.0;
            final cam = 1.25 - .25 * _out(_seg(t, 2.9, 5.4));
            final boom = _seg(t, 2.6, 3.05);
            final owlPop = t < 2.57 ? 0.0 : Curves.elasticOut.transform(_seg(t, 2.57, 3.35));
            final capT = _seg(t, 2.66, 3.9);
            final capOn = t < 2.66 || t >= 3.9;
            final rays = _seg(t, .8, 2.7);
            final aurora = _out(_seg(t, 2.7, 4.5));
            final orbitStart = 3.24;

            final children = <Widget>[
              // stars
              Positioned.fill(child: CustomPaint(painter: _Stars())),
              // warm + purple glow from the bottom
              Positioned(
                left: -w * .4,
                right: -w * .4,
                bottom: -320 + 220 * (1 - aurora),
                height: 720,
                child: Opacity(
                  opacity: aurora,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(center: Alignment(0, .2), radius: .62, colors: [Color(0xFF8B7CF6), Color(0xFF5545D6), Color(0x733B28B4), Color(0x003B28B4)], stops: [0, .28, .55, 1]),
                    ),
                  ),
                ),
              ),
              // light rays
              Positioned.fill(child: CustomPaint(painter: _Rays(c, rays * (t > 2.7 ? 1 : .6 + .4 * rays), t * .16))),
            ];

            // the first star
            if (t < 1.05) {
              final s = t < .3 ? _out(t / .3) * 1.2 : (t < .55 ? 1.2 - .4 * _seg(t, .3, .55) : (t < .8 ? .8 + .6 * _seg(t, .55, .8) : 1.4 * (1 - _seg(t, .8, 1.0))));
              children.add(Positioned(
                left: c.dx - 80,
                top: c.dy - 80,
                child: Transform.rotate(angle: t * 2.4, child: Transform.scale(scale: s, child: SizedBox(width: 160, height: 160, child: CustomPaint(painter: _Spark())))),
              ));
            }
            // sparks: at the star burst and at the boom
            for (final burst in [(.8, 1.35, 1.0), (2.62, 3.6, 2.0)]) {
              if (t > burst.$1 && t < burst.$2) {
                final f = _out(_seg(t, burst.$1, burst.$2));
                for (var i = 0; i < 28; i++) {
                  final a = i / 28 * 2 * math.pi + (burst.$3 > 1 ? .2 : 0);
                  final d = (burst.$3 > 1 ? 180 + (i % 5) * 50 : 90 + (i % 4) * 40) * f;
                  children.add(Positioned(
                    left: c.dx + math.cos(a) * d - 2,
                    top: c.dy + math.sin(a) * d - 2,
                    child: Opacity(
                      opacity: 1 - f,
                      child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0xFFA79BFF), blurRadius: 8, spreadRadius: 2)])),
                    ),
                  ));
                }
              }
            }
            // pieces spiral in
            if (t > 1.2 && t < 2.6) {
              for (var i = 0; i < _tiles.length; i++) {
                final s0 = 1.26 + i * .045;
                if (t < s0) continue;
                final f = _seg(t, s0, 2.52);
                final a = i / _tiles.length * 2 * math.pi + f * 2.6;
                final r = 300 * (1 - f);
                children.add(Positioned(
                  left: c.dx + math.cos(a) * r - 23,
                  top: c.dy + math.sin(a) * r - 23,
                  child: _tile(i, 1 - f * .7, f * 9.4, t > 2.52 ? 0 : _seg(t, s0, s0 + .15)),
                ));
              }
            }
            // orbit after the boom (keeps going)
            if (t > orbitStart) {
              final f = t - orbitStart;
              final appear = _seg(t, orbitStart, orbitStart + .9);
              final items = <(double, Widget)>[];
              for (var i = 0; i < _tiles.length; i++) {
                final ang = i / _tiles.length * 2 * math.pi + f * .78;
                final z = math.sin(ang);
                final x = 150 * math.cos(ang) * (.6 + .4 * appear);
                final y = 46 * z + (i % 3 - 1) * 30;
                items.add((
                  z,
                  Positioned(
                    left: c.dx + x - 23,
                    top: c.dy + y * appear - 23,
                    child: _tile(i, (.62 + .38 * (z + 1) / 2) * (.4 + .6 * appear), math.cos(ang) * .24, (.55 + .45 * (z + 1) / 2) * appear),
                  ),
                ));
              }
              items.sort((a, b) => a.$1.compareTo(b.$1));
              // behind the owl
              children.addAll(items.where((e) => e.$1 < 0).map((e) => e.$2));
              children.add(const SizedBox.shrink(key: ValueKey('owl-slot')));
              children.addAll(items.where((e) => e.$1 >= 0).map((e) => e.$2));
            }
            // flash + shock waves
            if (t > 2.6 && t < 3.5) {
              for (final d in [0.0, .18]) {
                final f = _seg(t, 2.6 + d, 3.42 + d);
                if (f > 0 && f < 1) {
                  final r = 10 + 290 * Curves.easeOut.transform(f);
                  children.add(Positioned(
                    left: c.dx - r,
                    top: c.dy - r,
                    child: Opacity(opacity: 1 - f, child: Container(width: r * 2, height: r * 2, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xE6C8BEFF), width: 3)))),
                  ));
                }
              }
              final fl = boom < .12 ? boom / .12 : 1 - (boom - .12) / .88;
              children.add(Positioned(
                left: c.dx - 260,
                top: c.dy - 260,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _c01(fl),
                    child: Container(width: 520, height: 520, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Colors.white, Color(0xCCC8BEFF), Color(0x00C8BEFF)], stops: [0, .3, .7]))),
                  ),
                ),
              ));
            }
            // Vidu
            Widget? owl;
            if (owlPop > 0) {
              final bob = t > 3.6 ? math.sin((t - 3.6) * 1.4) : 0.0;
              final turn = t > 3.6 ? math.sin((t - 3.6) * .9) * .42 : 0.0;
              owl = Positioned(
                left: c.dx - owlSize / 2,
                top: c.dy - owlSize / 2 - 6 * bob,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .0012)
                    ..scale(owlPop, owlPop)
                    ..rotateZ((1 - _c01(owlPop)) * -.35)
                    ..rotateY(turn),
                  child: Mascot(size: owlSize, book: false, cap: capOn, mood: OwlMood.hello),
                ),
              );
              final slot = children.indexWhere((x) => x.key == const ValueKey('owl-slot'));
              if (slot >= 0) {
                children[slot] = owl;
              } else {
                children.add(owl);
              }
              // the cap flies off and lands back
              if (!capOn) {
                final up = capT < .45 ? Curves.easeOut.transform(capT / .45) : 1 - Curves.easeIn.transform((capT - .45) / .55);
                children.add(Positioned(
                  left: c.dx - owlSize / 2,
                  top: c.dy - owlSize / 2 - 150 * up,
                  child: Transform.rotate(angle: capT * 4 * math.pi, child: const ViduCap(size: owlSize)),
                ));
              }
            }

            // words
            final pre = _seg(t, 3.78, 4.5);
            final tag = _out(_seg(t, 5.58, 6.3));
            final btn = _seg(t, 6.12, 6.84);
            const word = 'VidyaDesk';
            final shine = _seg(t, 5.22, 5.94);
            final textTop = h * .6;
            children.addAll([
              Positioned(
                left: 0,
                right: 0,
                top: textTop - 24,
                child: Opacity(
                  opacity: pre,
                  child: Text(tr('splash_welcome'), textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFFC9C1FF), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 12 - 8 * pre)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: textTop,
                child: ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (r) => LinearGradient(
                    colors: const [Color(0x00FFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
                    stops: [(shine * 1.4 - .3).clamp(0.0, 1.0), (shine * 1.4 - .15).clamp(0.0, 1.0), (shine * 1.4).clamp(0.0, 1.0)],
                  ).createShader(r),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < word.length; i++)
                      Builder(builder: (_) {
                        final s0 = 3.96 + i * .117;
                        final f = _seg(t, s0, s0 + .3);
                        final drop = f < .7 ? -40 * (1 - Curves.easeOut.transform(f / .7)) + 4 * Curves.easeOut.transform(f / .7) : 4 * (1 - (f - .7) / .3);
                        return Opacity(
                          opacity: _c01(f * 2),
                          child: Transform.translate(
                            offset: Offset(0, drop),
                            child: Transform.scale(
                              scale: 1 + .6 * (1 - _c01(f / .7)),
                              child: Text(word[i], style: TextStyle(color: i >= 5 ? const Color(0xFFC9C1FF) : Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -1.5, height: 1.1)),
                            ),
                          ),
                        );
                      }),
                  ]),
                ),
              ),
              Positioned(
                left: 36,
                right: 36,
                top: textTop + 62,
                child: Opacity(
                  opacity: tag,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - tag)),
                    child: Text(tr('splash_line'), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xD1FFFFFF), fontWeight: FontWeight.w600, fontSize: 15, height: 1.45)),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 30 + mq.padding.bottom,
                child: Opacity(
                  opacity: btn,
                  child: Transform.translate(
                    offset: Offset(0, 30 * (1 - Curves.easeOut.transform(btn))),
                    child: GestureDetector(
                      onTap: btn > .5 && widget.ready ? widget.onStart : null,
                      child: Container(
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: [BoxShadow(color: const Color(0xFFA79BFF).withValues(alpha: .45 + .4 * (0.5 + 0.5 * math.sin(t * 2.4))), blurRadius: 34)],
                        ),
                        child: widget.ready
                            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text(tr('get_started'), style: const TextStyle(color: Color(0xFF2B2370), fontWeight: FontWeight.w900, fontSize: 17)),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded, color: Color(0xFF2B2370), size: 20),
                              ])
                            : const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF6C5CE7))),
                      ),
                    ),
                  ),
                ),
              ),
            ]);

            return Stack(children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(shake, -shake * .6),
                  child: Transform.scale(scale: cam, origin: Offset(0, c.dy - h / 2), child: Stack(clipBehavior: Clip.none, children: children)),
                ),
              ),
              // sound on/off + skip
              Positioned(
                top: mq.padding.top + 8,
                right: 12,
                child: Row(children: [
                  _chip(_sound ? Icons.volume_up_rounded : Icons.volume_off_rounded, null, _toggleSound),
                  const SizedBox(width: 8),
                  if (t < _end) _chip(null, tr('skip_intro'), _skip),
                ]),
              ),
            ]);
          },
        );
      }),
    );
  }

  Widget _chip(IconData? icon, String? text, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: text == null ? 9 : 14),
          decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(99)),
          alignment: Alignment.center,
          child: icon != null ? Icon(icon, color: Colors.white, size: 18) : Text(text!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      );
}

class _Stars extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(4);
    final p = Paint()..color = Colors.white;
    for (var i = 0; i < 70; i++) {
      p.color = Colors.white.withValues(alpha: .12 + r.nextDouble() * .5);
      canvas.drawCircle(Offset(r.nextDouble() * size.width, r.nextDouble() * size.height), r.nextDouble() * 1.3 + .4, p);
    }
  }

  @override
  bool shouldRepaint(_Stars o) => false;
}

class _Rays extends CustomPainter {
  _Rays(this.c, this.o, this.angle);
  final Offset c;
  final double o, angle;
  @override
  void paint(Canvas canvas, Size size) {
    if (o <= 0) return;
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final p = Paint()..color = const Color(0xFFA79BFF).withValues(alpha: .22 * o);
    const n = 28;
    for (var i = 0; i < n; i++) {
      final a0 = i / n * 2 * math.pi, a1 = a0 + .09;
      canvas.drawPath(Path()
        ..moveTo(0, 0)
        ..lineTo(math.cos(a0) * 900, math.sin(a0) * 900)
        ..lineTo(math.cos(a1) * 900, math.sin(a1) * 900)
        ..close(), p);
    }
    canvas.rotate(-angle);
    // fade out with distance from the centre
    canvas.drawRect(
      rect.shift(-c),
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const RadialGradient(colors: [Colors.black, Color(0x99000000), Colors.transparent], stops: [0, .3, .75]).createShader(Rect.fromCircle(center: Offset.zero, radius: 460)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Rays o2) => o2.o != o || o2.angle != angle;
}

class _Spark extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (final (a, len, op) in [(0.0, 80.0, 1.0), (math.pi / 2, 80.0, 1.0), (math.pi / 4, 45.0, .6), (-math.pi / 4, 45.0, .6)]) {
      final d = Offset(math.cos(a), math.sin(a)) * len;
      canvas.drawLine(
        c - d,
        c + d,
        Paint()
          ..strokeWidth = 2
          ..shader = LinearGradient(colors: [Colors.transparent, Colors.white.withValues(alpha: op), Colors.transparent]).createShader(Rect.fromPoints(c - d, c + d)),
      );
    }
    canvas.drawCircle(c, 14, Paint()..color = const Color(0xFFA79BFF).withValues(alpha: .5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    canvas.drawCircle(c, 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_Spark o) => false;
}
