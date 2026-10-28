import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// "Vidu" — VidyaDesk's owl mascot, drawn as SVG.
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.size = 200, this.cap = true, this.book = true, this.wave = false, this.closed = false});
  final double size;
  final bool cap, book, wave, closed;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_owl(cap: cap, book: book, wave: wave, closed: closed), width: size, height: size);
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
          Offstage(offstage: _closed, child: Mascot(size: widget.size, cap: widget.cap, book: widget.book, wave: widget.wave)),
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
