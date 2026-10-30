import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// "Vidu" — VidyaDesk's owl mascot, drawn as SVG. Blinks every few seconds
/// (each owl at its own rhythm) unless [blink] is false.
/// What Vidu is doing. Each one moves in its own way.
enum OwlMood { idle, hello, wink, look, happy, read, sleep, think, sad, bow }

class Mascot extends StatefulWidget {
  const Mascot({super.key, this.size = 200, this.cap = true, this.book = true, this.wave = false, this.closed = false, this.blink = true, this.mood});
  final double size;
  final bool cap, book, wave, closed, blink;
  /// Animated mood. When null: [wave] → hello, otherwise standing still (only blinking).
  final OwlMood? mood;

  @override
  State<Mascot> createState() => _MascotState();
}

final _rnd = math.Random();

class _MascotState extends State<Mascot> {
  bool _shut = false;
  Timer? _next;
  final List<Timer> _steps = [];

  @override
  void initState() {
    super.initState();
    if (widget.blink && !widget.closed) _schedule(600 + _rnd.nextInt(2200));
  }

  void _schedule(int ms) {
    _next = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      const pattern = [(0, true), (130, false), (290, true), (420, false)];
      _steps.removeWhere((t) => !t.isActive);
      for (final s in pattern) {
        _steps.add(Timer(Duration(milliseconds: s.$1), () {
          if (mounted) setState(() => _shut = s.$2);
        }));
      }
      _schedule(3000 + _rnd.nextInt(2200));
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    for (final t in _steps) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final mood = w.mood ?? (w.wave ? OwlMood.hello : null);
    if (mood != null && !w.closed) return _MoodOwl(size: w.size, mood: mood, cap: w.cap, shut: _shut && w.blink);
    final open = SvgPicture.string(_owl(cap: w.cap, book: w.book, wave: w.wave, closed: w.closed), width: w.size, height: w.size);
    if (!w.blink || w.closed) return open;
    return SizedBox(
      width: w.size,
      height: w.size,
      child: Stack(children: [
        Offstage(offstage: _shut, child: open),
        Offstage(offstage: !_shut, child: SvgPicture.string(_owl(cap: w.cap, book: w.book, wave: w.wave, closed: true), width: w.size, height: w.size)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated Vidu: separate SVG pieces that Flutter moves (smooth, no redraw cost).
// ---------------------------------------------------------------------------

const _defs = '<defs>'
    '<linearGradient id="ob" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#A79BFF"/><stop offset="1" stop-color="#6C5CE7"/></linearGradient>'
    '<linearGradient id="obl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F4F1FF"/><stop offset="1" stop-color="#DCD6FF"/></linearGradient>'
    '<linearGradient id="oc" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3D347F"/><stop offset="1" stop-color="#1E1A45"/></linearGradient>'
    '<linearGradient id="bk" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#FFB547"/><stop offset="1" stop-color="#F59F00"/></linearGradient>'
    '<radialGradient id="sh" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#6C5CE7" stop-opacity="0.25"/><stop offset="1" stop-color="#6C5CE7" stop-opacity="0"/></radialGradient>'
    '</defs>';
String _svg(String body) => '<svg width="200" height="200" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">$_defs$body</svg>';

String _bodySvg({required bool cap, required bool mouth, required bool blush}) {
  final bx = blush ? '8' : '6', by = blush ? '4.5' : '4', bo = blush ? '0.85' : '0.55';
  final beak = mouth
      ? '<path d="M93 104 L100 112 L107 104Z" fill="url(#bk)"/><ellipse cx="100" cy="116" rx="6" ry="5" fill="#C2410C"/>'
      : '<path d="M93 104 L100 114 L107 104Z" fill="url(#bk)"/>';
  final capS = cap ? '<path d="M60 44 L100 26 L140 44 L100 62Z" fill="url(#oc)"/><path d="M78 50 L78 62 Q100 72 122 62 L122 50 L100 60Z" fill="#2B2560"/>' : '';
  return _svg('<path d="M52 88 Q52 40 100 40 Q148 40 148 88 L148 128 Q148 160 100 160 Q52 160 52 128Z" fill="url(#ob)"/>'
      '<path d="M52 70 L44 46 L70 58Z M148 70 L156 46 L130 58Z" fill="#8B7CF6"/>'
      '<ellipse cx="100" cy="128" rx="30" ry="26" fill="url(#obl)"/>'
      '<path d="M86 120 q4 4 8 0 M98 128 q4 4 8 0 M88 136 q4 4 8 0 M104 118 q4 4 8 0" stroke="#C4BBFF" stroke-width="2" fill="none" stroke-linecap="round"/>'
      '<circle cx="78" cy="88" r="21" fill="#FFFFFF"/><circle cx="122" cy="88" r="21" fill="#FFFFFF"/>'
      '$beak'
      '<ellipse cx="62" cy="108" rx="$bx" ry="$by" fill="#FF8FB1" fill-opacity="$bo"/><ellipse cx="138" cy="108" rx="$bx" ry="$by" fill="#FF8FB1" fill-opacity="$bo"/>'
      '$capS');
}

const _pupils = '<circle cx="80" cy="90" r="11" fill="#1E1A45"/><circle cx="120" cy="90" r="11" fill="#1E1A45"/><circle cx="84" cy="86" r="4" fill="#FFFFFF"/><circle cx="124" cy="86" r="4" fill="#FFFFFF"/>';
const _shutL = '<path d="M64 90 Q78 100 92 90" stroke="#1E1A45" stroke-width="5" fill="none" stroke-linecap="round"/>';
const _shutR = '<path d="M108 90 Q122 100 136 90" stroke="#1E1A45" stroke-width="5" fill="none" stroke-linecap="round"/>';
const _happyEyes = '<path d="M65 94 Q78 78 91 94" stroke="#1E1A45" stroke-width="5" fill="none" stroke-linecap="round"/><path d="M109 94 Q122 78 135 94" stroke="#1E1A45" stroke-width="5" fill="none" stroke-linecap="round"/>';
const _sadEyes = '<circle cx="78" cy="92" r="10" fill="#1E1A45"/><circle cx="122" cy="92" r="10" fill="#1E1A45"/><circle cx="81" cy="88" r="3.5" fill="#FFFFFF"/><circle cx="125" cy="88" r="3.5" fill="#FFFFFF"/>'
    '<path d="M64 76 L86 68" stroke="#4B3FC4" stroke-width="4" stroke-linecap="round"/><path d="M136 76 L114 68" stroke="#4B3FC4" stroke-width="4" stroke-linecap="round"/>';
const _winkEyes = '<circle cx="80" cy="90" r="11" fill="#1E1A45"/><circle cx="84" cy="86" r="4" fill="#FFFFFF"/>$_shutR';
const _glasses = '<circle cx="78" cy="88" r="23" fill="none" stroke="#2B2560" stroke-width="3.5"/><circle cx="122" cy="88" r="23" fill="none" stroke="#2B2560" stroke-width="3.5"/><path d="M99 86 Q100 82 101 86" stroke="#2B2560" stroke-width="3.5" fill="none"/>';
const _tassel = '<path d="M140 44 L140 66" stroke="#F59F00" stroke-width="3"/><circle cx="140" cy="68" r="4" fill="#F59F00"/>';
const _shadow = '<ellipse cx="100" cy="182" rx="62" ry="9" fill="url(#sh)"/>';
const _bookFront = '<path d="M62 122 L100 130 L138 122 L138 152 L100 160 L62 152Z" fill="#FFB547"/><path d="M66 124 L100 131 L134 124 L134 150 L100 157 L66 150Z" fill="#FFFFFF"/>'
    '<path d="M74 134 L94 138 M74 141 L94 145 M106 138 L126 134 M106 145 L126 141" stroke="#C9C1FF" stroke-width="2" stroke-linecap="round"/>';
const _page = '<path d="M100 131 L132 125 L132 149 L100 156Z" fill="#F7F5FF" stroke="#E0D9FF" stroke-width="1.5"/>';
const _tear = '<path d="M64 100 Q60 110 64 114 Q68 110 64 100Z" fill="#7CC4FF"/>';
String _wing(String d) => _svg('<path d="$d" stroke="#8B7CF6" stroke-width="12.5" fill="none" stroke-linecap="round"/>');

/// (left path, left pivot, right path, right pivot)
(String, Offset, String, Offset) _wings(OwlMood m) => switch (m) {
      OwlMood.hello => ('M54 118 Q40 130 50 146', const Offset(54, 118), 'M148 110 Q172 92 166 74', const Offset(148, 110)),
      OwlMood.happy => ('M54 110 Q30 88 36 64', const Offset(54, 110), 'M146 110 Q170 88 164 64', const Offset(146, 110)),
      OwlMood.think => ('M54 118 Q40 130 50 146', const Offset(54, 118), 'M146 122 Q150 106 118 112', const Offset(146, 122)),
      OwlMood.bow => ('M58 124 Q80 118 96 104', const Offset(58, 124), 'M142 124 Q120 118 104 104', const Offset(142, 124)),
      _ => ('M54 118 Q40 130 50 146', const Offset(54, 118), 'M146 118 Q160 130 150 146', const Offset(146, 118)),
    };

Duration _period(OwlMood m) => Duration(
    milliseconds: switch (m) {
      OwlMood.hello => 1400,
      OwlMood.wink => 2600,
      OwlMood.look => 3200,
      OwlMood.happy => 800,
      OwlMood.read => 2200,
      OwlMood.sleep => 2800,
      OwlMood.think => 1600,
      OwlMood.sad => 3000,
      OwlMood.bow => 2600,
      OwlMood.idle => 3000,
    });

class _MoodOwl extends StatefulWidget {
  const _MoodOwl({required this.size, required this.mood, required this.cap, required this.shut});
  final double size;
  final OwlMood mood;
  final bool cap, shut;
  @override
  State<_MoodOwl> createState() => _MoodOwlState();
}

class _MoodOwlState extends State<_MoodOwl> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _period(widget.mood))..repeat();
  late String _bodyS, _wl, _wr;
  late (String, Offset, String, Offset) _w;

  @override
  void initState() {
    super.initState();
    _prep();
  }

  @override
  void didUpdateWidget(_MoodOwl old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood || old.cap != widget.cap) {
      _c.duration = _period(widget.mood);
      _c.repeat();
      _prep();
    }
  }

  void _prep() {
    final m = widget.mood;
    _bodyS = _bodySvg(cap: widget.cap, mouth: m == OwlMood.hello || m == OwlMood.happy, blush: m == OwlMood.wink || m == OwlMood.happy || m == OwlMood.bow);
    _w = _wings(m);
    _wl = _wing(_w.$1);
    _wr = _wing(_w.$3);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _ease(double x) => 0.5 - 0.5 * math.cos(math.pi * x.clamp(0.0, 1.0));

  /// 0 → 1 → 0 between a and b (holding 1 in the middle).
  static double _hold(double t, double a, double b, {double r = .06}) {
    if (t <= a || t >= b) return 0;
    if (t < a + r) return _ease((t - a) / r);
    if (t > b - r) return _ease((b - t) / r);
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size, k = s / 200;
    final m = widget.mood;
    Widget pic(String svg) => SvgPicture.string(svg, width: s, height: s);
    Widget rot(Widget c, Offset pivot, double a) => a == 0 ? c : Transform(alignment: Alignment.topLeft, origin: pivot * k, transform: Matrix4.rotationZ(a), child: c);

    return RepaintBoundary(
      child: SizedBox(
        width: s,
        height: s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final sw = math.sin(2 * math.pi * t);
            var dy = 0.0, tilt = 0.0, sx = 1.0, sy = 1.0;
            var px = 0.0, py = 0.0;
            var wl = 0.0, wr = 0.0, tas = 0.0;
            var eyes = widget.shut ? '$_shutL$_shutR' : _pupils;
            switch (m) {
              case OwlMood.idle:
                tas = sw * .08;
              case OwlMood.hello:
                wr = sw * .32;
                tas = sw * .28;
              case OwlMood.wink:
                final hw = _hold(t, .28, .66, r: .08);
                tilt = -.15 * hw;
                tas = .2 * hw;
                if (t > .32 && t < .62) eyes = _winkEyes;
              case OwlMood.look:
                px = t < .1
                    ? 0
                    : t < .25
                        ? -6 * _ease((t - .1) / .15)
                        : t < .4
                            ? -6
                            : t < .55
                                ? -6 + 12 * _ease((t - .4) / .15)
                                : t < .7
                                    ? 6
                                    : t < .85
                                        ? 6 - 6 * _ease((t - .7) / .15)
                                        : 0;
                tilt = px / 6 * .07;
              case OwlMood.happy:
                dy = -26 * math.sin(math.pi * t);
                sy = t < .1 ? 1 - .06 * math.sin(math.pi * t / .1) : 1;
                wl = math.sin(4 * math.pi * t) * .16;
                wr = -wl;
                tas = sw * .3;
                eyes = _happyEyes;
              case OwlMood.read:
                px = -3 + 6 * _ease(t < .5 ? t * 2 : 2 - t * 2);
                py = 4;
              case OwlMood.sleep:
                final br = 0.5 - 0.5 * math.cos(2 * math.pi * t);
                sx = 1 + .025 * br;
                sy = 1 + .045 * br;
                tilt = .1;
                tas = .35;
                eyes = '$_shutL$_shutR';
              case OwlMood.think:
                wr = (0.5 - 0.5 * math.cos(2 * math.pi * t)) * -.14;
                px = 4 * math.cos(math.pi * t);
                py = -5;
                tilt = -.06;
              case OwlMood.sad:
                final sl = math.pow(math.sin(math.pi * t), 2).toDouble();
                dy = 5 * sl;
                sy = 1 - .04 * sl;
                tas = .3;
                eyes = _sadEyes;
              case OwlMood.bow:
                final hb = _hold(t, .25, .75, r: .12);
                dy = 7 * hb;
                sy = 1 - .08 * hb;
                eyes = _happyEyes;
            }

            final pageT = _ease((t - .3) / .3);
            final tearT = (t * 1.5) % 1;
            final bodyStack = Stack(children: [
              pic(_bodyS),
              Transform.translate(offset: Offset(px * k, py * k), child: pic(_svg(eyes))),
              if (m == OwlMood.read) pic(_svg(_glasses)),
              if (widget.cap) rot(pic(_svg(_tassel)), const Offset(140, 44), tas),
              if (m == OwlMood.read) ...[
                pic(_svg(_bookFront)),
                Transform(
                  alignment: Alignment.topLeft,
                  origin: const Offset(100, 140) * k,
                  transform: Matrix4.diagonal3Values(1 - 2 * pageT, 1, 1),
                  child: pic(_svg(_page)),
                ),
              ],
              rot(pic(_wl), _w.$2, wl),
              rot(pic(_wr), _w.$4, wr),
              if (m == OwlMood.sad) Transform.translate(offset: Offset(0, 40 * k * tearT), child: Opacity(opacity: (1 - tearT).clamp(0.0, 1.0), child: pic(_svg(_tear)))),
            ]);

            final shadowScale = m == OwlMood.happy ? 1 - .3 * math.sin(math.pi * t) : 1.0;
            final body = Matrix4.identity()
              ..translate(0.0, dy * k)
              ..rotateZ(tilt)
              ..scale(sx, sy);
            return Stack(clipBehavior: Clip.none, children: [
              Transform(alignment: Alignment.topLeft, origin: const Offset(100, 182) * k, transform: Matrix4.diagonal3Values(shadowScale, 1, 1), child: pic(_svg(_shadow))),
              Transform(alignment: Alignment.topLeft, origin: const Offset(100, 160) * k, transform: body, child: bodyStack),
              ..._extras(m, t, s),
            ]);
          },
        ),
      ),
    );
  }

  List<Widget> _extras(OwlMood m, double t, double s) {
    switch (m) {
      case OwlMood.happy:
        const cols = [Color(0xFFFFB547), Color(0xFF6C5CE7), Color(0xFF12B886), Color(0xFFF0466E), Color(0xFF3B9EF5)];
        return [
          for (var i = 0; i < 12; i++)
            _confetti(((t * .5) + i * .083) % 1, i, s, cols[i % 5]),
        ];
      case OwlMood.sleep:
        return [
          for (var i = 0; i < 3; i++) _zed((t + i / 3) % 1, s),
        ];
      case OwlMood.think:
        return [
          Positioned(
            right: s * .02,
            top: s * .04 - 6 * math.sin(2 * math.pi * t),
            child: Transform.rotate(
              angle: .1 * math.sin(2 * math.pi * t),
              child: Container(
                width: s * .22,
                height: s * .22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withValues(alpha: .25), blurRadius: 10, offset: const Offset(0, 4))]),
                child: Text('?', style: TextStyle(fontSize: s * .13, fontWeight: FontWeight.w900, color: const Color(0xFF6C5CE7))),
              ),
            ),
          ),
        ];
      case OwlMood.bow:
        return [
          for (var i = 0; i < 2; i++) _heart((t - .45 - i * .1) / .5, i, s),
        ];
      default:
        return const [];
    }
  }

  Widget _confetti(double ph, int i, double s, Color c) => Positioned(
        left: s * ((i * 0.37) % 1) - 6,
        top: -s * .1 + ph * s * 1.05,
        child: Opacity(
          opacity: ph < .85 ? 1 : ((1 - ph) / .15).clamp(0.0, 1.0),
          child: Transform.rotate(angle: ph * 9 + i, child: Container(width: s * .035, height: s * .055, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)))),
        ),
      );

  Widget _zed(double ph, double s) => Positioned(
        right: s * .12 - ph * s * .12,
        top: s * .28 - ph * s * .3,
        child: Opacity(
          opacity: (ph < .15 ? ph / .15 : 1 - ph).clamp(0.0, 1.0),
          child: Text('Z', style: TextStyle(fontSize: s * (.09 + ph * .08), fontWeight: FontWeight.w900, color: const Color(0xFF8B7CF6))),
        ),
      );

  Widget _heart(double ph, int i, double s) {
    if (ph <= 0 || ph >= 1) return const SizedBox.shrink();
    return Positioned(
      left: s * (.3 + i * .32),
      top: s * .12 - ph * s * .2,
      child: Opacity(opacity: (ph < .2 ? ph / .2 : 1 - ph).clamp(0.0, 1.0), child: Text('♥', style: TextStyle(fontSize: s * .12, color: const Color(0xFFF0466E)))),
    );
  }
}

/// Vidu who blinks twice every few seconds.
class BlinkingMascot extends StatefulWidget {
  const BlinkingMascot({super.key, this.size = 200, this.cap = true, this.book = true, this.wave = false});
  final double size;
  final bool cap, book, wave;
  @override
  State<BlinkingMascot> createState() => _BlinkingMascotState();
}

class _BlinkingMascotState extends State<BlinkingMascot> {
  bool _closed = false;
  Timer? _loop;
  final List<Timer> _steps = [];

  @override
  void initState() {
    super.initState();
    _blink(const Duration(milliseconds: 900));
    _loop = Timer.periodic(const Duration(milliseconds: 3400), (_) => _blink(Duration.zero));
  }

  void _blink(Duration start) {
    const pattern = [(0, true), (130, false), (290, true), (420, false)];
    for (final s in pattern) {
      _steps.add(Timer(start + Duration(milliseconds: s.$1), () {
        if (mounted) setState(() => _closed = s.$2);
      }));
    }
    _steps.removeWhere((t) => !t.isActive);
  }

  @override
  void dispose() {
    _loop?.cancel();
    for (final t in _steps) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(children: [
          Offstage(offstage: _closed, child: Mascot(size: widget.size, cap: widget.cap, book: widget.book, wave: widget.wave, blink: false)),
          Offstage(offstage: !_closed, child: Mascot(size: widget.size, cap: widget.cap, book: widget.book, wave: widget.wave, closed: true)),
        ]),
      );
}

String _owl({required bool cap, required bool book, required bool wave, bool closed = false}) => '''
<svg width="200" height="200" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
<defs>
<linearGradient id="ob" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#A79BFF"/><stop offset="1" stop-color="#6C5CE7"/></linearGradient>
<linearGradient id="obl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F4F1FF"/><stop offset="1" stop-color="#DCD6FF"/></linearGradient>
<linearGradient id="oc" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3D347F"/><stop offset="1" stop-color="#1E1A45"/></linearGradient>
<linearGradient id="bk" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#FFB547"/><stop offset="1" stop-color="#F59F00"/></linearGradient>
<radialGradient id="sh" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#6C5CE7" stop-opacity="0.25"/><stop offset="1" stop-color="#6C5CE7" stop-opacity="0"/></radialGradient>
</defs>
<ellipse cx="100" cy="182" rx="62" ry="9" fill="url(#sh)"/>
${book ? '<path d="M40 160 Q100 140 160 160 L160 176 Q100 158 40 176Z" fill="#FFFFFF" stroke="#D9D3FF" stroke-width="2"/><path d="M100 150 L100 168" stroke="#C9C1FF" stroke-width="2"/>' : ''}
<path d="M52 88 Q52 40 100 40 Q148 40 148 88 L148 128 Q148 160 100 160 Q52 160 52 128Z" fill="url(#ob)"/>
<path d="M52 70 L44 46 L70 58Z M148 70 L156 46 L130 58Z" fill="#8B7CF6"/>
<ellipse cx="100" cy="128" rx="30" ry="26" fill="url(#obl)"/>
<path d="M86 120 q4 4 8 0 M98 128 q4 4 8 0 M88 136 q4 4 8 0 M104 118 q4 4 8 0" stroke="#C4BBFF" stroke-width="2" fill="none" stroke-linecap="round"/>
<circle cx="78" cy="88" r="21" fill="#FFFFFF"/><circle cx="122" cy="88" r="21" fill="#FFFFFF"/>
${closed ? '<path d="M64 90 Q78 100 92 90" stroke="#1E1A45" stroke-width="5" fill="none" stroke-linecap="round"/><path d="M108 90 Q122 100 136 90" stroke="#1E1A45" stroke-width="5" fill="none" stroke-linecap="round"/>' : '<circle cx="80" cy="90" r="11" fill="#1E1A45"/><circle cx="120" cy="90" r="11" fill="#1E1A45"/><circle cx="84" cy="86" r="4" fill="#FFFFFF"/><circle cx="124" cy="86" r="4" fill="#FFFFFF"/>'}
<path d="M93 104 L100 114 L107 104Z" fill="url(#bk)"/>
<ellipse cx="62" cy="108" rx="6" ry="4" fill="#FF8FB1" fill-opacity="0.55"/><ellipse cx="138" cy="108" rx="6" ry="4" fill="#FF8FB1" fill-opacity="0.55"/>
${cap ? '<path d="M60 44 L100 26 L140 44 L100 62Z" fill="url(#oc)"/><path d="M78 50 L78 62 Q100 72 122 62 L122 50 L100 60Z" fill="#2B2560"/><path d="M140 44 L140 66" stroke="#F59F00" stroke-width="3"/><circle cx="140" cy="68" r="4" fill="#F59F00"/>' : ''}
${wave ? '<path d="M148 110 Q172 92 166 74" stroke="#8B7CF6" stroke-width="13" fill="none" stroke-linecap="round"/><path d="M54 118 Q40 130 50 146" stroke="#8B7CF6" stroke-width="12" fill="none" stroke-linecap="round"/>' : '<path d="M54 118 Q40 130 50 146" stroke="#8B7CF6" stroke-width="12" fill="none" stroke-linecap="round"/><path d="M146 118 Q160 130 150 146" stroke="#8B7CF6" stroke-width="12" fill="none" stroke-linecap="round"/>'}
</svg>''';

/// Vidu's graduation cap on its own (for the splash, where it flies off and lands back).
class ViduCap extends StatelessWidget {
  const ViduCap({super.key, required this.size});
  /// Size of the owl this cap belongs to.
  final double size;
  @override
  Widget build(BuildContext context) => SvgPicture.string(
        '<svg width="200" height="200" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">$_defs'
        '<path d="M60 44 L100 26 L140 44 L100 62Z" fill="url(#oc)"/><path d="M78 50 L78 62 Q100 72 122 62 L122 50 L100 60Z" fill="#2B2560"/>$_tassel</svg>',
        width: size,
        height: size,
      );
}
