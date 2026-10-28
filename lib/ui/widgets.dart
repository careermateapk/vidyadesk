import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import 'mascot.dart';

// ---------------------------------------------------------------------------
// Animations
// ---------------------------------------------------------------------------

/// Fades and slides its child up a little, after [delay].
class FadeIn extends StatefulWidget {
  const FadeIn({super.key, required this.child, this.delay = Duration.zero, this.offset = 18, this.duration = const Duration(milliseconds: 560)});
  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _t = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(offset: Offset(0, (1 - _a.value) * widget.offset), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Delay for item [i] in a list that animates in one after another.
Duration stagger(int i, {int startMs = 60, int stepMs = 60}) => Duration(milliseconds: startMs + i * stepMs);

/// A number that counts up from 0.
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, this.style, this.prefix = '', this.suffix = '', this.duration = const Duration(milliseconds: 1300)});
  final num value;
  final TextStyle? style;
  final String prefix, suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$prefix${formatNumber(v.round())}$suffix', style: style),
    );
  }
}

String formatNumber(int n) {
  final neg = n < 0;
  var s = n.abs().toString();
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    s = '${parts.join(',')},$last3';
  }
  return neg ? '-$s' : s;
}

String rupees(int n) => '₹${formatNumber(n)}';

/// Progress ring that fills up when it appears.
class Ring extends StatelessWidget {
  const Ring({super.key, required this.value, this.size = 92, this.stroke = 10, required this.color, required this.track, this.center});
  final double value; // 0..1
  final double size, stroke;
  final Color color, track;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, stroke, color, track),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.stroke, this.color, this.track);
  final double v, stroke;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - stroke) / 2;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, p..color = track);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color || old.track != track;
}

/// Bar that grows from the left.
class GrowBar extends StatelessWidget {
  const GrowBar({super.key, required this.value, required this.color, required this.track, this.height = 8, this.gradient});
  final double value;
  final Color color, track;
  final double height;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: track,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v,
            child: Container(decoration: BoxDecoration(color: gradient == null ? color : null, gradient: gradient, borderRadius: BorderRadius.circular(height))),
          ),
        ),
      ),
    );
  }
}

/// A light sweep that runs across its child again and again (for main buttons).
class Shine extends StatefulWidget {
  const Shine({super.key, required this.child, this.borderRadius = 18});
  final Widget child;
  final double borderRadius;

  @override
  State<Shine> createState() => _ShineState();
}

class _ShineState extends State<Shine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform((_c.value * 1.6).clamp(0, 1).toDouble());
                  return FractionalTranslation(
                    translation: Offset(-1.2 + t * 2.6, 0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0x00FFFFFF), Color(0x55FFFFFF), Color(0x00FFFFFF)]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pulsing dot (live / new).
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 9});
  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: (1 - _c.value) * 0.6), blurRadius: 0, spreadRadius: _c.value * 8)],
        ),
      ),
    );
  }
}

/// Gently floats up and down.
class Floaty extends StatefulWidget {
  const Floaty({super.key, required this.child, this.amount = 6});
  final Widget child;
  final double amount;

  @override
  State<Floaty> createState() => _FloatyState();
}

class _FloatyState extends State<Floaty> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Transform.translate(offset: Offset(0, -widget.amount * Curves.easeInOut.transform(_c.value)), child: child),
        child: widget.child,
      );
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.gradient, this.onTap, this.radius = 22, this.border});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double radius;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? p.card) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border != null ? Border.all(color: border!, width: 2) : (gradient == null ? Border.all(color: p.border) : null),
        boxShadow: p.shadow,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: box),
    );
  }
}

/// Main action button with gradient, shine and a little arrow nudge.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false, this.gradient, this.icon, this.arrow = true});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Gradient? gradient;
  final IconData? icon;
  final bool arrow;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final g = gradient ?? p.button;
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled ? [BoxShadow(color: g.colors.last.withValues(alpha: 0.5), blurRadius: 26, offset: const Offset(0, 14), spreadRadius: -12)] : null,
        ),
        child: Shine(
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(18)),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: enabled
                    ? () {
                        HapticFeedback.lightImpact();
                        onPressed!();
                      }
                    : null,
                child: SizedBox(
                  height: 54,
                  child: Center(
                    child: busy
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                              Flexible(
                                child: Text(label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: .1)),
                              ),
                              if (arrow) ...[const SizedBox(width: 8), const _Nudge()],
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Nudge extends StatefulWidget {
  const _Nudge();
  @override
  State<_Nudge> createState() => _NudgeState();
}

class _NudgeState extends State<_Nudge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Transform.translate(offset: Offset(5 * Curves.easeInOut.transform(_c.value), 0), child: child),
        child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
      );
}

class SoftButton extends StatelessWidget {
  const SoftButton({super.key, required this.label, required this.onPressed, this.icon, this.color, this.textColor, this.height = 48});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color, textColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: color ?? p.brandTint,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: textColor ?? p.brand), const SizedBox(width: 6)],
                Flexible(
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textColor ?? p.brand))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, required this.fg, required this.bg, this.leading});
  final String text;
  final Color fg, bg;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (leading != null) ...[leading!, const SizedBox(width: 5)],
          Text(text, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ]),
      );
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 44, this.index = 0});
  final String name;
  final double size;
  final int index;

  static const _grads = [
    [Color(0xFFA79BFF), Color(0xFF6C5CE7)],
    [Color(0xFF7DE3C3), Color(0xFF12B886)],
    [Color(0xFFFFC870), Color(0xFFF59F00)],
    [Color(0xFFFF9DB5), Color(0xFFF0466E)],
    [Color(0xFF8CC8FF), Color(0xFF3B9EF5)],
    [Color(0xFFC5B5FF), Color(0xFF8B5CF6)],
    [Color(0xFF9BE7F0), Color(0xFF0EA5B7)],
  ];

  @override
  Widget build(BuildContext context) {
    final g = _grads[(index.abs() + name.codeUnits.fold<int>(0, (a, b) => a + b)) % _grads.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(size * 0.34)),
      alignment: Alignment.center,
      child: Text(initials(name), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, math.min(2, parts.first.length)).toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class IconBox extends StatelessWidget {
  const IconBox(this.icon, {super.key, required this.fg, required this.bg, this.size = 38});
  final IconData icon;
  final Color fg, bg;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.32)),
        child: Icon(icon, color: fg, size: size * 0.5),
      );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.pal.ink2)),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -.2))),
          ?trailing,
        ]),
      );
}

/// Big gradient header at the top of a home screen.
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.child, this.gradient, this.bottomPad = 76});
  final Widget child;
  final Gradient? gradient;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(gradient: gradient ?? p.hero, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32))),
      child: Stack(
        children: [
          Positioned(
            right: -100,
            top: -110,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x55F5A524), Color(0x00F5A524)])),
            ),
          ),
          SafeArea(bottom: false, child: Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad), child: child)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(children: [
        const Floaty(child: Mascot(size: 110, book: false, cap: false)),
        const SizedBox(height: 14),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const SkeletonList();
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          IconBox(Icons.wifi_off_rounded, fg: p.danger, bg: p.dangerTint, size: 60),
          const SizedBox(height: 12),
          Text(tr('err_load'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(error.toString(), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 14),
          SoftButton(label: tr('retry'), icon: Icons.refresh_rounded, onPressed: onRetry),
        ]),
      ),
    );
  }
}

/// Loads data with [load] and shows loading / error / content.
/// Pull down to reload.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _f = widget.load();

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _f = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _f,
      builder: (context, s) {
        if (s.hasError) return ErrorView(error: s.error!, onRetry: _reload);
        if (s.connectionState != ConnectionState.done) return const LoadingView();
        return RefreshIndicator(color: context.pal.brand, onRefresh: _reload, child: widget.builder(context, s.data as T, _reload));
      },
    );
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, tr('copied'));
}

/// Back button in a white rounded box (used on inner screens).
class BackBox extends StatelessWidget {
  const BackBox({super.key, this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return IconBtn(icon: Icons.chevron_left_rounded, size: 26, tooltip: tr('back'), onTap: onTap ?? () => Navigator.of(context).maybePop(), color: p.ink);
  }
}

/// Top bar for inner screens: back box + title (+ optional trailing).
class InnerBar extends StatelessWidget implements PreferredSizeWidget {
  const InnerBar({super.key, required this.title, this.trailing, this.showBack = true, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(70);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
        child: Row(children: [
          if (showBack) ...[const BackBox(), const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.4)),
              if (subtitle != null)
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.pal.muted)),
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }
}

/// Row of 7 round day buttons (Mon..Sun) for picking class days.
class DayPicker extends StatelessWidget {
  const DayPicker({super.key, required this.selected, required this.onChanged});
  final List<int> selected;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final d = i + 1;
        final on = selected.contains(d);
        return Column(children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              final next = [...selected];
              on ? next.remove(d) : next.add(d);
              next.sort();
              onChanged(next);
            },
            child: AnimatedScale(
              scale: on ? 1.08 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? p.brand : p.cardAlt,
                  border: Border.all(color: on ? p.brand : p.border),
                  boxShadow: on ? [BoxShadow(color: p.brand.withValues(alpha: .45), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -6)] : null,
                ),
                alignment: Alignment.center,
                child: Text(letters[i], style: TextStyle(fontWeight: FontWeight.w800, color: on ? Colors.white : p.muted)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(dayShort(d), style: TextStyle(fontSize: 10, color: p.muted, fontWeight: FontWeight.w600)),
        ]);
      }),
    );
  }
}

/// Choice chip that animates when picked.
class ChoicePill extends StatelessWidget {
  const ChoicePill({super.key, required this.label, required this.selected, required this.onTap, this.sub});
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: sub == null ? 10 : 7),
        decoration: BoxDecoration(
          color: selected ? p.brand : p.card,
          borderRadius: BorderRadius.circular(sub == null ? 999 : 16),
          border: Border.all(color: selected ? p.brand : p.border),
          boxShadow: selected ? p.glow(p.brand) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: selected ? Colors.white : p.ink2)),
            if (sub != null) Text(sub!, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: selected ? Colors.white70 : p.muted)),
          ],
        ),
      ),
    );
  }
}

/// Segmented control with a sliding white pill.
class Segmented extends StatelessWidget {
  const Segmented({super.key, required this.items, required this.index, required this.onChanged});
  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.cardAlt, borderRadius: BorderRadius.circular(15), border: Border.all(color: p.border)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / items.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(11), boxShadow: p.shadow)),
          ),
          Row(
            children: List.generate(items.length, (i) {
              final on = i == index;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: SizedBox(
                    height: 42,
                    child: Center(
                      child: Text(items[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, color: on ? p.brand : p.muted, fontSize: 13.5)),
                    ),
                  ),
                ),
              );
            }),
          ),
        ]);
      }),
    );
  }
}

/// The VidyaDesk book logo in a gold rounded square.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF8B7CF6), Color(0xFF6C5CE7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(size * 0.32),
          boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withValues(alpha: .4), blurRadius: size * .5, offset: Offset(0, size * .2), spreadRadius: -size * .2)],
        ),
        child: Icon(Icons.school_outlined, color: Colors.white, size: size * 0.54),
      );
}

/// Google "G" logo, drawn with the four brand colours.
class GoogleG extends StatelessWidget {
  const GoogleG({super.key, this.size = 22});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48;
    canvas.scale(s, s);
    Path p(String d) => _svgPath(d);
    canvas.drawPath(p('M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z'), Paint()..color = const Color(0xFFEA4335));
    canvas.drawPath(p('M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z'), Paint()..color = const Color(0xFF4285F4));
    canvas.drawPath(p('M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z'), Paint()..color = const Color(0xFFFBBC05));
    canvas.drawPath(p('M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z'), Paint()..color = const Color(0xFF34A853));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tiny SVG path reader (M, L, H, V, C, S, Z; absolute and relative).
Path _svgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvCcSsZz]|-?\d*\.?\d+(?:e-?\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = 'M';
  double x = 0, y = 0, cx = 0, cy = 0, sx = 0, sy = 0;
  double n() => double.parse(tokens[i++]);
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.moveTo(x, y);
        sx = x;
        sy = y;
        cmd = rel ? 'l' : 'L';
        break;
      case 'L':
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.lineTo(x, y);
        break;
      case 'H':
        x = (rel ? x : 0) + n();
        path.lineTo(x, y);
        break;
      case 'V':
        y = (rel ? y : 0) + n();
        path.lineTo(x, y);
        break;
      case 'C':
        final x1 = (rel ? x : 0) + n(), y1 = (rel ? y : 0) + n();
        final x2 = (rel ? x : 0) + n(), y2 = (rel ? y : 0) + n();
        final ex = (rel ? x : 0) + n(), ey = (rel ? y : 0) + n();
        path.cubicTo(x1, y1, x2, y2, ex, ey);
        cx = x2;
        cy = y2;
        x = ex;
        y = ey;
        continue;
      case 'S':
        final x1 = 2 * x - cx, y1 = 2 * y - cy;
        final x2 = (rel ? x : 0) + n(), y2 = (rel ? y : 0) + n();
        final ex = (rel ? x : 0) + n(), ey = (rel ? y : 0) + n();
        path.cubicTo(x1, y1, x2, y2, ex, ey);
        cx = x2;
        cy = y2;
        x = ex;
        y = ey;
        continue;
      case 'Z':
        path.close();
        x = sx;
        y = sy;
        break;
    }
    cx = x;
    cy = y;
  }
  return path;
}

/// Google button in Google's own style (white, grey border, colour G).
class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : onPressed,
        child: Container(
          height: 56,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)), 
          child: Center(
            child: busy
                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: p.brand))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutBack,
                      builder: (context, v, child) => Transform.rotate(angle: (1 - v) * -math.pi, child: Transform.scale(scale: v, child: child)),
                      child: const GoogleG(),
                    ),
                    const SizedBox(width: 12),
                    Text(label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: p.ink)),
                  ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design system 2.0 pieces
// ---------------------------------------------------------------------------

/// Page with the soft lavender wash at the top. Use instead of a plain Scaffold body.
class PageBg extends StatelessWidget {
  const PageBg({super.key, required this.child, this.height = 340});
  final Widget child;
  final double height;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Stack(children: [
      Positioned(left: 0, right: 0, top: 0, height: height, child: DecoratedBox(decoration: BoxDecoration(gradient: p.pageTop))),
      Positioned.fill(child: child),
    ]);
  }
}

/// Scaffold + lavender background + optional top bar.
class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key, required this.body, this.title, this.subtitle, this.back = true, this.actions = const [], this.bottom, this.topBar});
  final Widget body;
  final String? title, subtitle;
  final bool back;
  final List<Widget> actions;
  final Widget? bottom;
  final Widget? topBar;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: p.bg,
      body: PageBg(
        child: Column(children: [
          if (topBar != null) topBar! else if (title != null) InnerBar(title: title!, subtitle: subtitle, showBack: back, trailing: actions.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: _spaced(actions))),
          Expanded(child: body),
          if (bottom != null) SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 14), child: bottom)),
        ]),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> w) => [for (var i = 0; i < w.length; i++) ...[if (i > 0) const SizedBox(width: 10), w[i]]];
}

/// Square white button with an icon (top bars). Optional red dot.
class IconBtn extends StatelessWidget {
  const IconBtn({super.key, required this.icon, required this.onTap, this.dot = false, this.filled = false, this.tooltip, this.size = 21, this.color, this.box = 44});
  final IconData icon;
  final VoidCallback? onTap;
  final bool dot, filled;
  final String? tooltip;
  final double size, box;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final w = Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: filled ? p.brand : p.card,
        borderRadius: BorderRadius.circular(box * .32),
        boxShadow: filled ? p.glow(p.brand) : p.shadow,
        border: filled ? null : Border.all(color: p.border),
      ),
      child: Stack(alignment: Alignment.center, children: [
        Icon(icon, size: size, color: filled ? Colors.white : (color ?? p.ink)),
        if (dot)
          Positioned(
            top: box * .22,
            right: box * .24,
            child: Container(width: 9, height: 9, decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle, border: Border.all(color: p.card, width: 2))),
          ),
      ]),
    );
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Pressable(child: w),
      ),
    );
  }
}

/// Shrinks a little while pressed — button feedback.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child});
  final Widget child;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(scale: _down ? .95 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
      );
}

/// Round filter chip; filled purple when selected.
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? p.brand : p.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? p.brand : p.border),
          boxShadow: selected ? p.glow(p.brand) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: selected ? Colors.white : p.ink2), const SizedBox(width: 5)],
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: selected ? Colors.white : p.ink2)),
        ]),
      ),
    );
  }
}

/// Horizontal scrolling row of filter pills.
class PillBar extends StatelessWidget {
  const PillBar({super.key, required this.items, required this.index, required this.onChanged, this.padding = const EdgeInsets.symmetric(horizontal: 18)});
  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => Center(child: FilterPill(label: items[i], selected: i == index, onTap: () => onChanged(i))),
        ),
      );
}

/// Small stat card: coloured icon tile, big number, label.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.value, required this.label, required this.fg, required this.bg, this.suffix = '', this.empty = false, this.onTap});
  final IconData icon;
  final int value;
  final String label, suffix;
  final Color fg, bg;
  final bool empty;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconBox(icon, fg: fg, bg: bg, size: 34),
        const SizedBox(height: 10),
        empty
            ? Text('—', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.muted))
            : CountUp(value, suffix: suffix, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.6)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Purple gradient feature card with soft circles.
class FeatureCard extends StatelessWidget {
  const FeatureCard({super.key, required this.child, this.onTap, this.gradient, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final g = gradient ?? p.hero;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(Gap.rCard), boxShadow: p.glow(const Color(0xFF5545D6))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Gap.rCard),
          child: Stack(children: [
            const Positioned(right: -34, top: -44, child: _Bubble(170, .09)),
            const Positioned(right: 40, bottom: -64, child: _Bubble(120, .07)),
            Padding(padding: padding, child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child)),
          ]),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.size, this.alpha);
  final double size, alpha;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha)));
}

/// Glassy chip used on purple cards.
class GlassChip extends StatelessWidget {
  const GlassChip(this.text, {super.key, this.icon, this.solid = false});
  final String text;
  final IconData? icon;
  final bool solid;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: solid ? Colors.white : Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: solid ? const Color(0xFF4B3FC4) : Colors.white), const SizedBox(width: 5)],
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: solid ? const Color(0xFF4B3FC4) : Colors.white)),
        ]),
      );
}

/// Grey shimmer placeholders while data loads.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.rows = 5});
  final int rows;
  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget box(double w, double h, double r) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              gradient: LinearGradient(
                begin: Alignment(-1 + _c.value * 3, 0),
                end: Alignment(_c.value * 3, 0),
                colors: [p.cardAlt, p.border, p.cardAlt],
              ),
            ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < widget.rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                box(42, 42, 13),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [box(160, 12, 6), const SizedBox(height: 8), box(100, 10, 6)])),
                box(46, 22, 999),
              ]),
            ),
          ),
      ],
    );
  }
}

/// Small coloured dot + label (chart legends).
class LegendDot extends StatelessWidget {
  const LegendDot(this.color, this.label, {super.key});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.pal.muted)),
      ]);
}

/// Bars that grow up — simple weekly chart. [values] are 0..100.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.values, required this.labels, this.highlight = -1, this.height = 100});
  final List<int?> values;
  final List<String> labels;
  final int highlight;
  final double height;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      height: height + 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final v = values[i];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (v != null && i == highlight)
                  Text('$v%', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: p.brand)),
                const SizedBox(height: 3),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (v ?? 0) / 100),
                  duration: Duration(milliseconds: 700 + i * 80),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => Container(
                    height: v == null ? 6 : (height - 18) * t + 6,
                    decoration: BoxDecoration(
                      color: v == null ? p.cardAlt : (i == highlight ? p.brand : p.brandTint),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(labels[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: i == highlight ? p.brand : p.muted)),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

/// Divider line in the card colour.
class Line extends StatelessWidget {
  const Line({super.key});
  @override
  Widget build(BuildContext context) => Container(height: 1, color: context.pal.border);
}

/// Opaque page background: lavender at the top fading into the page colour.
/// Every route is wrapped in this, and scaffolds stay transparent on top of it.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.top, p.bg, p.bg], stops: const [0, .38, 1]),
      ),
      child: child,
    );
  }
}
