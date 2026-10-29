import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/plan.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/upi.dart';
import '../ui/mascot.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'payments.dart' show askUtr;

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

/// Does the coaching's plan include [f]? (true while the plan is unknown).
bool planHas(BuildContext context, Feature f) => context.appRead.plan?.has(f) ?? true;

/// Opens [go] only if the plan has [f]; otherwise shows what plan is needed.
Future<void> gated(BuildContext context, Feature f, VoidCallback go) async {
  if (planHas(context, f)) return go();
  await showUpgradeSheet(context, need: minPlan(f));
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
      // Teachers get a heads-up in the last 3 days.
      if (m.role != Role.teacher || plan.daysLeft > 3) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          color: p.warnTint,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(Icons.schedule_rounded, color: p.warn),
            const SizedBox(width: 10),
            Expanded(child: Text(trf('plan_ends_teacher', {'n': '${plan.daysLeft}'}), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.ink2))),
          ]),
        ),
      );
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

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, required this.m, this.pick});
  final Membership m;
  final Plan? pick;
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool _yearly = true;
  late Plan _plan = widget.pick ?? context.appRead.plan?.renewPlan ?? Plan.standard;
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final st = app.plan;
    final sub = st == null
        ? widget.m.instituteName
        : st.trial
            ? '${widget.m.instituteName} · ${trf('trial_days_left', {'n': '${st.daysLeft.clamp(0, 999)}'})}'
            : '${widget.m.instituteName} · ${planName(st.plan)} · ${st.active ? trf('plan_ends_on', {'date': _date(st.endDate)}) : tr('plan_ended')}';
    return Scaffold(
      appBar: InnerBar(
        title: tr('choose_plan'),
        subtitle: sub,
        trailing: IconBtn(icon: Icons.table_chart_outlined, tooltip: tr('compare_plans'), onTap: () => push(context, const ComparePlansScreen())),
      ),
      body: Loader<List<SubPayment>>(
        key: ValueKey(_v),
        load: () => app.backend.mySubPayments(widget.m.instituteId),
        builder: (context, pays, reload) {
          final waiting = pays.where((x) => x.status == 'pending').toList();
          final lastNo = pays.where((x) => x.status == 'rejected' && DateTime.now().millisecondsSinceEpoch - x.decidedAt < 7 * 86400000).firstOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
            children: [
              if (waiting.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    color: p.successTint,
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Icon(Icons.hourglass_top_rounded, color: p.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          trf('sub_waiting', {'plan': planName(planFrom(waiting.first.plan)), 'amt': rupees(waiting.first.amount), 'utr': waiting.first.utr}),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.ink2, height: 1.4),
                        ),
                      ),
                    ]),
                  ),
                ),
              if (lastNo != null && waiting.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    color: p.dangerTint,
                    padding: const EdgeInsets.all(14),
                    child: Text(trf('sub_not_found', {'utr': lastNo.utr}), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.danger, height: 1.4)),
                  ),
                ),
              _Segment(yearly: _yearly, onChanged: (v) => setState(() => _yearly = v)),
              const SizedBox(height: 12),
              for (final x in paidPlans)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PlanCard(plan: x, yearly: _yearly, selected: _plan == x, current: st != null && !st.trial && st.plan == x, onTap: () => setState(() => _plan = x)),
                ),
              const SizedBox(height: 4),
              PrimaryButton(
                label: trf('take_plan', {'plan': planName(_plan), 'amt': rupees(planAmount(_plan, _yearly)), 'per': _yearly ? tr('per_year') : tr('per_month')}),
                onPressed: () async {
                  final ok = await payForPlan(context, widget.m, _plan, _yearly);
                  if (ok && mounted) setState(() => _v++);
                },
              ),
              const SizedBox(height: 8),
              Text(tr('plans_footer'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              AppCard(
                color: p.cardAlt,
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('how_plan_ends'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final r in [('end_7', p.indigo), ('end_3', p.warn), ('end_0', p.danger), ('end_lock', p.muted)])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(padding: const EdgeInsets.only(top: 5), child: CircleAvatar(radius: 4, backgroundColor: r.$2)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tr(r.$1), style: TextStyle(color: p.ink2, fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600))),
                      ]),
                    ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.yearly, required this.onChanged});
  final bool yearly;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget seg(bool y, String t) => Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(y);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: yearly == y ? p.card : Colors.transparent, borderRadius: BorderRadius.circular(12), boxShadow: yearly == y ? [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 8, offset: const Offset(0, 2))] : null),
              child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: yearly == y ? p.ink : p.muted)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.cardAlt, borderRadius: BorderRadius.circular(15)),
      child: Row(children: [seg(false, tr('monthly')), seg(true, tr('yearly_free2'))]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.yearly, required this.selected, required this.current, required this.onTap});
  final Plan plan;
  final bool yearly, selected, current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final col = planColor(p, plan);
    final i = paidPlans.indexOf(plan);
    final lim = planLimit[plan]!;
    final price = planPrice[plan]!;
    final own = [
      for (final f in planFeatureRows)
        if ((i == 0 && f.$2) || (i == 1 && f.$3 && !f.$2) || (i == 2 && f.$4 && !f.$3)) f.$1,
    ].take(4);
    final tag = plan == Plan.standard ? tr('most_popular') : plan == Plan.pro ? tr('best_value') : '';
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? col : p.border, width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(color: col.withValues(alpha: .18), blurRadius: 0, spreadRadius: 4)] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconBox(plan == Plan.basic ? Icons.menu_book_rounded : plan == Plan.standard ? Icons.bolt_rounded : Icons.star_rounded, fg: col, bg: col.withValues(alpha: .13)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(planName(plan), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  if (current) Tag(tr('current_plan'), fg: p.success, bg: p.successTint) else if (tag.isNotEmpty) Tag(tag, fg: Colors.white, bg: col),
                ]),
                Text(
                  '${lim.$1 < 0 ? tr('unlimited_students') : trf('n_students', {'n': '${lim.$1}'})} · ${lim.$2 < 0 ? tr('unlimited_teachers') : trf('n_teachers', {'n': '${lim.$2}'})}',
                  style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(rupees(yearly ? price.$2 : price.$1), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(yearly ? '${tr('per_year')} · ≈${rupees((price.$2 / 12).round())}${tr('per_month_short')}' : tr('per_month'), style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ]),
          const SizedBox(height: 10),
          for (final k in own)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                Icon(Icons.check_rounded, size: 16, color: col),
                const SizedBox(width: 6),
                Expanded(child: Text(tr(k), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink2))),
              ]),
            ),
          if (i > 0)
            Row(children: [
              Icon(Icons.add_rounded, size: 16, color: p.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(trf('all_of_plan', {'plan': planName(paidPlans[i - 1])}), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.muted))),
            ]),
        ]),
      ),
    );
  }
}

class ComparePlansScreen extends StatelessWidget {
  const ComparePlansScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget cell(Widget c) => SizedBox(width: 58, child: Center(child: c));
    Widget row(String label, List<Widget> v, {bool bold = false, bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.border))),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: bold ? p.muted : p.ink2))),
            ...v.map(cell),
          ]),
        );
    TextStyle b = const TextStyle(fontWeight: FontWeight.w800, fontSize: 12);
    return Scaffold(
      appBar: InnerBar(title: tr('compare_plans'), subtitle: tr('compare_sub')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(color: p.cardAlt, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
              child: Row(children: [
                Expanded(child: Text(tr('feature'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
                for (final x in paidPlans) cell(Text(planName(x), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: planColor(p, x)))),
              ]),
            ),
            row(tr('per_month_label'), [for (final x in paidPlans) Text(rupees(planPrice[x]!.$1), style: b)], bold: true),
            row(tr('students'), [for (final x in paidPlans) Text(planLimit[x]!.$1 < 0 ? '∞' : '${planLimit[x]!.$1}', style: b)], bold: true),
            row(tr('teachers'), [for (final x in paidPlans) Text(planLimit[x]!.$2 < 0 ? '∞' : '${planLimit[x]!.$2}', style: b)], bold: true),
            for (var i = 0; i < planFeatureRows.length; i++)
              row(
                tr(planFeatureRows[i].$1),
                [
                  for (final (k, has) in [(0, planFeatureRows[i].$2), (1, planFeatureRows[i].$3), (2, planFeatureRows[i].$4)])
                    has ? Icon(Icons.check_rounded, size: 18, color: planColor(p, paidPlans[k])) : Text('—', style: TextStyle(color: p.border, fontWeight: FontWeight.w800)),
                ],
                last: i == planFeatureRows.length - 1,
              ),
          ]),
        ),
        const SizedBox(height: 12),
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
// Paying for a plan (UPI to the VidyaDesk owner, then UTR)
// ---------------------------------------------------------------------------

Future<UpiApp?> _pickApp(BuildContext context, int amount) => showModalBottomSheet<UpiApp>(
      context: context,
      builder: (c) {
        final p = c.pal;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(trf('pay_amt_upi', {'amt': rupees(amount)}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text('${tr('to')} $ownerUpi', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))),
                TextButton.icon(onPressed: () => copyText(c, ownerUpi), icon: const Icon(Icons.copy_rounded, size: 16), label: Text(tr('copy'))),
              ]),
              const SizedBox(height: 6),
              for (final a in upiApps)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Color(a.color), borderRadius: BorderRadius.circular(12)),
                    child: Text(a.letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
                  onTap: () => Navigator.pop(c, a),
                ),
            ]),
          ),
        );
      },
    );

/// Returns true when a payment was sent for checking.
Future<bool> payForPlan(BuildContext context, Membership m, Plan plan, bool yearly) async {
  final app = context.appRead;
  final amount = planAmount(plan, yearly);
  final upiApp = await _pickApp(context, amount);
  if (upiApp == null || !context.mounted) return false;
  final ref = 'VDP${DateTime.now().millisecondsSinceEpoch}';
  UpiResult res;
  if (app.isDemo) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    res = UpiResult(UpiStatus.success, utr: '${DateTime.now().millisecondsSinceEpoch}'.substring(1, 13));
  } else {
    res = await payByUpi(
      vpa: ownerUpi,
      payee: ownerPayee,
      amount: amount,
      note: 'VidyaDesk ${plan.name} ${yearly ? 'year' : 'month'}',
      ref: ref,
      package: upiApp.package,
    );
  }
  if (!context.mounted) return false;
  if (res.status == UpiStatus.failed) {
    toast(context, tr('upi_failed'));
    return false;
  }
  if (res.status == UpiStatus.noApp) toast(context, trf('upi_no_app', {'app': upiApp.name}));
  final utr = await askUtr(context, res.utr);
  if (utr == null || !context.mounted) return false;
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    await app.backend.claimSubscription(SubPayment(
      id: '${m.instituteId}_$now',
      instituteId: m.instituteId,
      instituteName: m.instituteName,
      adminUid: m.uid,
      adminName: m.name,
      phone: m.phone,
      plan: plan.name,
      yearly: yearly,
      amount: amount,
      utr: utr,
      createdAt: now,
    ));
  } catch (e) {
    if (context.mounted) toast(context, errorMessage(e));
    return false;
  }
  if (!context.mounted) return true;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.verified_rounded, color: c.pal.success, size: 40),
      title: Text(tr('sub_sent_title')),
      content: Text(trf('sub_sent_body', {'utr': utr}), textAlign: TextAlign.center),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('ok')))],
    ),
  );
  return true;
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
            const Center(child: Floaty(child: Mascot(size: 160, book: false))),
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
  const OwnerPanelScreen({super.key});
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
          title: Text(tr('payment_not_found_q')),
          content: Text(trf('payment_not_found_body', {'utr': s.utr})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('not_received'))),
          ],
        ),
      );
      if (sure != true) return;
    }
    if (!mounted) return;
    setState(() => _busy.add(s.id));
    try {
      await context.appRead.backend.decideSubPayment(s, ok);
      if (mounted) toast(context, ok ? trf('plan_started', {'inst': s.instituteName}) : tr('marked_not_received'));
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
      appBar: InnerBar(title: tr('owner_panel'), subtitle: tr('owner_panel_sub')),
      body: Loader<OwnerStats>(
        key: ValueKey(_v),
        load: () => context.appRead.backend.ownerStats(),
        builder: (context, d, reload) {
          final now = DateTime.now();
          final st = [for (final i in d.institutes) (i, PlanStatus(planFrom(i.plan), i.planUntil, now: now))];
          final paid = st.where((x) => !x.$2.trial && !x.$2.locked).length;
          final trial = st.where((x) => x.$2.trial && !x.$2.locked).length;
          final soon = st.where((x) => x.$2.daysLeft <= 7 && !x.$2.locked).toList()..sort((a, b) => a.$2.until.compareTo(b.$2.until));
          final locked = st.where((x) => x.$2.locked).toList();
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
                    if (i.ownerPhone.isNotEmpty) IconBtn(icon: Icons.chat_rounded, color: p.success, box: 38, tooltip: 'WhatsApp', onTap: () => openWhatsApp(context, i.ownerPhone, trf('owner_remind_text', {'inst': i.name}))),
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
                const SizedBox(height: 18),
                SectionTitle(tr('confirm_payments'), trailing: d.pending.isEmpty ? null : Tag(trf('n_new', {'n': '${d.pending.length}'}), fg: p.danger, bg: p.dangerTint)),
                if (d.pending.isEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr('no_payments_waiting'), style: TextStyle(color: p.muted))),
                for (final s in d.pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s.instituteName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              Text('${planName(planFrom(s.plan))} · ${s.yearly ? tr('one_year') : tr('one_month')} · ${s.adminName}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                            ]),
                          ),
                          Text(rupees(s.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(child: SelectableText('UTR ${s.utr}', style: TextStyle(fontWeight: FontWeight.w700, color: p.ink2, letterSpacing: .4))),
                          IconBtn(icon: Icons.copy_rounded, box: 36, size: 18, tooltip: tr('copy'), onTap: () => copyText(context, s.utr)),
                          if (s.phone.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            IconBtn(icon: Icons.call_rounded, box: 36, size: 18, tooltip: tr('call'), onTap: () => callPhone(context, s.phone)),
                          ],
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: SoftButton(label: tr('not_received'), height: 42, color: p.dangerTint, textColor: p.danger, onPressed: _busy.contains(s.id) ? null : () => _decide(s, false))),
                          const SizedBox(width: 8),
                          Expanded(child: SoftButton(label: tr('confirm_start'), height: 42, color: p.successTint, textColor: p.success, onPressed: _busy.contains(s.id) ? null : () => _decide(s, true))),
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
