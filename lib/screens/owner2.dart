import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/plan.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/push.dart';
import '../services/reports.dart';
import '../ui/mascot.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'file_sheet.dart';
import 'owner.dart' show showManageCoaching;
import 'subscription.dart' show planName, planColor;
import 'viewers.dart' show pickPhotos, PhotoViewerScreen;

const _day = 86400000;

String _d(int ms) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String _ago(int ms) {
  if (ms <= 0) return tr('never');
  final d = DateTime.now().millisecondsSinceEpoch - ms;
  if (d < 3600000) return tr('just_now');
  if (d < _day) return trf('n_hours_ago', {'n': '${d ~/ 3600000}'});
  return trf('n_days_ago', {'n': '${d ~/ _day}'});
}

int _sleepDays(Institute i) => i.lastActive <= 0 ? 999 : (DateTime.now().millisecondsSinceEpoch - i.lastActive) ~/ _day;

// ---------------------------------------------------------------------------
// O1 Earnings
// ---------------------------------------------------------------------------

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  int _months = 6;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: tr('earnings'), subtitle: tr('owner_panel')),
      body: Loader<(List<SubPayment>, OwnerStats)>(
        load: () async {
          final b = context.appRead.backend;
          return (await b.allSubPayments(), await b.ownerStats());
        },
        builder: (context, d, reload) {
          final pays = d.$1.where((x) => x.started && !x.demo).toList();
          final now = DateTime.now();
          final months = [for (var i = _months - 1; i >= 0; i--) DateTime(now.year, now.month - i)];
          int sumFor(DateTime m) => pays.where((x) {
                final t = DateTime.fromMillisecondsSinceEpoch(x.createdAt);
                return t.year == m.year && t.month == m.month;
              }).fold(0, (a, x) => a + x.amount);
          final sums = [for (final m in months) sumFor(m)];
          final cur = sums.last;
          final prev = sums.length > 1 ? sums[sums.length - 2] : 0;
          final change = prev == 0 ? null : ((cur - prev) * 100 / prev).round();
          final maxV = sums.fold<int>(1, (a, b) => b > a ? b : a);
          final byPlan = {for (final x in paidPlans) x: pays.where((y) => y.plan == x.name).fold<int>(0, (a, y) => a + y.amount)};
          final total = byPlan.values.fold<int>(0, (a, b) => a + b);
          final insts = d.$2.institutes;
          final everPaid = {for (final x in pays) x.instituteId};
          final conv = insts.isEmpty ? 0 : (everPaid.length * 100 / insts.length).round();
          final newThis = insts.where((i) {
            final t = DateTime.fromMillisecondsSinceEpoch(i.createdAt);
            return i.createdAt > 0 && t.year == now.year && t.month == now.month;
          }).length;
          final left = insts.where((i) => PlanStatus(planFrom(i.plan), i.planUntil).locked).length;
          const mn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
            Row(children: [
              for (final o in [(1, 'one_month'), (6, 'six_months'), (12, 'one_year')]) ...[
                Expanded(child: ChoicePill(label: tr(o.$2), selected: _months == o.$1, onTap: () => setState(() => _months = o.$1))),
                if (o.$1 != 12) const SizedBox(width: 8),
              ],
            ]),
            const SizedBox(height: 12),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr('this_month_income'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
                Row(children: [
                  Expanded(child: Text(rupees(cur), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
                  if (change != null) Tag('${change >= 0 ? '+' : ''}$change%', fg: change >= 0 ? p.success : p.danger, bg: change >= 0 ? p.successTint : p.dangerTint),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  height: 150,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var i = 0; i < months.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                            if (sums[i] > 0) FittedBox(child: Text(sums[i] >= 1000 ? '${(sums[i] / 1000).toStringAsFixed(1)}k' : '${sums[i]}', style: TextStyle(fontSize: 10, color: p.muted, fontWeight: FontWeight.w700))),
                            const SizedBox(height: 3),
                            Container(
                              height: 4 + 110 * sums[i] / maxV,
                              decoration: BoxDecoration(
                                color: i == months.length - 1 ? p.brand : p.brandTint,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(3)),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(mn[months[i].month - 1], style: TextStyle(fontSize: 10.5, color: p.muted)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            SectionTitle(tr('which_plan_sells')),
            AppCard(
              child: Column(children: [
                for (final x in paidPlans)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text(planName(x), style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text('${total == 0 ? 0 : (byPlan[x]! * 100 / total).round()}% · ${rupees(byPlan[x]!)}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(value: total == 0 ? 0 : byPlan[x]! / total, minHeight: 8, color: planColor(p, x), backgroundColor: p.cardAlt),
                      ),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              for (final k in [(tr('trial_to_paid'), '$conv%', p.success), (tr('new_this_month'), '$newThis', p.brand), (tr('left_us'), '$left', p.danger)]) ...[
                Expanded(
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    radius: 18,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k.$2, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: k.$3)),
                      Text(k.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 11)),
                    ]),
                  ),
                ),
                if (k.$1 != tr('left_us')) const SizedBox(width: 8),
              ],
            ]),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// O2 Plan prices
// ---------------------------------------------------------------------------

class PricesScreen extends StatefulWidget {
  const PricesScreen({super.key});
  @override
  State<PricesScreen> createState() => _PricesScreenState();
}

class _PricesScreenState extends State<PricesScreen> {
  late final Map<Plan, List<TextEditingController>> _c = {
    for (final x in paidPlans)
      x: [
        TextEditingController(text: '${planPrice[x]!.$1}'),
        TextEditingController(text: '${planPrice[x]!.$2}'),
        TextEditingController(text: planLimit[x]!.$1 < 0 ? '' : '${planLimit[x]!.$1}'),
        TextEditingController(text: planLimit[x]!.$2 < 0 ? '' : '${planLimit[x]!.$2}'),
      ],
  };
  bool _busy = false;

  @override
  void dispose() {
    for (final l in _c.values) {
      for (final c in l) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.appRead;
    int n(TextEditingController c, {bool unlimited = false}) => c.text.trim().isEmpty && unlimited ? -1 : int.tryParse(c.text.trim()) ?? 0;
    final prices = <String, dynamic>{
      for (final x in paidPlans) x.name: [n(_c[x]![0]), n(_c[x]![1]), n(_c[x]![2], unlimited: true), n(_c[x]![3], unlimited: true)],
    };
    if (prices.values.any((v) => (v as List)[0] <= 0 || v[1] <= 0)) return toast(context, tr('err_amount'));
    setState(() => _busy = true);
    try {
      final c = await app.backend.config();
      c.prices = prices;
      await app.backend.saveConfig(c);
      app.config = c;
      applyPrices(prices);
      if (mounted) {
        toast(context, tr('prices_saved'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget field(String label, TextEditingController c, {String hint = ''}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(controller: c, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(isDense: true, hintText: hint)),
          ]),
        );
    return AppScaffold(
      title: tr('plan_prices'),
      subtitle: tr('plan_prices_sub'),
      bottom: PrimaryButton(label: tr('save_prices'), arrow: false, busy: _busy, onPressed: _save),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 20), children: [
        for (final x in paidPlans)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [CircleAvatar(radius: 5, backgroundColor: planColor(p, x)), const SizedBox(width: 8), Text(planName(x), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
                const SizedBox(height: 10),
                Row(children: [
                  field('${tr('per_month_label')} ₹', _c[x]![0]),
                  const SizedBox(width: 8),
                  field('${tr('one_year')} ₹', _c[x]![1]),
                  const SizedBox(width: 8),
                  field(tr('students'), _c[x]![2], hint: '∞'),
                  const SizedBox(width: 8),
                  field(tr('teachers'), _c[x]![3], hint: '∞'),
                ]),
              ]),
            ),
          ),
        AppCard(
          color: p.warnTint,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: p.warn),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('prices_note'), style: TextStyle(color: p.ink2, fontWeight: FontWeight.w600, fontSize: 12.5))),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// O3 Coaching detail · O5 Block · O6 View as admin
// ---------------------------------------------------------------------------

class CoachingDetailScreen extends StatefulWidget {
  const CoachingDetailScreen({super.key, required this.inst});
  final Institute inst;
  @override
  State<CoachingDetailScreen> createState() => _CoachingDetailScreenState();
}

class _CoachingDetailScreenState extends State<CoachingDetailScreen> {
  late Institute _i = widget.inst;
  int _v = 0;

  Future<void> _block() async {
    final app = context.appRead;
    if (_i.blocked) {
      await app.backend.setBlocked(_i.id, false, '');
      Push.send(inst: _i.id, kind: 'plan', title: '✅ ${tr('push_unblocked')}', body: _i.name, topics: [Push.admins(_i.id), Push.staff(_i.id), Push.learners(_i.id)]);
    } else {
      final why = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(trf('block_q', {'inst': _i.name})),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('block_sub')),
            const SizedBox(height: 10),
            TextField(controller: why, maxLines: 2, decoration: InputDecoration(hintText: tr('block_reason_hint'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: c.pal.danger), onPressed: () => Navigator.pop(c, true), child: Text(tr('block'))),
          ],
        ),
      );
      if (ok != true) return;
      await app.backend.setBlocked(_i.id, true, why.text.trim());
    }
    final fresh = await app.backend.institute(_i.id);
    if (!mounted) return;
    setState(() {
      if (fresh != null) _i = fresh;
      _v++;
    });
    toast(context, _i.blocked ? tr('blocked_done') : tr('unblocked_done'));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final st = PlanStatus(planFrom(_i.plan), _i.planUntil);
    return Scaffold(
      appBar: InnerBar(title: _i.name, subtitle: [_i.ownerName, _i.city].where((e) => e.isNotEmpty).join(' · ')),
      body: Loader<(List<Membership>, List<Batch>, List<FeeRecord>)>(
        key: ValueKey(_v),
        load: () async {
          final b = app.backend;
          final n = DateTime.now();
          return (await b.members(_i.id), await b.batches(_i.id), await b.feesForMonth(_i.id, monthKey(n)).catchError((_) => <FeeRecord>[]));
        },
        builder: (context, d, reload) {
          final studs = d.$1.where((x) => x.role == Role.student && x.approved).length;
          final teach = d.$1.where((x) => x.role == Role.teacher && x.approved).length;
          final fees = d.$3.where((f) => f.paid).fold<int>(0, (a, f) => a + f.amount);
          final now = DateTime.now();
          final days = [for (var k = 13; k >= 0; k--) now.subtract(Duration(days: k))];
          String key(DateTime x) => '${x.year}${x.month.toString().padLeft(2, '0')}${x.day.toString().padLeft(2, '0')}';
          final use = [for (final x in days) _i.usage[key(x)] ?? 0];
          final maxU = use.fold<int>(1, (a, b) => b > a ? b : a);
          final week = use.skip(7).fold<int>(0, (a, b) => a + b);
          Widget kpi(String l, String v, Color c) => Expanded(
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  radius: 18,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
                    Text(l, style: TextStyle(color: p.muted, fontSize: 11)),
                  ]),
                ),
              );
          Widget row(String k, String v) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [Expanded(child: Text(k, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))), Text(v, style: const TextStyle(fontWeight: FontWeight.w800))]),
              );
          return ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
            if (_i.blocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  color: p.dangerTint,
                  padding: const EdgeInsets.all(14),
                  child: Text('${tr('coaching_blocked')}${_i.blockReason.isEmpty ? '' : ' · ${_i.blockReason}'}', style: TextStyle(color: p.danger, fontWeight: FontWeight.w800)),
                ),
              ),
            Row(children: [
              kpi(tr('students'), '$studs', p.brand),
              const SizedBox(width: 8),
              kpi(tr('teachers'), '$teach', p.success),
              const SizedBox(width: 8),
              kpi(tr('batches'), '${d.$2.length}', p.indigo),
            ]),
            const SizedBox(height: 10),
            AppCard(
              child: Column(children: [
                row(tr('plan'), '${planName(st.plan)} · ${st.active ? trf('till_date', {'date': _d(st.until)}) : tr('plan_ended')}'),
                row(tr('app_last_open'), _ago(_i.lastActive)),
                row(tr('opens_this_week'), '$week'),
                row(tr('fees_this_month_app'), rupees(fees)),
                if (_i.createdAt > 0) row(tr('joined_on'), _d(_i.createdAt)),
              ]),
            ),
            const SizedBox(height: 12),
            Text(tr('use_14_days'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                height: 64,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final u in use)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(height: 3 + 58 * u / maxU, decoration: BoxDecoration(color: u == 0 ? p.border : p.brand, borderRadius: BorderRadius.circular(3))),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: SoftButton(
                  label: tr('view_as_admin'),
                  icon: Icons.visibility_outlined,
                  height: 46,
                  onPressed: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    app.startViewAs(_i);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SoftButton(
                  label: _i.blocked ? tr('unblock') : tr('block'),
                  icon: _i.blocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                  height: 46,
                  color: _i.blocked ? p.successTint : p.dangerTint,
                  textColor: _i.blocked ? p.success : p.danger,
                  onPressed: _block,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            SoftButton(label: tr('manage_plan'), icon: Icons.workspace_premium_outlined, height: 46, onPressed: () => showManageCoaching(context, _i, onChanged: () => setState(() => _v++))),
            if (_i.ownerPhone.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: SoftButton(label: tr('call'), icon: Icons.call_rounded, height: 46, onPressed: () => callPhone(context, _i.ownerPhone))),
                const SizedBox(width: 8),
                Expanded(
                  child: SoftButton(
                    label: 'WhatsApp',
                    icon: Icons.chat_rounded,
                    height: 46,
                    color: p.successTint,
                    textColor: p.success,
                    onPressed: () => openWhatsApp(context, _i.ownerPhone, trf('owner_hello_text', {'inst': _i.name})),
                  ),
                ),
              ]),
            ],
          ]);
        },
      ),
    );
  }
}

/// The owner looking at a coaching exactly like its admin (nothing can be saved).
class ViewAsBar extends StatelessWidget {
  const ViewAsBar({super.key, required this.name, required this.onClose});
  final String name;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFD27A),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
          child: Row(children: [
            const Icon(Icons.visibility_outlined, color: Color(0xFF6B4400), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(trf('viewing_as', {'inst': name}), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF6B4400), fontWeight: FontWeight.w800))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6B4400), visualDensity: VisualDensity.compact),
              onPressed: onClose,
              child: Text(tr('stop_viewing')),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// O4 Sleeping coachings
// ---------------------------------------------------------------------------

class SleepingScreen extends StatelessWidget {
  const SleepingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: tr('sleeping'), subtitle: tr('sleeping_sub')),
      body: Loader<OwnerStats>(
        load: () => context.appRead.backend.ownerStats(),
        builder: (context, d, reload) {
          final list = d.institutes.where((i) => _sleepDays(i) >= 7 && !PlanStatus(planFrom(i.plan), i.planUntil).locked).toList()..sort((a, b) => a.lastActive.compareTo(b.lastActive));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
            if (list.isEmpty) EmptyState(icon: Icons.celebration_outlined, text: tr('none_sleeping')),
            if (list.isNotEmpty)
              AppCard(
                color: p.warnTint,
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, color: p.warn),
                  const SizedBox(width: 10),
                  Expanded(child: Text(trf('n_may_leave', {'n': '${list.length}'}), style: TextStyle(fontWeight: FontWeight.w700, color: p.ink2))),
                ]),
              ),
            const SizedBox(height: 10),
            for (final i in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () => push(context, CoachingDetailScreen(inst: i)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(i.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Text(planName(planFrom(i.plan)), style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ]),
                      ),
                      Tag(i.lastActive <= 0 ? tr('never_opened') : trf('n_days_closed', {'n': '${_sleepDays(i)}'}), fg: p.danger, bg: p.dangerTint),
                    ]),
                    if (i.ownerPhone.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: SoftButton(label: tr('call'), icon: Icons.call_rounded, height: 40, onPressed: () => callPhone(context, i.ownerPhone))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SoftButton(
                            label: 'WhatsApp',
                            icon: Icons.chat_rounded,
                            height: 40,
                            color: p.successTint,
                            textColor: p.success,
                            onPressed: () => openWhatsApp(context, i.ownerPhone, trf('owner_hello_text', {'inst': i.name})),
                          ),
                        ),
                      ]),
                    ],
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// O7 Help box
// ---------------------------------------------------------------------------

/// Admin: write to VidyaDesk and see replies.
class HelpBoxScreen extends StatefulWidget {
  const HelpBoxScreen({super.key, required this.m});
  final Membership m;
  @override
  State<HelpBoxScreen> createState() => _HelpBoxScreenState();
}

class _HelpBoxScreenState extends State<HelpBoxScreen> {
  final _text = TextEditingController();
  String _topic = 'payment';
  String _photo = '';
  bool _busy = false;
  int _v = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.length < 5) return toast(context, tr('err_write_more'));
    final app = context.appRead;
    setState(() => _busy = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await app.backend.sendTicket(Ticket(
        id: '${widget.m.instituteId}_$now',
        instituteId: widget.m.instituteId,
        instituteName: widget.m.instituteName,
        adminUid: widget.m.uid,
        adminName: widget.m.name,
        phone: widget.m.phone,
        topic: _topic,
        text: t,
        image: _photo,
        createdAt: now,
      ));
      Push.send(inst: widget.m.instituteId, kind: 'ticket', title: '🆘 ${widget.m.instituteName}', body: t, topics: ['owner']);
      _text.clear();
      setState(() {
        _photo = '';
        _v++;
      });
      if (mounted) toast(context, tr('ticket_sent'));
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: tr('help_box'), subtitle: tr('help_box_sub')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('tell_problem'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in ['payment', 'fees', 'app', 'other']) ChoicePill(label: tr('tk_$t'), selected: _topic == t, onTap: () => setState(() => _topic = t)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _text, minLines: 3, maxLines: 6, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: tr('problem_hint'))),
            const SizedBox(height: 10),
            if (_photo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(alignment: Alignment.centerLeft, child: _Thumb(b64: _photo, onRemove: () => setState(() => _photo = ''))),
              ),
            Row(children: [
              Expanded(
                child: SoftButton(
                  label: tr('add_screenshot'),
                  icon: Icons.photo_camera_outlined,
                  height: 46,
                  onPressed: () async {
                    final got = await pickPhotos(context, max: 1);
                    if (got.isNotEmpty) setState(() => _photo = got.first);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: PrimaryButton(label: tr('send'), arrow: false, busy: _busy, onPressed: _send)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        SectionTitle(tr('my_tickets')),
        FutureBuilder<List<Ticket>>(
          key: ValueKey(_v),
          future: context.appRead.backend.myTickets(widget.m.instituteId),
          builder: (context, s) {
            if (!s.hasData) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            if (s.data!.isEmpty) return Text(tr('no_tickets'), style: TextStyle(color: p.muted));
            return Column(children: [for (final t in s.data!) _TicketCard(t: t)]);
          },
        ),
      ]),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.b64, this.onRemove});
  final String b64;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) {
    final b = Avatar.bytesOf(b64);
    return Stack(clipBehavior: Clip.none, children: [
      GestureDetector(
        onTap: () => push(context, PhotoViewerScreen(images: [b64])),
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: b == null ? const SizedBox(width: 70, height: 70) : Image.memory(b, width: 70, height: 70, fit: BoxFit.cover)),
      ),
      if (onRemove != null)
        Positioned(right: -8, top: -8, child: IconButton.filled(iconSize: 14, visualDensity: VisualDensity.compact, onPressed: onRemove, icon: const Icon(Icons.close_rounded))),
    ]);
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.t, this.owner = false, this.onReply});
  final Ticket t;
  final bool owner;
  final VoidCallback? onReply;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final answered = t.status == 'answered';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: onReply,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(owner ? t.instituteName : tr('tk_${t.topic}'), style: const TextStyle(fontWeight: FontWeight.w800))),
            Tag(answered ? tr('answered') : tr('open'), fg: answered ? p.success : p.warn, bg: answered ? p.successTint : p.warnTint),
          ]),
          if (owner) Text('${tr('tk_${t.topic}')} · ${t.adminName} · ${_ago(t.createdAt)}', style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(t.text, style: const TextStyle(height: 1.4)),
          if (t.image.isNotEmpty) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: _Thumb(b64: t.image))],
          if (answered) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.successTint, borderRadius: BorderRadius.circular(12)),
              child: Text('✓ ${t.reply}', style: TextStyle(color: p.success, fontWeight: FontWeight.w700, height: 1.4)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Owner: every help request; tap to reply.
class OwnerInboxScreen extends StatefulWidget {
  const OwnerInboxScreen({super.key});
  @override
  State<OwnerInboxScreen> createState() => _OwnerInboxScreenState();
}

class _OwnerInboxScreenState extends State<OwnerInboxScreen> {
  int _v = 0;

  Future<void> _reply(Ticket t) async {
    final c = TextEditingController(text: t.reply);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (s) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(s).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.instituteName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 6),
          Text(t.text, style: TextStyle(color: s.pal.ink2)),
          const SizedBox(height: 12),
          TextField(controller: c, autofocus: true, minLines: 2, maxLines: 5, decoration: InputDecoration(hintText: tr('write_reply'))),
          const SizedBox(height: 12),
          Row(children: [
            if (t.phone.isNotEmpty) ...[
              IconBtn(icon: Icons.call_rounded, tooltip: tr('call'), onTap: () => callPhone(s, t.phone)),
              const SizedBox(width: 8),
            ],
            Expanded(child: PrimaryButton(label: tr('send_reply'), arrow: false, onPressed: () => Navigator.pop(s, true))),
          ]),
        ]),
      ),
    );
    if (ok != true || c.text.trim().isEmpty || !mounted) return;
    try {
      await context.appRead.backend.replyTicket(t, c.text.trim());
      Push.send(inst: t.instituteId, kind: 'ticket', title: '💬 ${tr('push_ticket_reply')}', body: c.text.trim(), topics: [Push.person(t.instituteId, t.adminUid)]);
      if (mounted) setState(() => _v++);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: InnerBar(title: tr('inbox'), subtitle: tr('inbox_sub')),
      body: Loader<List<Ticket>>(
        key: ValueKey(_v),
        load: () => context.appRead.backend.allTickets(),
        builder: (context, list, reload) {
          final open = list.where((t) => t.status != 'answered').toList();
          final done = list.where((t) => t.status == 'answered').toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
            if (list.isEmpty) EmptyState(icon: Icons.inbox_outlined, text: tr('no_tickets')),
            for (final t in [...open, ...done]) _TicketCard(t: t, owner: true, onReply: () => _reply(t)),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// O8 What's new
// ---------------------------------------------------------------------------

class NewsEditorScreen extends StatefulWidget {
  const NewsEditorScreen({super.key});
  @override
  State<NewsEditorScreen> createState() => _NewsEditorScreenState();
}

class _NewsEditorScreenState extends State<NewsEditorScreen> {
  late final AppConfig _c = context.appRead.config;
  late final _title = TextEditingController(text: _c.newsTitle);
  late final List<(TextEditingController, TextEditingController)> _items = [
    for (var i = 0; i < 4; i++) (TextEditingController(text: i < _c.newsItems.length ? _c.newsItems[i].$1 : ''), TextEditingController(text: i < _c.newsItems.length ? _c.newsItems[i].$2 : '')),
  ];
  bool _busy = false;

  Future<void> _publish() async {
    final items = [for (final x in _items) if (x.$1.text.trim().isNotEmpty) (x.$1.text.trim(), x.$2.text.trim())];
    if (items.isEmpty) return toast(context, tr('err_news_empty'));
    final app = context.appRead;
    setState(() => _busy = true);
    try {
      final c = await app.backend.config();
      c
        ..newsTitle = _title.text.trim()
        ..newsItems = items
        ..newsId = DateTime.now().millisecondsSinceEpoch;
      await app.backend.saveConfig(c);
      app.config = c;
      if (mounted) {
        toast(context, tr('news_published'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: tr('whats_new_editor'),
      subtitle: tr('whats_new_editor_sub'),
      bottom: PrimaryButton(label: tr('publish_news'), arrow: false, busy: _busy, onPressed: _publish),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 20), children: [
        FieldLabel(tr('heading')),
        TextField(controller: _title, decoration: InputDecoration(hintText: tr('news_title_hint'))),
        const SizedBox(height: 14),
        for (var i = 0; i < _items.length; i++) ...[
          FieldLabel('${tr('news_point')} ${i + 1}'),
          TextField(controller: _items[i].$1, decoration: InputDecoration(hintText: tr('news_point_hint'))),
          const SizedBox(height: 6),
          TextField(controller: _items[i].$2, decoration: InputDecoration(hintText: tr('news_point_sub_hint'))),
          const SizedBox(height: 12),
        ],
      ]),
    );
  }
}

/// Shown once to everyone after the owner publishes "What's new".
Future<void> maybeShowWhatsNew(BuildContext context) async {
  final app = context.appRead;
  final c = app.config;
  if (c.newsId <= 0 || c.newsItems.isEmpty || app.newsSeen >= c.newsId) return;
  app.markNewsSeen(c.newsId);
  await showDialog<void>(
    context: context,
    builder: (d) {
      final p = d.pal;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Center(child: Mascot(size: 110, book: false, wave: true)),
            Text(c.newsTitle.isEmpty ? tr('whats_new_title') : c.newsTitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final x in c.newsItems)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  IconBox(Icons.auto_awesome_rounded, fg: p.brand, bg: p.brandTint, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(x.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (x.$2.isNotEmpty) Text(x.$2, style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 18),
            PrimaryButton(label: tr('great'), arrow: false, onPressed: () => Navigator.pop(d)),
          ]),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// O9 Feature switches
// ---------------------------------------------------------------------------

class FlagsScreen extends StatefulWidget {
  const FlagsScreen({super.key});
  @override
  State<FlagsScreen> createState() => _FlagsScreenState();
}

class _FlagsScreenState extends State<FlagsScreen> {
  AppConfig? _c;
  List<Institute> _insts = [];

  @override
  void initState() {
    super.initState();
    final b = context.appRead.backend;
    Future.wait([b.config(), b.ownerStats()]).then((r) {
      if (!mounted) return;
      setState(() {
        _c = r[0] as AppConfig;
        _insts = (r[1] as OwnerStats).institutes;
      });
    });
  }

  Future<void> _set(String f, String mode, List<String> insts) async {
    final c = _c!;
    setState(() => c.flags = {...c.flags, f: (mode, insts)});
    try {
      await context.appRead.backend.saveConfig(c);
      context.appRead.config = c;
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    }
  }

  Future<void> _pickInsts(String f, List<String> cur) async {
    final sel = {...cur};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (s) => StatefulBuilder(
        builder: (s, set) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(s).size.height * .75),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('pick_coachings'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final i in _insts)
                    CheckboxListTile(
                      value: sel.contains(i.id),
                      onChanged: (v) => set(() => v == true ? sel.add(i.id) : sel.remove(i.id)),
                      title: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(i.city),
                    ),
                ]),
              ),
              Padding(padding: const EdgeInsets.all(16), child: PrimaryButton(label: tr('save'), arrow: false, onPressed: () => Navigator.pop(s, true))),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) _set(f, 'some', sel.toList());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = _c;
    return Scaffold(
      appBar: InnerBar(title: tr('feature_switches'), subtitle: tr('feature_switches_sub')),
      body: c == null
          ? const LoadingView()
          : ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
              for (final f in flagFeatures)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('ff_$f'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ChoicePill(label: tr('ff_all'), selected: (c.flags[f]?.$1 ?? 'all') == 'all', onTap: () => _set(f, 'all', const [])),
                        ChoicePill(label: tr('ff_some'), selected: c.flags[f]?.$1 == 'some', onTap: () => _pickInsts(f, c.flags[f]?.$2 ?? const [])),
                        ChoicePill(label: tr('ff_off'), selected: c.flags[f]?.$1 == 'off', onTap: () => _set(f, 'off', const [])),
                      ]),
                      if (c.flags[f]?.$1 == 'some') ...[
                        const SizedBox(height: 8),
                        Text(_insts.where((i) => c.flags[f]!.$2.contains(i.id)).map((i) => i.name).join(', '), style: TextStyle(color: p.muted, fontSize: 12.5)),
                      ],
                    ]),
                  ),
                ),
            ]),
    );
  }
}

// ---------------------------------------------------------------------------
// O10 Maintenance
// ---------------------------------------------------------------------------

class MaintenanceEditorScreen extends StatefulWidget {
  const MaintenanceEditorScreen({super.key});
  @override
  State<MaintenanceEditorScreen> createState() => _MaintenanceEditorScreenState();
}

class _MaintenanceEditorScreenState extends State<MaintenanceEditorScreen> {
  late final AppConfig _c = context.appRead.config;
  late bool _on = _c.maintenanceNow;
  late final _msg = TextEditingController(text: _c.maintMsg.isEmpty ? tr('maint_default_msg') : _c.maintMsg);
  int _mins = 30;
  bool _busy = false;

  Future<void> _save() async {
    final app = context.appRead;
    setState(() => _busy = true);
    try {
      final c = await app.backend.config();
      c
        ..maintOn = _on
        ..maintMsg = _msg.text.trim()
        ..maintUntil = !_on || _mins == 0 ? 0 : DateTime.now().millisecondsSinceEpoch + _mins * 60000;
      await app.backend.saveConfig(c);
      app.config = c;
      if (mounted) {
        toast(context, _on ? tr('maint_on_done') : tr('maint_off_done'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('maintenance'),
      bottom: PrimaryButton(label: tr('save'), arrow: false, busy: _busy, onPressed: _save),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 20), children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _on,
            onChanged: (v) => setState(() => _on = v),
            title: Text(tr('maintenance_mode'), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(tr('maint_sub')),
          ),
        ),
        const SizedBox(height: 14),
        FieldLabel(tr('message')),
        TextField(controller: _msg, minLines: 2, maxLines: 4),
        const SizedBox(height: 14),
        FieldLabel(tr('till_when')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in [(30, 'm30'), (60, 'm60'), (0, 'until_i_stop')]) ChoicePill(label: tr(o.$2), selected: _mins == o.$1, onTap: () => setState(() => _mins = o.$1)),
        ]),
        const SizedBox(height: 14),
        AppCard(
          color: p.warnTint,
          padding: const EdgeInsets.all(14),
          child: Text(tr('maint_owner_note'), style: TextStyle(color: p.ink2, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      ]),
    );
  }
}

/// What everyone else sees during maintenance.
class MaintenanceView extends StatelessWidget {
  const MaintenanceView({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 80, 24, 30), children: [
          const Center(child: Mascot(size: 160, book: false, mood: OwlMood.sleep)),
          const SizedBox(height: 8),
          Text(tr('maint_title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(app.config.maintMsg.isEmpty ? tr('maint_default_msg') : app.config.maintMsg, textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 14.5, height: 1.5)),
          const SizedBox(height: 24),
          SoftButton(label: tr('check_again'), icon: Icons.refresh_rounded, onPressed: app.loadConfig),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// O11 Data download
// ---------------------------------------------------------------------------

class ExportScreen extends StatelessWidget {
  const ExportScreen({super.key});

  Future<List<TableReport>> _make(BuildContext context) async {
    final b = context.appRead.backend;
    final st = await b.ownerStats();
    final pays = await b.allSubPayments();
    final coupons = await b.coupons();
    final insts = st.institutes;
    final people = <String, (int, int, int)>{};
    for (final i in insts) {
      try {
        final m = await b.members(i.id);
        people[i.id] = (
          m.where((x) => x.role == Role.student && x.approved).length,
          m.where((x) => x.role == Role.teacher && x.approved).length,
          m.where((x) => x.role == Role.parent && x.approved).length,
        );
      } catch (_) {}
    }
    final today = _d(DateTime.now().millisecondsSinceEpoch);
    return [
      TableReport(
        title: 'VidyaDesk coachings',
        institute: 'VidyaDesk',
        subtitle: today,
        headers: ['Coaching', 'City', 'Admin', 'Phone', 'Plan', 'Till', 'Last opened', 'Blocked'],
        rows: [
          for (final i in insts) [i.name, i.city, i.ownerName, i.ownerPhone, i.plan, i.planUntil > 0 ? _d(i.planUntil) : '', i.lastActive > 0 ? _d(i.lastActive) : '', i.blocked ? 'Yes' : ''],
        ],
      ),
      TableReport(
        title: 'VidyaDesk plan payments',
        institute: 'VidyaDesk',
        subtitle: today,
        headers: ['Date', 'Coaching', 'Plan', 'Period', 'Amount', 'Via', 'UPI ref', 'Status'],
        numeric: const {4},
        rows: [
          for (final x in pays) [_d(x.createdAt), x.instituteName, x.plan, x.yearly ? '1 year' : '1 month', x.demo ? '0' : '${x.amount}', x.via, x.utr, x.demo ? 'demo' : x.status],
        ],
      ),
      TableReport(
        title: 'VidyaDesk people per coaching',
        institute: 'VidyaDesk',
        subtitle: today,
        headers: ['Coaching', 'Students', 'Teachers', 'Parents'],
        numeric: const {1, 2, 3},
        rows: [
          for (final i in insts) [i.name, '${people[i.id]?.$1 ?? ''}', '${people[i.id]?.$2 ?? ''}', '${people[i.id]?.$3 ?? ''}'],
        ],
      ),
      TableReport(
        title: 'VidyaDesk coupons',
        institute: 'VidyaDesk',
        subtitle: today,
        headers: ['Code', 'Discount', 'Plans', 'Till', 'Used', 'Max', 'On'],
        rows: [
          for (final c in coupons) [c.code, c.pct ? '${c.value}%' : '₹${c.value}', c.plans.join(' '), c.until > 0 ? _d(c.until) : '', '${c.used}', c.maxUses > 0 ? '${c.maxUses}' : '', c.active ? 'Yes' : 'No'],
        ],
      ),
    ];
  }

  Future<void> _get(BuildContext context, int? which) async {
    toast(context, tr('making_report'));
    try {
      final all = await _make(context);
      if (!context.mounted) return;
      final r = which != null
          ? all[which]
          : TableReport(
              title: 'VidyaDesk all data',
              institute: 'VidyaDesk',
              subtitle: all.first.subtitle,
              headers: all.first.headers,
              rows: all.first.rows,
              extra: [for (final t in all.skip(1)) (t.title, t.headers, t.rows)],
            );
      await showFileSheet(context, title: r.title, files: [excelOption(r), pdfOption(r)]);
    } catch (e) {
      if (context.mounted) toast(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final items = [
      (Icons.apartment_rounded, 'exp_coachings', 'exp_coachings_sub'),
      (Icons.receipt_long_rounded, 'exp_payments', 'exp_payments_sub'),
      (Icons.groups_rounded, 'exp_people', 'exp_people_sub'),
      (Icons.local_offer_outlined, 'exp_coupons', 'exp_coupons_sub'),
    ];
    return Scaffold(
      appBar: InnerBar(title: tr('data_download'), subtitle: tr('data_download_sub')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              onTap: () => _get(context, i),
              child: Row(children: [
                IconBox(items[i].$1, fg: p.success, bg: p.successTint),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(items[i].$2), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(tr(items[i].$3), style: TextStyle(color: p.muted, fontSize: 12.5)),
                  ]),
                ),
                Icon(Icons.download_rounded, color: p.success),
              ]),
            ),
          ),
        const SizedBox(height: 6),
        PrimaryButton(label: tr('exp_all'), icon: Icons.download_rounded, arrow: false, onPressed: () => _get(context, null)),
        const SizedBox(height: 8),
        Text(tr('exp_note'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12.5)),
      ]),
    );
  }
}

/// Everyone in a blocked coaching sees this.
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key, required this.inst});
  final Institute inst;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    return Scaffold(
      body: SafeArea(
        child: OwlRefresh(
          onRefresh: app.loadInstitute,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 70, 24, 30), children: [
            const Center(child: Mascot(size: 150, book: false, mood: OwlMood.sad)),
            const SizedBox(height: 8),
            Text(tr('coaching_closed'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(trf('coaching_closed_sub', {'inst': inst.name}) + (inst.blockReason.isEmpty ? '' : '\n${tr('reason')}: ${inst.blockReason}'),
                textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 14, height: 1.5)),
            const SizedBox(height: 22),
            if (app.active?.role == Role.admin)
              SoftButton(label: tr('talk_to_vidyadesk'), icon: Icons.support_agent_rounded, onPressed: () => push(context, HelpBoxScreen(m: app.active!))),
            const SizedBox(height: 8),
            SoftButton(label: tr('check_again'), icon: Icons.refresh_rounded, onPressed: app.loadInstitute),
            const SizedBox(height: 6),
            TextButton(onPressed: app.signOut, child: Text(tr('logout'), style: TextStyle(color: p.muted))),
          ]),
        ),
      ),
    );
  }
}

/// Small helper used by the JSON export (kept for future CSV needs).
String jsonPretty(Object o) => const JsonEncoder.withIndent('  ').convert(o);
