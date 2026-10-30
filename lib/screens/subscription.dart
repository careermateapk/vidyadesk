import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/plan.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/push.dart';
import '../services/receipt.dart' show buildPlanReceipt;
import '../services/upi.dart';
import '../ui/mascot.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'onboarding.dart' show roleIcon, roleName;
import 'file_sheet.dart';
import 'owner.dart';
import 'owner2.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String planName(Plan p) => tr('plan_${p.name}');

Color planColor(Palette p, Plan x) => switch (x) {
      Plan.basic => const Color(0xFF0EA5B7),
      Plan.standard => p.brand,
      Plan.pro => const Color(0xFFE08A00),
      Plan.trial => p.success,
    };

String _date(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// Admin's plan badge: FREE TRIAL / BASIC / STANDARD / PRO / NO PLAN.
class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key, required this.st, this.small = false});
  final PlanStatus st;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final none = !st.active;
    final c = none ? p.muted : planColor(p, st.plan);
    final label = none ? tr('badge_no_plan') : tr('badge_${st.plan.name}');
    if (small) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
        child: const Icon(Icons.star_rounded, size: 13, color: Colors.white),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .4)),
      ]),
    );
  }
}

/// A glowing ring around the admin's photo, coloured by the plan:
/// trial grey · Basic teal · Standard purple-blue · Pro gold with stars ·
/// red and pulsing when 7 days or less are left.
class PlanRing extends StatefulWidget {
  const PlanRing({super.key, required this.st, required this.child, required this.size, this.stroke});
  final PlanStatus? st;
  final Widget child;
  /// Size of [child] (the photo).
  final double size;
  final double? stroke;
  @override
  State<PlanRing> createState() => _PlanRingState();
}

class _PlanRingState extends State<PlanRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.st;
    if (st == null) return widget.child;
    final w = widget.stroke ?? (widget.size * .075).clamp(3.0, 7.0);
    final total = widget.size + w * 2 + 4;
    final red = !st.active || st.daysLeft <= 7;
    final (List<Color> cols, Color glow, double turns) = red
        ? (const [Color(0xFFF0466E), Color(0xFFFF8FA8), Color(0xFFF0466E)], const Color(0xFFF0466E), 0)
        : switch (st.plan) {
            Plan.basic => (const [Color(0xFF0EA5B7), Color(0xFF5EEAD4), Color(0xFF0EA5B7)], const Color(0xFF0EA5B7), 2),
            Plan.standard => (const [Color(0xFF6C5CE7), Color(0xFFA79BFF), Color(0xFF3B9EF5), Color(0xFF6C5CE7)], const Color(0xFF6C5CE7), 3),
            Plan.pro => (const [Color(0xFFFFD27A), Color(0xFFFF9F43), Color(0xFFF0466E), Color(0xFFFFD27A), Color(0xFFFFF3C4), Color(0xFFFFD27A)], const Color(0xFFFF9F43), 4),
            Plan.trial => (const [Color(0xFFC9C6DC), Color(0xFFEFEDFA), Color(0xFFC9C6DC)], const Color(0x00000000), 0),
          };
    final pro = !red && st.plan == Plan.pro;
    final std = !red && st.plan == Plan.standard;
    return RepaintBoundary(
      child: SizedBox(
        width: total,
        height: total,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = _c.value;
            final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2 * (red ? 7.5 : 6));
            final glowA = red ? .25 + .6 * pulse : (st.plan == Plan.trial ? 0.0 : (pro ? .45 + .45 * pulse : .25 + .35 * pulse));
            return Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: Opacity(
                  opacity: red ? .45 + .55 * pulse : 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [if (glowA > 0) BoxShadow(color: glow.withValues(alpha: glowA), blurRadius: pro ? 18 : 12, spreadRadius: pro ? 1 : 0)]),
                    child: CustomPaint(painter: _RingArc(cols, w, t * math.pi * 2 * turns)),
                  ),
                ),
              ),
              Positioned.fill(child: Padding(padding: EdgeInsets.all(w + 2), child: ClipOval(child: child))),
              if (pro) ...[
                _star(total * .78, -total * .06, total * .26, (0.5 + 0.5 * math.sin(t * math.pi * 2 * 5))),
                _star(-total * .02, total * .72, total * .16, (0.5 + 0.5 * math.sin(t * math.pi * 2 * 5 + 2))),
              ],
              if (std)
                Builder(builder: (_) {
                  final a = t * math.pi * 2 * 3 - math.pi / 2;
                  final r = total / 2 - w / 2;
                  return Positioned(
                    left: total / 2 + r * math.cos(a) - 4,
                    top: total / 2 + r * math.sin(a) - 4,
                    child: Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFA79BFF).withValues(alpha: .9), blurRadius: 8)])),
                  );
                }),
            ]);
          },
          child: SizedBox(width: widget.size, height: widget.size, child: widget.child),
        ),
      ),
    );
  }

  Widget _star(double x, double y, double s, double v) => Positioned(
        left: x,
        top: y,
        child: IgnorePointer(
          child: Opacity(
            opacity: .35 + .65 * v,
            child: Transform.scale(scale: .7 + .4 * v, child: Icon(Icons.auto_awesome, size: s, color: const Color(0xFFFFD27A))),
          ),
        ),
      );
}

class _RingArc extends CustomPainter {
  _RingArc(this.cols, this.w, this.angle);
  final List<Color> cols;
  final double w, angle;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..shader = SweepGradient(colors: cols, transform: GradientRotation(angle)).createShader(r));
  }

  @override
  bool shouldRepaint(_RingArc o) => o.angle != angle || o.cols != cols;
}

/// Does the coaching's plan include [f]? (true while the plan is unknown).
/// Is a feature switched on by the VidyaDesk owner for this coaching?
bool featureOn(BuildContext context, String key) {
  final app = context.appRead;
  return app.config.on(key, app.active?.instituteId ?? '');
}

bool planHas(BuildContext context, Feature f) => context.appRead.plan?.has(f) ?? true;

/// Opens [go] only if the plan has [f]; otherwise shows what plan is needed.
Future<void> gated(BuildContext context, Feature f, VoidCallback go) async {
  if (planHas(context, f)) return go();
  // Only the admin hears about plans; others simply can't open it.
  if (context.appRead.active?.role == Role.admin) await showUpgradeSheet(context, need: minPlan(f));
}

/// Admin: "this needs Standard / Pro". Others: "ask your admin".
Future<void> showUpgradeSheet(BuildContext context, {required Plan need, String? title, String? sub, (int, int)? usage}) {
  final app = context.appRead;
  final admin = app.active?.role == Role.admin;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) {
      final p = c.pal;
      final col = planColor(p, need);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconBox(usage == null ? Icons.lock_rounded : Icons.groups_rounded, fg: p.warn, bg: p.warnTint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title ?? trf('needs_plan', {'plan': planName(need)}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  if (usage != null) Text('${usage.$1} / ${usage.$2}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            if (usage != null) ...[
              const SizedBox(height: 12),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: 1, minHeight: 10, color: p.warn, backgroundColor: p.warnTint)),
            ],
            const SizedBox(height: 12),
            Text(sub ?? (admin ? trf('needs_plan_admin', {'plan': planName(need)}) : tr('needs_plan_member')), style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
            if (admin) ...[
              const SizedBox(height: 14),
              AppCard(
                border: col,
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(child: Text(planName(need), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  Text('${rupees(planPrice[need]!.$1)}${tr('per_month_short')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                ]),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: tr('upgrade_now'),
                onPressed: () {
                  Navigator.pop(c);
                  push(context, PlansScreen(m: app.active!, pick: need));
                },
              ),
            ] else ...[
              const SizedBox(height: 14),
              SoftButton(label: tr('ok'), onPressed: () => Navigator.pop(c)),
            ],
          ]),
        ),
      );
    },
  );
}

/// Before approving [r]: is there room in the plan? Shows the upgrade sheet when full.
Future<bool> checkPlanLimit(BuildContext context, Membership r) async {
  if (r.role != Role.student && r.role != Role.teacher) return true;
  final app = context.appRead;
  final plan = app.plan;
  if (plan == null) return true;
  final max = r.role == Role.student ? plan.maxStudents : plan.maxTeachers;
  if (max < 0) return true;
  List<Membership> all;
  try {
    all = await app.backend.members(r.instituteId);
  } catch (_) {
    return true;
  }
  final used = all.where((x) => x.role == r.role && x.approved).length;
  if (used < max) return true;
  if (!context.mounted) return false;
  if (app.active?.role != Role.admin) {
    toast(context, tr('limit_ask_admin'));
    return false;
  }
  final next = paidPlans.firstWhere((x) => (r.role == Role.student ? planLimit[x]!.$1 : planLimit[x]!.$2) < 0 || (r.role == Role.student ? planLimit[x]!.$1 : planLimit[x]!.$2) > max, orElse: () => Plan.pro);
  await showUpgradeSheet(
    context,
    need: next,
    usage: (used, max),
    title: trf(r.role == Role.student ? 'plan_full_students' : 'plan_full_teachers', {'plan': planName(plan.plan)}),
    sub: app.active?.role == Role.admin ? trf('plan_full_sub', {'name': r.name, 'plan': planName(next)}) : tr('needs_plan_member'),
  );
  return false;
}

// ---------------------------------------------------------------------------
// Banner on the home screen
// ---------------------------------------------------------------------------

class PlanBanner extends StatelessWidget {
  const PlanBanner({super.key, required this.m});
  final Membership m;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final plan = app.plan;
    if (plan == null) return const SizedBox.shrink();
    final p = context.pal;
    final admin = m.role == Role.admin;

    if (plan.grace) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          color: p.dangerTint,
          padding: const EdgeInsets.all(14),
          onTap: admin ? () => push(context, PlansScreen(m: m)) : null,
          child: Row(children: [
            IconBox(Icons.warning_amber_rounded, fg: p.danger, bg: p.card),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('plan_ended'), style: TextStyle(fontWeight: FontWeight.w800, color: p.danger, fontSize: 15)),
                const SizedBox(height: 2),
                Text(trf(admin ? 'grace_admin' : 'grace_member', {'n': '${plan.graceLeft}'}), style: TextStyle(color: p.ink2, fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600)),
              ]),
            ),
            if (admin) Icon(Icons.chevron_right_rounded, color: p.danger),
          ]),
        ),
      );
    }
    if (!admin) {
      return const SizedBox.shrink();
    }
    if (!plan.warn) return const SizedBox.shrink();
    final total = plan.trial ? trialDays : 30;
    final left = plan.daysLeft.clamp(0, total);
    const ink = Color(0xFF6B4400);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        gradient: const LinearGradient(colors: [Color(0xFFFFE7B0), Color(0xFFFFD27A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const IconBox(Icons.schedule_rounded, fg: Color(0xFFB76E00), bg: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trf(plan.trial ? 'trial_left' : 'plan_left', {'n': '$left', 'plan': planName(plan.plan)}), style: const TextStyle(fontWeight: FontWeight.w800, color: ink, fontSize: 15)),
                const SizedBox(height: 2),
                Text(trf('plan_ends_on', {'date': _date(plan.endDate)}), style: const TextStyle(color: Color(0xFF8A5A00), fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: 1 - left / total, minHeight: 7, color: const Color(0xFFB76E00), backgroundColor: Colors.white.withValues(alpha: .55)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => push(context, PlansScreen(m: m)),
              child: Text(plan.trial ? tr('choose_plan') : tr('renew_now'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plans
// ---------------------------------------------------------------------------

// ---------- small animated pieces used by the plan screens ----------

/// A number that counts up (or to its new value) smoothly. ₹ when [money].
class _CountTo extends StatelessWidget {
  const _CountTo(this.value, {super.key, required this.style, this.money = false, this.ms = 900});
  final int value;
  final TextStyle style;
  final bool money;
  final int ms;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: Duration(milliseconds: ms),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text(money ? rupees(v.round()) : '${v.round()}', style: style),
      );
}

/// Ring that fills from 0 to [pct] when the screen opens.
class _Ring extends StatelessWidget {
  const _Ring({required this.pct, required this.child, this.size = 124, this.colors = const [Color(0xFFFFD27A), Color(0xFFFF9F43)]});
  final double pct;
  final Widget child;
  final double size;
  final List<Color> colors;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: pct.clamp(0, 1)),
        duration: const Duration(milliseconds: 1300),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => SizedBox(width: size, height: size, child: CustomPaint(painter: _RingPainter(v, colors), child: Center(child: c))),
        child: child,
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.colors);
  final double v;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    const w = 12.0;
    final r = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = Colors.white.withValues(alpha: .18));
    if (v <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(colors: colors, startAngle: -math.pi / 2, endAngle: math.pi * 1.5, transform: const GradientRotation(-math.pi / 2)).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v;
}

/// A soft light that sweeps across [child] again and again (premium shine).
class _Shine extends StatefulWidget {
  const _Shine({super.key, required this.child, this.radius = 26, this.seconds = 3});
  final Widget child;
  final double radius;
  final int seconds;
  @override
  State<_Shine> createState() => _ShineState();
}

class _ShineState extends State<_Shine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(seconds: widget.seconds))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Stack(children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) {
                  // sweep during the first 45% of each loop, then rest
                  final t = (_c.value / .45).clamp(0.0, 1.0);
                  return FractionalTranslation(
                    translation: Offset(-1.2 + 2.4 * Curves.easeInOut.transform(t), 0),
                    child: Transform.rotate(
                      angle: .35,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .16), Colors.white.withValues(alpha: 0)], stops: const [.3, .5, .7]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ]),
      );
}

/// Little stars that twinkle (on dark cards).
class _Twinkle extends StatefulWidget {
  const _Twinkle({required this.spots});
  final List<(double, double, double)> spots; // (x 0..1, y 0..1, size)
  @override
  State<_Twinkle> createState() => _TwinkleState();
}

class _TwinkleState extends State<_Twinkle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: LayoutBuilder(
          builder: (_, box) => AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Stack(children: [
              for (var i = 0; i < widget.spots.length; i++)
                Positioned(
                  left: widget.spots[i].$1 * box.maxWidth,
                  top: widget.spots[i].$2 * box.maxHeight,
                  child: Opacity(
                    opacity: (.25 + .75 * (0.5 + 0.5 * math.sin((_c.value + i * .29) * math.pi * 2))).clamp(0.0, 1.0),
                    child: Icon(Icons.auto_awesome, size: widget.spots[i].$3, color: Colors.white),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// Shakes [child] gently once when it appears (a warning).
class _ShakeOnce extends StatelessWidget {
  const _ShakeOnce({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        builder: (_, v, c) => Transform.translate(offset: Offset(math.sin(v * math.pi * 6) * 6 * (1 - v), 0), child: c),
        child: child,
      );
}

/// Rupees saved by paying yearly, and how many months that is.
(int, int) yearlySaving(Plan x) {
  final pr = planPrice[x]!;
  final save = pr.$1 * 12 - pr.$2;
  return (save < 0 ? 0 : save, pr.$1 <= 0 ? 0 : (save / pr.$1).round());
}

IconData planIcon(Plan x) => switch (x) {
      Plan.basic => Icons.menu_book_rounded,
      Plan.standard => Icons.bolt_rounded,
      Plan.pro => Icons.star_rounded,
      Plan.trial => Icons.card_giftcard_rounded,
    };

// ---------------------------------------------------------------------------
// Plans
// ---------------------------------------------------------------------------

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, required this.m, this.pick});
  final Membership m;
  final Plan? pick;
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> with SingleTickerProviderStateMixin {
  bool _yearly = true;
  late Plan _plan = widget.pick ?? context.appRead.plan?.renewPlan ?? Plan.standard;
  int _v = 0;
  // clouds drift slowly
  late final AnimationController _sky = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();

  @override
  void dispose() {
    _sky.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final ok = await payForPlan(context, widget.m, _plan, _yearly);
    if (ok && mounted) setState(() => _v++);
  }

  String _short(DateTime d) => '${d.day} ${tr('m${d.month}')}';

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final st = app.plan;
    final amt = planAmount(_plan, _yearly);
    final pro = _plan == Plan.pro;
    final now = DateTime.now();

    // Heading and the three steps depend on where the coaching stands.
    final trial = st == null || st.trial;
    final ended = st != null && !st.active;
    final left = st == null ? 0 : st.daysLeft.clamp(0, 9999);
    final (String h1, String h2, String chip) = trial && !ended
        ? (tr('sky_trial_h1'), trf('sky_trial_h2', {'n': '$left'}), tr('sky_chip_free'))
        : ended
            ? (tr('sky_end_h1'), tr('sky_end_h2'), tr('sky_chip_safe'))
            : (trf('sky_paid_h1', {'n': '$left'}), tr('sky_paid_h2'), tr('sky_chip_add'));
    final sub = trial && !ended ? tr('sky_trial_sub') : (ended ? tr('sky_end_sub') : tr('sky_paid_sub'));
    final end = st?.endDate ?? now.add(const Duration(days: trialDays));
    final newEnd = DateTime.fromMillisecondsSinceEpoch(extendUntil(st?.until ?? 0, _yearly));
    final steps = trial && !ended
        ? [
            (Icons.check_rounded, tr('sky_t1'), tr('sky_t1s')),
            (Icons.notifications_rounded, trf('sky_t2', {'date': _short(end.subtract(const Duration(days: 7)))}), tr('sky_t2s')),
            (Icons.lock_rounded, trf('sky_t3', {'date': _short(end)}), tr('sky_t3s')),
          ]
        : [
            (Icons.check_rounded, tr('sky_p1'), tr('sky_p1s')),
            (Icons.schedule_rounded, ended ? tr('sky_p2_end') : trf('sky_p2', {'date': _short(end)}), ended ? tr('sky_p2s_end') : trf('sky_p2s', {'n': '$left'})),
            (Icons.star_rounded, trf('sky_p3', {'date': prettyDate(newEnd)}), trf('sky_p3s', {'plan': planName(_plan), 'per': _yearly ? tr('one_year') : tr('one_month')})),
          ];
    final fill = trial && !ended ? (1 - left / trialDays).clamp(.12, 1.0) : .34;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F1FF),
      bottomNavigationBar: Container(
        color: const Color(0xFFF3F1FF),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _Shine(
                radius: 20,
                seconds: 3,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      _pay();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 62,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: pro
                            ? const LinearGradient(colors: [Color(0xFF1E1A45), Color(0xFF3D2E8C)])
                            : const LinearGradient(colors: [Color(0xFF5B6CF0), Color(0xFF4B3FC4)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                        border: pro ? Border.all(color: const Color(0xFFFFD27A), width: 1.5) : null,
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(
                          '${pro ? '★ ' : ''}${trf('take_plan_short', {'plan': planName(_plan)})} · ${rupees(amt)}${_yearly ? tr('per_year') : tr('per_month')}',
                          style: TextStyle(color: pro ? const Color(0xFFFFD27A) : Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
                        ),
                        Text(tr('sky_cta_sub'), style: const TextStyle(color: Color(0xDDFFFFFF), fontWeight: FontWeight.w700, fontSize: 11.5)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(tr('sky_footer'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
      body: Stack(children: [
        // sky
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 360,
          child: AnimatedBuilder(
            animation: _sky,
            builder: (_, __) {
              final t = _sky.value * math.pi * 2;
              Widget cloud(double x, double y, double w, double h, double speed) => Positioned(
                    left: x + math.sin(t * speed) * 18,
                    top: y,
                    child: Container(
                      width: w,
                      height: h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: RadialGradient(colors: [Colors.white, Colors.white.withValues(alpha: .9), Colors.white.withValues(alpha: .35)], stops: const [0, .6, 1]),
                        boxShadow: [BoxShadow(color: const Color(0xFF4B3FC4).withValues(alpha: .15), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                    ),
                  );
              return Stack(clipBehavior: Clip.hardEdge, children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF5B6CF0), Color(0xFF7E8BF7), Color(0xFFBFC6FF), Color(0xFFF3F1FF)], stops: [0, .38, .72, 1]),
                    ),
                  ),
                ),
                Positioned(left: 0, right: 0, top: -60, child: Center(child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Colors.white.withValues(alpha: .5), Colors.white.withValues(alpha: 0)]))))),
                cloud(-50, 130, 180, 62, 1),
                cloud(260, 115, 200, 68, -1),
                cloud(-30, 185, 210, 72, -1),
                cloud(120, 175, 220, 78, 1),
                cloud(250, 195, 190, 70, 1),
                cloud(30, 235, 330, 82, -1),
                const Positioned(left: 0, right: 0, bottom: 0, height: 90, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00F3F1FF), Color(0xFFF3F1FF)])))),
              ]);
            },
          ),
        ),
        SafeArea(
          child: Loader<List<SubPayment>>(
            key: ValueKey(_v),
            pullToRefresh: false,
            load: () => app.backend.mySubPayments(widget.m.instituteId),
            builder: (context, pays, reload) {
              final waiting = pays.where((x) => x.status == 'pending').toList();
              final lastNoAny = pays.where((x) => (x.status == 'rejected' || x.status == 'reversed') && DateTime.now().millisecondsSinceEpoch - x.decidedAt < 15 * 86400000).firstOrNull;
              final lastNo = lastNoAny == null || pays.any((x) => x.started && x.createdAt > lastNoAny.createdAt) ? null : lastNoAny;
              return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 20), children: [
                Row(children: [
                  Material(
                    color: Colors.white.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () => Navigator.maybePop(context), child: const SizedBox(width: 44, height: 44, child: Icon(Icons.chevron_left_rounded, size: 28))),
                  ),
                  const Spacer(),
                  Material(
                    color: Colors.white.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(99),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => push(context, ComparePlansScreen(m: widget.m)),
                      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), child: Text(tr('compare_short'), style: TextStyle(color: p.brandDeep, fontWeight: FontWeight.w800, fontSize: 13))),
                    ),
                  ),
                ]),
                // Vidu flies in
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutBack,
                  builder: (_, v, c) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, -40 * (1 - v)), child: c)),
                  child: const Center(child: Mascot(size: 150, book: false, mood: OwlMood.hello)),
                ),
                Text(h1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, height: 1.15, letterSpacing: -.5)),
                ShaderMask(
                  shaderCallback: (r) => (trial && !ended ? const LinearGradient(colors: [Color(0xFF5545D6), Color(0xFF8B7CF6)]) : const LinearGradient(colors: [Color(0xFFE8930C), Color(0xFFF0466E)])).createShader(r),
                  child: Text(h2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -.5, color: Colors.white)),
                ),
                const SizedBox(height: 8),
                Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                  Text(sub, style: TextStyle(color: p.ink2, fontWeight: FontWeight.w700, fontSize: 13)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: p.success, borderRadius: BorderRadius.circular(7)),
                    child: Text(chip, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11.5)),
                  ),
                ]),
                const SizedBox(height: 14),
                if (waiting.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      color: p.successTint,
                      padding: const EdgeInsets.all(14),
                      child: Text(trf('sub_waiting', {'plan': planName(planFrom(waiting.first.plan)), 'amt': rupees(waiting.first.amount), 'utr': waiting.first.utr}),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.ink2, height: 1.4)),
                    ),
                  ),
                if (lastNo != null && waiting.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ShakeOnce(
                      child: AppCard(
                        color: p.dangerTint,
                        padding: const EdgeInsets.all(14),
                        child: Text(trf('sub_not_found', {'plan': planName(planFrom(lastNo.plan)), 'amt': rupees(lastNo.amount)}), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.danger, height: 1.4)),
                      ),
                    ),
                  ),
                _Timeline(steps: steps, fill: fill),
                const SizedBox(height: 12),
                _PlanTabs(plan: _plan, onChanged: (x) => setState(() => _plan = x)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _PeriodCard(plan: _plan, yearly: false, selected: !_yearly, onTap: () => setState(() => _yearly = false))),
                  const SizedBox(width: 10),
                  Expanded(child: _PeriodCard(plan: _plan, yearly: true, selected: _yearly, onTap: () => setState(() => _yearly = true))),
                ]),
                const SizedBox(height: 12),
                _PlanIncludes(plan: _plan),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

/// "How the plan works": three steps with a bar that fills down.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps, required this.fill});
  final List<(IconData, String, String)> steps;
  final double fill;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white),
        boxShadow: [BoxShadow(color: const Color(0xFF4B3FC4).withValues(alpha: .14), blurRadius: 30, offset: const Offset(0, 14), spreadRadius: -12)],
      ),
      child: Column(children: [
        Text(tr('sky_how'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 1)),
        const SizedBox(height: 10),
        Stack(children: [
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 10 : 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(steps[i].$2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    Text(steps[i].$3, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 11.5, height: 1.35)),
                  ]),
                ),
            ]),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 22,
            child: LayoutBuilder(
              builder: (_, box) => TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fill),
                duration: const Duration(milliseconds: 1500),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Stack(children: [
                  Positioned.fill(child: Container(decoration: BoxDecoration(color: const Color(0xFFE6E3FA), borderRadius: BorderRadius.circular(12)))),
                  Positioned(left: 0, right: 0, top: 0, height: box.maxHeight * v, child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B7CF6)], begin: Alignment.topCenter, end: Alignment.bottomCenter), borderRadius: BorderRadius.circular(12)))),
                  for (var i = 0; i < steps.length; i++)
                    Positioned(
                      left: 3,
                      top: box.maxHeight * (i / steps.length) + 4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: Icon(steps[i].$1, size: 11, color: const Color(0xFF6C5CE7)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Divider(height: 1, color: p.border),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          for (final x in [(Icons.groups_rounded, tr('students')), (Icons.currency_rupee_rounded, tr('sky_upi')), (Icons.support_agent_rounded, tr('sky_support'))])
            Row(children: [Icon(x.$1, size: 14, color: p.ink2), const SizedBox(width: 4), Text(x.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.ink2))]),
        ]),
      ]),
    );
  }
}

class _PlanTabs extends StatelessWidget {
  const _PlanTabs({required this.plan, required this.onChanged});
  final Plan plan;
  final ValueChanged<Plan> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final i = paidPlans.indexOf(plan);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .75), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white)),
      child: Stack(children: [
        Positioned.fill(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            alignment: Alignment(-1 + i * 1.0, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: plan == Plan.pro ? null : Colors.white,
                  gradient: plan == Plan.pro ? const LinearGradient(colors: [Color(0xFF1E1A45), Color(0xFF3D2E8C)]) : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: p.brand.withValues(alpha: .25), blurRadius: 12, offset: const Offset(0, 5))],
                ),
              ),
            ),
          ),
        ),
        Row(children: [
          for (final x in paidPlans)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(x);
                },
                child: SizedBox(
                  height: 40,
                  child: Center(
                    child: Text(
                      '${planName(x)}${x == Plan.standard ? ' 🔥' : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: x == plan ? (x == Plan.pro ? const Color(0xFFFFD27A) : p.brand) : p.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.plan, required this.yearly, required this.selected, required this.onTap});
  final Plan plan;
  final bool yearly, selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pr = planPrice[plan]!;
    final (save, months) = yearlySaving(plan);
    final amount = yearly ? pr.$2 : pr.$1;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: .65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? p.brand : Colors.white, width: selected ? 2.5 : 1.5),
            boxShadow: selected ? [BoxShadow(color: p.brand.withValues(alpha: .3), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -10)] : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 16,
                height: 16,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? p.brand : p.border, width: 2)),
                alignment: Alignment.center,
                child: selected ? Container(width: 8, height: 8, decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle)) : null,
              ),
              const SizedBox(width: 7),
              Text((yearly ? tr('yearly') : tr('monthly')).toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: .6, color: p.ink2)),
            ]),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: _CountTo(amount, money: true, ms: 500, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -.6, height: 1)))),
              Text(yearly ? tr('per_year_short') : tr('per_month_short'), style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 2),
            Text(
              yearly && months > 0 ? '≈ ${rupees((pr.$2 / 12).round())}${tr('per_month_short')} · ${trf('n_months_free_plain', {'n': '$months'})}' : tr('stop_any_time'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        if (yearly && save > 0)
          Positioned(
            right: 10,
            top: -11,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [p.brand, p.brand2]), borderRadius: BorderRadius.circular(8)),
              child: Text(trf('rs_save', {'amt': rupees(save)}), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900)),
            ),
          ),
      ]),
    );
  }
}

/// What the chosen plan adds (small chips).
class _PlanIncludes extends StatelessWidget {
  const _PlanIncludes({required this.plan});
  final Plan plan;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final i = paidPlans.indexOf(plan);
    final lim = planLimit[plan]!;
    final own = [
      for (final f in planFeatureRows)
        if ((i == 0 && f.$2) || (i == 1 && f.$3 && !f.$2) || (i == 2 && f.$4 && !f.$3)) f.$1,
    ].take(5);
    final dark = plan == Plan.pro;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Wrap(key: ValueKey(plan), spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
        _Chip(
          text: '${lim.$1 < 0 ? '∞' : lim.$1} ${tr('students')} · ${lim.$2 < 0 ? '∞' : lim.$2} ${tr('teachers')}',
          icon: Icons.groups_rounded,
          fg: dark ? const Color(0xFF8A5200) : p.brand,
          bg: dark ? const Color(0xFFFFF3C4) : p.brandTint,
        ),
        for (final k in own) _Chip(text: tr('${k}_short'), icon: Icons.check_rounded, fg: dark ? const Color(0xFF8A5200) : p.brand, bg: dark ? const Color(0xFFFFF3C4) : p.brandTint),
        if (i > 0) _Chip(text: trf('all_of_plan_short', {'plan': planName(paidPlans[i - 1])}), icon: Icons.add_rounded, fg: p.muted, bg: Colors.white),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// My plan (dashboard)
// ---------------------------------------------------------------------------

/// The coaching's VidyaDesk plan: days left, usage, what's included, payments.
class MyPlanScreen extends StatelessWidget {
  const MyPlanScreen({super.key, required this.m});
  final Membership m;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final st = app.plan;
    return Scaffold(
      appBar: InnerBar(title: tr('my_plan'), subtitle: m.instituteName),
      body: Loader<(List<SubPayment>, List<Membership>)>(
        pullToRefresh: false,
        key: ValueKey(st?.until ?? 0),
        load: () async => (
          await app.backend.mySubPayments(m.instituteId),
          await app.backend.members(m.instituteId).catchError((_) => <Membership>[]),
        ),
        builder: (context, d, reload) {
          final pays = d.$1;
          final mem = d.$2;
          final studs = mem.where((x) => x.role == Role.student && x.approved).length;
          final teach = mem.where((x) => x.role == Role.teacher && x.approved).length;
          final lastPaid = pays.where((x) => x.started).firstOrNull;
          final total = st == null ? 30 : (st.trial ? trialDays : (lastPaid?.yearly ?? false) ? 365 : 30);
          final left = st == null ? 0 : st.daysLeft.clamp(0, 9999);
          final pct = total == 0 ? 0.0 : (left / total).clamp(0.0, 1.0);
          final ended = st != null && !st.active;
          final nextUp = st == null || st.trial ? Plan.standard : (st.plan == Plan.pro ? null : paidPlans[(paidPlans.indexOf(st.plan) + 1).clamp(0, 2)]);
          return RefreshIndicator(
            onRefresh: () async {
              await app.loadInstitute();
              await reload();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
              children: [
                if (st != null)
                  Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: const Color(0xFF4B3FC4).withValues(alpha: .45), blurRadius: 34, offset: const Offset(0, 18), spreadRadius: -16)]),
                    child: _Shine(
                      radius: 28,
                      seconds: 4,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: ended
                              ? const LinearGradient(colors: [Color(0xFF7A1F3D), Color(0xFFC23A5E)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                              : const LinearGradient(colors: [Color(0xFF2B2370), Color(0xFF4B3FC4), Color(0xFF6C5CE7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        ),
                        child: Stack(clipBehavior: Clip.none, children: [
                          Positioned(right: -70, top: -70, child: Container(width: 190, height: 190, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .07)))),
                          Positioned(left: -50, bottom: -80, child: Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .05)))),
                          const Positioned.fill(child: _Twinkle(spots: [(.8, .02, 12), (.92, .3, 8), (.06, .7, 9)])),
                          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(children: [
                              _Ring(
                                pct: pct,
                                colors: ended ? const [Color(0xFFFFFFFF), Color(0xFFFFB3C4)] : const [Color(0xFFFFD27A), Color(0xFFFF9F43)],
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  _CountTo(left, ms: 1300, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1, letterSpacing: -1.5)),
                                  Text(tr('days_left_short'), style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 12, fontWeight: FontWeight.w700)),
                                ]),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(planIcon(st.plan), size: 13, color: Colors.white),
                                      const SizedBox(width: 4),
                                      Text(planName(st.plan).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: .5)),
                                    ]),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(ended ? tr('plan_ended') : (st.trial ? tr('trial_running') : tr('plan_running')),
                                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -.4, height: 1.15)),
                                  const SizedBox(height: 2),
                                  Text(trf('till_date', {'date': _date(st.endDate)}), style: TextStyle(color: Colors.white.withValues(alpha: .8), fontWeight: FontWeight.w600, fontSize: 13)),
                                  if (!ended) ...[
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF4ADE80), boxShadow: [BoxShadow(color: const Color(0xFF4ADE80).withValues(alpha: .5), blurRadius: 6, spreadRadius: 2)])),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(tr('auto_reminder_7'), maxLines: 2, style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 11.5, fontWeight: FontWeight.w700))),
                                    ]),
                                  ],
                                ]),
                              ),
                            ]),
                            const SizedBox(height: 18),
                            Row(children: [
                              Expanded(
                                child: _HeroBtn(
                                  label: st.trial ? tr('choose_plan') : tr('renew_now'),
                                  icon: Icons.refresh_rounded,
                                  bg: Colors.white,
                                  fg: const Color(0xFF4B3FC4),
                                  onTap: () => push(context, PlansScreen(m: m, pick: st.renewPlan)),
                                ),
                              ),
                              if (nextUp != null && !st.trial) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _HeroBtn(
                                    label: trf('take_plan_short', {'plan': planName(nextUp)}),
                                    icon: Icons.star_rounded,
                                    gradient: const LinearGradient(colors: [Color(0xFFFFD27A), Color(0xFFFF9F43)]),
                                    fg: const Color(0xFF3A2300),
                                    onTap: () => push(context, PlansScreen(m: m, pick: nextUp)),
                                  ),
                                ),
                              ],
                            ]),
                          ]),
                        ]),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                SectionTitle(tr('usage_title')),
                Row(children: [
                  for (final u in [
                    (Icons.groups_rounded, tr('students'), studs, st?.maxStudents ?? -1, p.brand, p.brand2),
                    (Icons.school_rounded, tr('teachers'), teach, st?.maxTeachers ?? -1, p.success, const Color(0xFF4ADE80)),
                  ]) ...[
                    if (u.$2 == tr('teachers')) const SizedBox(width: 10),
                    Expanded(
                      child: AppCard(
                        padding: const EdgeInsets.all(14),
                        radius: 20,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            IconBox(u.$1, fg: u.$5, bg: u.$5.withValues(alpha: .12), size: 34),
                            const SizedBox(width: 8),
                            Expanded(child: Text(u.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 13))),
                          ]),
                          const SizedBox(height: 10),
                          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            _CountTo(u.$3, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -.8, height: 1)),
                            Text(' / ${u.$4 < 0 ? '∞' : u.$4}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
                          ]),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              height: 10,
                              child: Stack(children: [
                                Container(color: p.cardAlt),
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: u.$4 <= 0 ? (u.$4 < 0 ? .08 : 0) : (u.$3 / u.$4).clamp(0.0, 1.0)),
                                  duration: const Duration(milliseconds: 1100),
                                  curve: Curves.easeOutCubic,
                                  builder: (_, v, __) => FractionallySizedBox(
                                    widthFactor: v,
                                    child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: LinearGradient(colors: [u.$5, u.$6]))),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(u.$4 < 0 ? tr('no_limit') : trf('n_more_can_join', {'n': '${(u.$4 - u.$3).clamp(0, 99999)}'}),
                              style: TextStyle(color: u.$4 > 0 && u.$3 >= u.$4 * .9 ? p.danger : p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 20),
                SectionTitle(tr('in_this_plan')),
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final f in planFeatureRows)
                      if (st == null || st.trial || [f.$2, f.$3, f.$4][(paidPlans.indexOf(st.plan)).clamp(0, 2)])
                        _Chip(text: tr('${f.$1}_short'), icon: Icons.check_rounded, fg: p.brand, bg: p.brandTint)
                      else
                        _Chip(
                          text: '${tr('${f.$1}_short')} · ${planName(f.$3 ? Plan.standard : Plan.pro)}',
                          icon: Icons.lock_outline_rounded,
                          fg: p.muted,
                          bg: p.cardAlt,
                          onTap: () => push(context, PlansScreen(m: m, pick: f.$3 ? Plan.standard : Plan.pro)),
                        ),
                  ]),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => push(context, ComparePlansScreen(m: m, students: studs)),
                    icon: Icon(Icons.table_chart_outlined, color: p.brand, size: 18),
                    label: Text(tr('compare_plans'), style: TextStyle(color: p.brand, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 6),
                SectionTitle(tr('payment_history')),
                if (pays.isEmpty) Text(tr('no_plan_payments'), style: TextStyle(color: p.muted)),
                if (pays.isNotEmpty)
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Column(children: [
                      for (var i = 0; i < pays.length; i++) _PayRow(x: pays[i], first: i == 0),
                    ]),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroBtn extends StatelessWidget {
  const _HeroBtn({required this.label, required this.icon, required this.fg, required this.onTap, this.bg, this.gradient});
  final String label;
  final IconData icon;
  final Color fg;
  final Color? bg;
  final Gradient? gradient;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Ink(
          height: 48,
          decoration: BoxDecoration(color: bg, gradient: gradient, borderRadius: BorderRadius.circular(15)),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 6),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 14.5))),
            ]),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.icon, required this.fg, required this.bg, this.onTap});
  final String text;
  final IconData icon;
  final Color fg, bg;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: onTap != null ? Border.all(color: context.pal.border) : null),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
        ),
      );
}

class _PayRow extends StatelessWidget {
  const _PayRow({required this.x, required this.first});
  final SubPayment x;
  final bool first;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ok = x.started;
    final c = ok ? p.success : (x.status == 'pending' ? p.warn : p.danger);
    final t = ok ? p.successTint : (x.status == 'pending' ? p.warnTint : p.dangerTint);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: p.border))),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: t, borderRadius: BorderRadius.circular(12)),
          child: Icon(ok ? Icons.check_rounded : (x.status == 'pending' ? Icons.hourglass_top_rounded : Icons.close_rounded), color: c, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${planName(planFrom(x.plan))} · ${x.yearly ? tr('one_year') : tr('one_month')}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('${_date(DateTime.fromMillisecondsSinceEpoch(x.createdAt))}${x.via.isEmpty ? '' : ' · ${x.via}'}', style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(x.demo ? 'DEMO' : rupees(x.amount), style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(tr('pay_status_${x.status}'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
        ]),
        if (ok) ...[
          const SizedBox(width: 6),
          IconBtn(icon: Icons.download_rounded, box: 36, size: 18, tooltip: tr('receipt'), onTap: () => planReceipt(context, x)),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Compare
// ---------------------------------------------------------------------------

class ComparePlansScreen extends StatelessWidget {
  const ComparePlansScreen({super.key, this.m, this.students = -1});
  final Membership? m;
  /// Students now (for the "near your limit" warning); -1 = unknown.
  final int students;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = context.app.plan;
    final cur = st == null || st.trial ? null : st.plan;
    final max = st?.maxStudents ?? -1;
    final near = cur != null && students >= 0 && max > 0 && students >= (max * .85).floor();
    Widget cell(Widget c, int k) => Expanded(
          child: Container(
            height: 42,
            color: paidPlans[k] == cur ? p.brandTint : null,
            alignment: Alignment.center,
            child: c,
          ),
        );
    Widget row(String label, List<Widget> v, {bool first = false}) => Container(
          decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: p.border))),
          child: Row(children: [
            Expanded(flex: 5, child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(label, maxLines: 2, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink2)))),
            Expanded(flex: 12, child: Row(children: [for (var k = 0; k < v.length; k++) cell(v[k], k)])),
          ]),
        );
    const b = TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5);
    final next = cur == null || cur == Plan.pro ? null : paidPlans[paidPlans.indexOf(cur) + 1];
    return Scaffold(
      appBar: InnerBar(title: tr('compare_plans'), subtitle: tr('compare_sub')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
        if (near)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _ShakeOnce(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFF4DB), Color(0xFFFFE6EC)]), borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFE8930C))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(trf('n_of_max_students', {'n': '$students', 'max': '$max'}), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7A4A00), fontSize: 14.5)),
                      Text(trf('near_limit_sub', {'n': '${(max - students).clamp(0, 99999)}'}), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF9A6A20), fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        AppCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(children: [
              Row(children: [
                const Expanded(flex: 5, child: SizedBox(height: 48)),
                Expanded(
                  flex: 12,
                  child: Row(children: [
                    for (var k = 0; k < 3; k++)
                      Expanded(
                        child: Container(
                          height: 48,
                          color: paidPlans[k] == cur ? p.brandTint : null,
                          alignment: Alignment.center,
                          child: Text(planName(paidPlans[k]), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: planColor(p, paidPlans[k]))),
                        ),
                      ),
                  ]),
                ),
              ]),
              row(tr('students'), [for (final x in paidPlans) Text(planLimit[x]!.$1 < 0 ? '∞' : '${planLimit[x]!.$1}', style: b)]),
              row(tr('teachers'), [for (final x in paidPlans) Text(planLimit[x]!.$2 < 0 ? '∞' : '${planLimit[x]!.$2}', style: b)]),
              for (final f in planFeatureRows)
                row(tr('${f.$1}_short'), [
                  for (final has in [f.$2, f.$3, f.$4]) has ? Icon(Icons.check_rounded, size: 19, color: p.success) : Text('—', style: TextStyle(color: p.muted.withValues(alpha: .5), fontWeight: FontWeight.w900)),
                ]),
              row(tr('per_month_label'), [for (final x in paidPlans) Text(rupees(planPrice[x]!.$1), style: b)]),
              row(tr('one_year'), [for (final x in paidPlans) FittedBox(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(rupees(planPrice[x]!.$2), style: b)))]),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        if (m != null && cur != null)
          Row(children: [
            Expanded(child: SoftButton(label: trf('keep_plan', {'plan': planName(cur)}), height: 52, onPressed: () => push(context, PlansScreen(m: m!, pick: cur)))),
            if (next != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _HeroBtn(
                  label: trf('take_plan_short', {'plan': planName(next)}),
                  icon: Icons.star_rounded,
                  gradient: const LinearGradient(colors: [Color(0xFFFF9F43), Color(0xFFF0466E)]),
                  fg: Colors.white,
                  onTap: () => push(context, PlansScreen(m: m!, pick: next)),
                ),
              ),
            ],
          ])
        else
          AppCard(
            color: p.successTint,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.star_rounded, color: p.success),
              const SizedBox(width: 10),
              Expanded(child: Text(tr('trial_note'), style: TextStyle(color: p.success, fontWeight: FontWeight.w700, fontSize: 13))),
            ]),
          ),
      ]),
    );
  }
}


// ---------------------------------------------------------------------------
// Paying for a plan (UPI to the VidyaDesk owner — no UTR to type)
// ---------------------------------------------------------------------------

class _PayPlanSheet extends StatefulWidget {
  const _PayPlanSheet({required this.plan, required this.yearly, required this.demo});
  final Plan plan;
  final bool yearly, demo;
  @override
  State<_PayPlanSheet> createState() => _PayPlanSheetState();
}

class _PayPlanSheetState extends State<_PayPlanSheet> {
  int _app = 0;
  final _code = TextEditingController();
  Coupon? _cp;
  String? _cpErr;
  bool _checking = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _cpErr = null;
    });
    try {
      final c = await context.appRead.backend.coupon(code);
      final why = c == null ? 'none' : c.problem(widget.plan.name, widget.yearly);
      setState(() {
        _cp = why.isEmpty ? c : null;
        _cpErr = why.isEmpty ? null : tr('coupon_$why');
      });
      if (why.isEmpty) HapticFeedback.mediumImpact();
    } catch (_) {
      setState(() => _cpErr = tr('coupon_none'));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final lim = planLimit[widget.plan]!;
    final full = planAmount(widget.plan, widget.yearly);
    final off = _cp?.discount(full) ?? 0;
    final amount = full - off;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${planName(widget.plan)} · ${widget.yearly ? tr('one_year') : tr('one_month')}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            '${lim.$1 < 0 ? tr('unlimited_students') : trf('n_students', {'n': '${lim.$1}'})} · ${lim.$2 < 0 ? tr('unlimited_teachers') : trf('n_teachers', {'n': '${lim.$2}'})}',
            style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (featureOn(context, 'coupons')) Row(children: [
            Expanded(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) {
                  if (_cp != null || _cpErr != null) {
                    setState(() {
                      _cp = null;
                      _cpErr = null;
                    });
                  }
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('coupon_hint'),
                  prefixIcon: Icon(Icons.local_offer_outlined, color: _cp != null ? p.success : p.muted),
                  errorText: _cpErr,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: _cp != null
                  ? Center(child: Tag(tr('coupon_applied'), fg: p.success, bg: p.successTint, leading: Icon(Icons.check_rounded, size: 14, color: p.success)))
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: p.brand,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: p.brand.withValues(alpha: .5),
                        disabledForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      onPressed: _checking ? null : _apply,
                      child: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(tr('apply')),
                    ),
            ),
          ]),
          const SizedBox(height: 10),
          if (off > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(children: [
                Row(children: [Expanded(child: Text(tr('plan'), style: TextStyle(color: p.muted))), Text(rupees(full))]),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(child: Text('${tr('coupon')} ${_cp!.code}${_cp!.pct ? ' (${_cp!.value}%)' : ''}', style: TextStyle(color: p.success, fontWeight: FontWeight.w700))),
                  Text('− ${rupees(off)}', style: TextStyle(color: p.success, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('total'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
                  Text(rupees(amount), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                ]),
              ),
              if (widget.yearly && off == 0) Tag(tr('two_months_free'), fg: p.success, bg: p.successTint),
              if (widget.demo) ...[const SizedBox(width: 6), Tag('DEMO', fg: p.warn, bg: p.warnTint)],
            ]),
          ),
          if (!widget.demo) ...[
            const SizedBox(height: 12),
            FieldLabel(tr('pay_with')),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: upiApps.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => setState(() => _app = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 92,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: _app == i ? p.brandTint : p.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _app == i ? p.brand : p.border, width: _app == i ? 2 : 1),
                    ),
                    child: Column(children: [
                      UpiIcon(upiApps[i], size: 40),
                      const SizedBox(height: 6),
                      Text(upiApps[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ]),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          PrimaryButton(
            label: widget.demo ? tr('demo_pay') : trf('pay_amt_upi', {'amt': rupees(amount)}),
            icon: Icons.bolt_rounded,
            arrow: false,
            onPressed: () => Navigator.pop(context, (widget.demo ? _chooserApp : upiApps[_app.clamp(0, upiApps.length - 1)], _cp)),
          ),
          const SizedBox(height: 8),
          Text(widget.demo ? tr('demo_pay_note') : tr('no_utr_note'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12.5)),
        ]),
      ),
    );
  }
}

const _chooserApp = UpiApp('Demo', '', 'D', 0xFF6C5CE7);

/// Pays for [plan] and starts it. Returns true when the plan started (or is waiting for a check).
Future<bool> payForPlan(BuildContext context, Membership m, Plan plan, bool yearly) async {
  final app = context.appRead;
  final demo = app.isDemo || demoPayEmails.contains((app.profile?.email ?? app.signedIn?.email ?? '').toLowerCase());
  final picked = await showModalBottomSheet<(UpiApp, Coupon?)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PayPlanSheet(plan: plan, yearly: yearly, demo: demo),
  );
  if (picked == null || !context.mounted) return false;
  final upiApp = picked.$1;
  final cp = picked.$2;
  final coupon = cp?.code ?? '';
  final full = planAmount(plan, yearly);
  final amount = full - (cp?.discount(full) ?? 0);
  var paidOk = false;
  var ref = '';
  if (demo || amount <= 0) {
    paidOk = true;
    ref = 'DEMO${DateTime.now().millisecondsSinceEpoch % 100000000}';
  } else {
    final res = await payByUpi(
      vpa: ownerUpi,
      payee: ownerPayee,
      amount: amount,
      note: 'VidyaDesk ${plan.name} ${yearly ? 'year' : 'month'}',
      ref: 'VDP${DateTime.now().millisecondsSinceEpoch}',
      package: upiApp.package,
      activity: upiApp.activity,
    );
    if (!context.mounted) return false;
    switch (res.status) {
      case UpiStatus.noApp:
        toast(context, trf('upi_no_app', {'app': upiApp.name}));
        return false;
      case UpiStatus.failed:
        toast(context, tr('upi_failed'));
        return false;
      case UpiStatus.success:
        paidOk = true;
        ref = res.utr;
      case UpiStatus.unknown:
        // The UPI app did not say. Ask once (no UTR needed).
        final cut = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(tr('was_money_cut')),
            content: Text(tr('was_money_cut_sub')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('no_not_paid'))),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('yes_paid'))),
            ],
          ),
        );
        if (cut != true || !context.mounted) return false;
        ref = res.utr;
    }
  }
  if (!context.mounted) return false;
  SubPayment pay;
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Expanded(child: Text(tr('starting_plan'), style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ),
    ),
  );
  try {
    pay = await app.backend.startPlan(admin: m, plan: plan.name, yearly: yearly, paidOk: paidOk, ref: ref, via: demo ? 'Demo' : (amount <= 0 ? 'Coupon' : upiApp.name), coupon: coupon);
  } catch (e) {
    nav.pop();
    if (context.mounted) toast(context, tr('err_plan_start'));
    return false;
  }
  nav.pop();
  app.loadInstitute(); // in the background — the celebration shows right away
  if (!context.mounted) return true;
  if (pay.started) {
    await push(context, PlanSuccessScreen(pay: pay));
  } else {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.hourglass_top_rounded, color: c.pal.warn, size: 40),
        title: Text(tr('sub_sent_title')),
        content: Text(tr('sub_wait_body'), textAlign: TextAlign.center),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('ok')))],
      ),
    );
  }
  return true;
}

/// Opens the receipt of a plan payment (download / share).
Future<void> planReceipt(BuildContext context, SubPayment p) => showFileSheet(context, title: tr('receipt'), files: [
      FileOption(
        label: 'PDF',
        name: 'VidyaDesk_${planFrom(p.plan).name}_${DateTime.fromMillisecondsSinceEpoch(p.createdAt).toIso8601String().substring(0, 10)}.pdf',
        mime: 'application/pdf',
        make: () => buildPlanReceipt(p, planLabel: planName(planFrom(p.plan))),
        text: 'VidyaDesk plan receipt',
      ),
    ]);

/// Confetti + owl after a plan starts.
class PlanSuccessScreen extends StatefulWidget {
  const PlanSuccessScreen({super.key, required this.pay});
  final SubPayment pay;
  @override
  State<PlanSuccessScreen> createState() => _PlanSuccessScreenState();
}

class _PlanSuccessScreenState extends State<PlanSuccessScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pay = widget.pay;
    final plan = planFrom(pay.plan);
    final until = DateTime.fromMillisecondsSinceEpoch(pay.newUntil);
    final rows = [
      (tr('plan'), '${planName(plan)} · ${pay.yearly ? tr('one_year') : tr('one_month')}'),
      (tr('amount'), pay.demo ? '${rupees(0)} (DEMO)' : rupees(pay.amount)),
      if (pay.via.isNotEmpty) (tr('paid_via'), pay.via),
      if (pay.utr.isNotEmpty) (tr('upi_ref'), pay.utr),
      (tr('valid_till'), _date(until)),
    ];
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: IgnorePointer(child: Confetti(animation: _a))),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(22, 30, 22, 30), children: [
            ScaleTransition(
              scale: CurvedAnimation(parent: _a, curve: const Interval(0, .35, curve: Curves.elasticOut)),
              child: const Center(child: Mascot(size: 180, book: false, mood: OwlMood.happy)),
            ),
            const SizedBox(height: 6),
            FadeIn(child: Text(trf('plan_started_title', {'plan': planName(plan)}), textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
            const SizedBox(height: 6),
            Text(trf('plan_started_sub', {'inst': pay.instituteName, 'date': _date(until)}), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 14, height: 1.5)),
            const SizedBox(height: 20),
            AppCard(
              child: Column(children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(child: Text(r.$1, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))),
                      Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: SoftButton(label: tr('receipt'), icon: Icons.download_rounded, onPressed: () => planReceipt(context, pay))),
              const SizedBox(width: 10),
              Expanded(child: PrimaryButton(label: tr('lets_start'), arrow: false, onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst))),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Falling confetti pieces.
class Confetti extends StatelessWidget {
  const Confetti({super.key, required this.animation});
  final Animation<double> animation;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: animation, builder: (_, _) => CustomPaint(painter: _ConfettiPainter(animation.value)));
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);
  final double t;
  static const _colors = [Color(0xFF6C5CE7), Color(0xFF12B886), Color(0xFFE8930C), Color(0xFFF0466E), Color(0xFF3B9EF5)];
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 70; i++) {
      final seed = (i * 9301 + 49297) % 233280 / 233280.0;
      final x = ((i * 37) % 100) / 100 * size.width + 30 * math.sin(t * 6 + i);
      final y = -40 + (t * (0.9 + seed)) * (size.height + 80) - (i % 7) * 30;
      if (y < -30 || y > size.height + 20) continue;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 8 * (seed - .5) + i);
      final paint = Paint()..color = _colors[i % 5].withValues(alpha: (1.2 - t).clamp(0, 1));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 7 + (i % 3) * 3, height: 11 + (i % 4) * 2), const Radius.circular(2)), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Locked app
// ---------------------------------------------------------------------------

class PlanLockedScreen extends StatelessWidget {
  const PlanLockedScreen({super.key, required this.m});
  final Membership m;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final st = app.plan!;
    final inst = app.inst;
    final admin = m.role == Role.admin;
    final others = app.memberships.where((x) => x.id != m.id && x.status != MemberStatus.rejected && x.instituteId != m.instituteId).toList();
    final phone = (inst?.ownerPhone.isNotEmpty ?? false) ? inst!.ownerPhone : (inst?.phone ?? '');
    final renew = st.renewPlan;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: app.loadInstitute,
          child: ListView(padding: const EdgeInsets.fromLTRB(22, 30, 22, 30), children: [
            const Center(child: Mascot(size: 160, book: false, mood: OwlMood.sad)),
            const SizedBox(height: 8),
            Text(admin ? tr('locked_admin_title') : tr('locked_member_title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              admin ? trf('locked_admin_sub', {'inst': m.instituteName, 'plan': planName(st.plan), 'date': _date(st.endDate)}) : trf('locked_member_sub', {'inst': m.instituteName}),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 18),
            if (!admin && ((inst?.ownerName.isNotEmpty ?? false) || phone.isNotEmpty))
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Avatar(inst?.ownerName.isNotEmpty == true ? inst!.ownerName : tr('the_admin'), size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(inst?.ownerName.isNotEmpty == true ? inst!.ownerName : tr('the_admin'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${tr('role_admin')} · ${m.instituteName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ]),
                  ),
                  if (phone.isNotEmpty) ...[
                    IconBtn(icon: Icons.chat_rounded, color: p.success, tooltip: 'WhatsApp', onTap: () => openWhatsApp(context, phone, trf('renew_ask_text', {'inst': m.instituteName}))),
                    const SizedBox(width: 8),
                    IconBtn(icon: Icons.call_rounded, color: p.brand, tooltip: tr('call'), onTap: () => callPhone(context, phone)),
                  ],
                ]),
              ),
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.shield_rounded, color: p.success),
                const SizedBox(width: 10),
                Expanded(child: Text(trf(admin ? 'data_safe_admin' : 'data_safe_member', {'n': '${st.dataLeft.clamp(0, keepDataDays)}'}), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              ]),
            ),
            if (admin) ...[
              const SizedBox(height: 10),
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: Text('${planName(renew)} · ${tr('one_year')}', style: const TextStyle(fontWeight: FontWeight.w800))),
                    Text(rupees(planPrice[renew]!.$2), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: Text(tr('or_one_month'), style: TextStyle(color: p.muted))),
                    Text(rupees(planPrice[renew]!.$1), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: tr('renew_upi'), icon: Icons.bolt_rounded, arrow: false, onPressed: () => push(context, PlansScreen(m: m, pick: renew))),
              const SizedBox(height: 4),
              TextButton(onPressed: () => push(context, PlansScreen(m: m)), child: Text(tr('see_other_plans'), style: TextStyle(color: p.brand, fontWeight: FontWeight.w800))),
            ] else ...[
              const SizedBox(height: 18),
              Text(tr('locked_everyone'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12.5)),
            ],
            const SizedBox(height: 10),
            SoftButton(label: tr('check_again'), icon: Icons.refresh_rounded, onPressed: () async {
              await app.loadInstitute();
              if (context.mounted && (app.plan?.locked ?? false)) toast(context, tr('still_locked'));
            }),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 18),
              SectionTitle(tr('your_other_roles')),
              for (final o in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    onTap: () => app.switchTo(o),
                    child: Row(children: [
                      IconBox(roleIcon(o.role), fg: p.brand, bg: p.brandTint),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${roleName(o.role)} · ${o.instituteName}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      Icon(Icons.chevron_right_rounded, color: p.muted),
                    ]),
                  ),
                ),
            ],
            const SizedBox(height: 6),
            TextButton(onPressed: app.signOut, child: Text(tr('logout'), style: TextStyle(color: p.muted))),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Owner panel (VidyaDesk owner only)
// ---------------------------------------------------------------------------

class OwnerPanelScreen extends StatefulWidget {
  const OwnerPanelScreen({super.key, this.standalone = false});
  /// Shown as the whole app (owner login): no back, with logout.
  final bool standalone;
  @override
  State<OwnerPanelScreen> createState() => _OwnerPanelScreenState();
}

class _OwnerPanelScreenState extends State<OwnerPanelScreen> {
  int _v = 0;
  final Set<String> _busy = {};

  Future<void> _decide(SubPayment s, bool ok) async {
    if (!ok) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s.status == 'auto' ? tr('stop_plan_q') : tr('payment_not_found_q')),
          content: Text(trf(s.status == 'auto' ? 'stop_plan_body' : 'payment_not_found_body', {'inst': s.instituteName, 'amt': rupees(s.amount)})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: c.pal.danger), onPressed: () => Navigator.pop(c, true), child: Text(s.status == 'auto' ? tr('stop_plan') : tr('not_received'))),
          ],
        ),
      );
      if (sure != true) return;
    }
    if (!mounted) return;
    setState(() => _busy.add(s.id));
    try {
      final wasAuto = s.status == 'auto';
      await context.appRead.backend.decideSubPayment(s, ok);
      if (!ok || !wasAuto) {
        Push.send(
          inst: s.instituteId,
          kind: 'plan',
          title: ok ? '✅ ${trf('push_plan_ok', {'plan': planName(planFrom(s.plan))})}' : '⚠️ ${tr('push_plan_no')}',
          body: ok ? s.instituteName : trf('push_plan_no_body', {'amt': rupees(s.amount)}),
          topics: [Push.admins(s.instituteId)],
        );
      }
      if (mounted) toast(context, ok ? (wasAuto ? tr('marked_ok') : trf('plan_started', {'inst': s.instituteName})) : (wasAuto ? tr('plan_stopped') : tr('marked_not_received')));
      if (ok && context.appRead.active?.instituteId == s.instituteId && mounted) await context.appRead.loadInstitute();
      if (mounted) setState(() => _v++);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy.remove(s.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(
        title: tr('owner_panel'),
        subtitle: tr('owner_panel_sub'),
        showBack: !widget.standalone,
        trailing: widget.standalone ? IconBtn(icon: Icons.logout_rounded, tooltip: tr('logout'), onTap: () => context.appRead.signOut()) : null,
      ),
      body: Loader<OwnerStats>(
        pullToRefresh: false,
        key: ValueKey(_v),
        load: () => context.appRead.backend.ownerStats(),
        builder: (context, d, reload) {
          final now = DateTime.now();
          final st = [for (final i in d.institutes) (i, PlanStatus(planFrom(i.plan), i.planUntil, now: now))];
          final paid = st.where((x) => !x.$2.trial && !x.$2.locked).length;
          final trial = st.where((x) => x.$2.trial && !x.$2.locked).length;
          final soon = st.where((x) => x.$2.daysLeft <= 7 && !x.$2.locked).toList()..sort((a, b) => a.$2.until.compareTo(b.$2.until));
          final locked = st.where((x) => x.$2.locked).toList();
          final sleeping = d.institutes.where((i) => !PlanStatus(planFrom(i.plan), i.planUntil).locked && (i.lastActive <= 0 || DateTime.now().millisecondsSinceEpoch - i.lastActive > 7 * 86400000)).length;
          Widget kpi(String label, String v, Color c) => Expanded(
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  radius: 18,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FittedBox(child: Text(v, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c))),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              );
          Widget instRow(Institute i, PlanStatus s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () async {
                    await push(context, CoachingDetailScreen(inst: i));
                    if (mounted) setState(() => _v++);
                  },
                  child: Row(children: [
                    Icon(Icons.schedule_rounded, color: s.locked ? p.danger : s.trial ? p.warn : planColor(p, s.plan), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${i.ownerName.isEmpty ? i.city : i.ownerName} · ${planName(s.plan)} · ${s.daysLeft >= 0 ? trf('n_days', {'n': '${s.daysLeft}'}) : tr('plan_ended')}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                    ),
                    i.blocked ? Tag(tr('blocked'), fg: p.danger, bg: p.dangerTint) : Tag('${tr('open')} ›', fg: p.brand, bg: p.brandTint),
                  ]),
                ),
              );
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
              children: [
                Row(children: [
                  kpi(tr('coachings'), '${d.institutes.length}', p.brand),
                  const SizedBox(width: 8),
                  kpi(tr('paid'), '$paid', p.success),
                  const SizedBox(width: 8),
                  kpi(tr('plan_trial'), '$trial', p.warn),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  kpi(tr('this_month_income'), rupees(d.monthIncome), p.indigo),
                  const SizedBox(width: 8),
                  kpi(tr('students'), '${d.students}', p.brand),
                  const SizedBox(width: 8),
                  kpi(tr('locked'), '${locked.length}', p.danger),
                ]),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: .95,
                  children: [
                    for (final t in [
                      (Icons.bar_chart_rounded, tr('earnings'), p.success, () => push(context, const EarningsScreen()), 0),
                      (Icons.currency_rupee_rounded, tr('prices'), p.brand, () => push(context, const PricesScreen()), 0),
                      (Icons.bedtime_outlined, tr('sleeping'), p.danger, () => push(context, const SleepingScreen()), sleeping),
                      (Icons.support_agent_rounded, tr('inbox'), p.indigo, () => push(context, const OwnerInboxScreen()), 0),
                      (Icons.local_offer_outlined, tr('coupons'), p.warn, () => push(context, const CouponsScreen()), 0),
                      (Icons.view_carousel_outlined, tr('banners'), p.indigo, () => push(context, const BannersScreen()), 0),
                      (Icons.campaign_outlined, tr('notice_to_all'), p.danger, () => showBroadcast(context), 0),
                      (Icons.auto_awesome_outlined, tr('whats_new_short'), p.brand, () => push(context, const NewsEditorScreen()), 0),
                      (Icons.toggle_on_outlined, tr('features'), p.success, () => push(context, const FlagsScreen()), 0),
                      (Icons.construction_rounded, tr('maintenance'), p.warn, () => push(context, const MaintenanceEditorScreen()), 0),
                      (Icons.download_rounded, tr('download'), p.success, () => push(context, const ExportScreen()), 0),
                    ])
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                        radius: 18,
                        onTap: t.$4,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          CountBadge(count: t.$5, child: Icon(t.$1, color: t.$3)),
                          const SizedBox(height: 6),
                          Text(t.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
                        ]),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SectionTitle(tr('check_payments'), trailing: d.pending.isEmpty ? null : Tag(trf('n_new', {'n': '${d.pending.length}'}), fg: p.danger, bg: p.dangerTint)),
                if (d.pending.isEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr('no_payments_waiting'), style: TextStyle(color: p.muted))),
                for (final s in d.pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      border: s.status == 'pending' ? p.warn : null,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                Text(s.instituteName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                if (s.demo) Tag('DEMO', fg: p.warn, bg: p.warnTint),
                              ]),
                              Text('${planName(planFrom(s.plan))} · ${s.yearly ? tr('one_year') : tr('one_month')} · ${s.adminName}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                              Text('${_date(DateTime.fromMillisecondsSinceEpoch(s.createdAt))} · ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(s.createdAt)).format(context)}${s.via.isEmpty ? '' : ' · ${s.via}'}',
                                  style: TextStyle(color: p.muted, fontSize: 12)),
                            ]),
                          ),
                          Text(rupees(s.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                        ]),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: s.status == 'auto' ? p.successTint : p.warnTint, borderRadius: BorderRadius.circular(10)),
                          child: Text(s.status == 'auto' ? tr('owner_auto_note') : tr('owner_pending_note'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s.status == 'auto' ? p.success : p.warn)),
                        ),
                        if (s.utr.isNotEmpty || s.phone.isNotEmpty)
                          Row(children: [
                            Expanded(child: SelectableText(s.utr.isEmpty ? '' : '${tr('upi_ref')} ${s.utr}', style: TextStyle(fontWeight: FontWeight.w700, color: p.ink2, letterSpacing: .3))),
                            if (s.utr.isNotEmpty) IconBtn(icon: Icons.copy_rounded, box: 36, size: 18, tooltip: tr('copy'), onTap: () => copyText(context, s.utr)),
                            if (s.phone.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              IconBtn(icon: Icons.call_rounded, box: 36, size: 18, tooltip: tr('call'), onTap: () => callPhone(context, s.phone)),
                            ],
                          ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: SoftButton(
                              label: s.status == 'auto' ? tr('stop_plan') : tr('not_received'),
                              height: 44,
                              color: p.dangerTint,
                              textColor: p.danger,
                              onPressed: _busy.contains(s.id) ? null : () => _decide(s, false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SoftButton(
                              label: s.status == 'auto' ? tr('money_ok') : tr('confirm_start'),
                              height: 44,
                              color: p.successTint,
                              textColor: p.success,
                              onPressed: _busy.contains(s.id) ? null : () => _decide(s, true),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                const SizedBox(height: 10),
                SectionTitle(tr('ending_soon')),
                if (soon.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr('none_ending'), style: TextStyle(color: p.muted))),
                for (final x in soon) instRow(x.$1, x.$2),
                if (locked.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SectionTitle(tr('locked_coachings')),
                  for (final x in locked) instRow(x.$1, x.$2),
                ],
                const SizedBox(height: 10),
                SectionTitle(tr('all_coachings')),
                for (final x in st..sort((a, b) => a.$1.name.compareTo(b.$1.name))) instRow(x.$1, x.$2),
              ],
            ),
          );
        },
      ),
    );
  }
}
