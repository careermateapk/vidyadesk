import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/plan.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/push.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'subscription.dart' show planName, planColor, featureOn;
import 'money.dart' show confirmDelete;
import 'viewers.dart' show openExternal;

String _d(int ms) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

const _day = 86400000;

// ---------------------------------------------------------------------------
// Manage one coaching: renew, give plan, extend trial, stop — as many times as needed
// ---------------------------------------------------------------------------

Future<void> showManageCoaching(BuildContext context, Institute inst, {required VoidCallback onChanged}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ManageSheet(inst: inst, onChanged: onChanged),
  );
}

class _ManageSheet extends StatefulWidget {
  const _ManageSheet({required this.inst, required this.onChanged});
  final Institute inst;
  final VoidCallback onChanged;
  @override
  State<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends State<_ManageSheet> {
  late Institute _inst = widget.inst;
  int _v = 0;

  Future<void> _open(String action) async {
    final st = PlanStatus(planFrom(_inst.plan), _inst.planUntil);
    if (action == 'stop') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('stop_plan_q')),
          content: Text(trf('owner_stop_body', {'inst': _inst.name})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: c.pal.danger), onPressed: () => Navigator.pop(c, true), child: Text(tr('stop_now'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final until = DateTime.now().millisecondsSinceEpoch - (graceDays * _day + 60000);
      await _apply('stop', st.plan.name, until, 0, '');
      return;
    }
    final r = await push<(String, int, int, String)>(
      context,
      GivePlanScreen(inst: _inst, action: action),
    );
    if (r == null || !mounted) return;
    await _apply(action, r.$1, r.$2, r.$3, r.$4);
  }

  Future<void> _apply(String action, String plan, int until, int days, String note) async {
    final app = context.appRead;
    try {
      await app.backend.ownerSetPlan(_inst.id, action: action, plan: plan, until: until, days: days, note: note);
      Push.send(
        inst: _inst.id,
        kind: 'plan',
        title: action == 'stop' ? '⚠️ ${tr('push_owner_stopped')}' : '✅ ${trf('push_owner_gave', {'plan': planName(planFrom(plan))})}',
        body: action == 'stop' ? _inst.name : trf('till_date', {'date': _d(until)}),
        topics: [Push.admins(_inst.id)],
      );
      final fresh = await app.backend.institute(_inst.id);
      if (!mounted) return;
      setState(() {
        if (fresh != null) _inst = fresh;
        _v++;
      });
      widget.onChanged();
      if (app.active?.instituteId == _inst.id) app.loadInstitute();
      toast(context, tr('saved'));
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = PlanStatus(planFrom(_inst.plan), _inst.planUntil);
    Widget act(String a, IconData i, String label, Color fg, Color bg) => Expanded(
          child: GestureDetector(
            onTap: () => _open(a),
            child: Container(
              height: 58,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(i, color: fg, size: 20),
                const SizedBox(width: 6),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800))),
              ]),
            ),
          ),
        );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_inst.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text([if (_inst.ownerName.isNotEmpty) _inst.ownerName, if (_inst.ownerPhone.isNotEmpty) _inst.ownerPhone, _inst.city].where((e) => e.isNotEmpty).join(' · '),
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
              ]),
            ),
            Tag(st.locked ? tr('locked') : (st.grace ? tr('plan_ended') : tr('active')), fg: st.active ? p.success : p.danger, bg: st.active ? p.successTint : p.dangerTint),
          ]),
          const SizedBox(height: 12),
          AppCard(
            color: p.cardAlt,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Text(tr('now'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${planName(st.plan)} · ${st.active ? trf('till_date', {'date': _d(st.until)}) : trf('ended_on', {'date': _d(st.until)})}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            act('renew', Icons.autorenew_rounded, tr('renew'), p.success, p.successTint),
            const SizedBox(width: 8),
            act('give', Icons.star_outline_rounded, tr('give_plan'), p.brand, p.brandTint),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            act('trial', Icons.schedule_rounded, tr('extend_trial'), p.warn, p.warnTint),
            const SizedBox(width: 8),
            act('stop', Icons.block_rounded, tr('stop_plan_short'), p.danger, p.dangerTint),
          ]),
          if (_inst.ownerPhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: SoftButton(label: tr('call'), icon: Icons.call_rounded, height: 44, onPressed: () => callPhone(context, _inst.ownerPhone))),
              const SizedBox(width: 8),
              Expanded(
                child: SoftButton(
                  label: 'WhatsApp',
                  icon: Icons.chat_rounded,
                  height: 44,
                  color: p.successTint,
                  textColor: p.success,
                  onPressed: () => openWhatsApp(context, _inst.ownerPhone, trf('owner_remind_text', {'inst': _inst.name})),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          Text(tr('plan_history'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          FutureBuilder<List<PlanAction>>(
            key: ValueKey(_v),
            future: context.appRead.backend.planHistory(_inst.id),
            builder: (context, snap) {
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
              final list = snap.data!;
              if (list.isEmpty) return Text(tr('nothing_yet'), style: TextStyle(color: p.muted));
              return Column(children: [
                for (final a in list.take(30))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.only(top: 5), child: CircleAvatar(radius: 4, backgroundColor: a.action == 'stop' || a.action.contains('reversed') ? p.danger : p.brand)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            '${tr('pa_${a.action.startsWith('paid_') ? 'paid' : a.action}')}${a.plan.isEmpty || a.action == 'stop' ? '' : ' · ${planName(planFrom(a.plan))}'}${a.until > 0 && a.action != 'stop' ? ' · ${trf('till_date', {'date': _d(a.until)})}' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                          if (a.note.isNotEmpty) Text(a.note, style: TextStyle(color: p.muted, fontSize: 12)),
                        ]),
                      ),
                      Text(_d(a.at), style: TextStyle(color: p.muted, fontSize: 12)),
                    ]),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

/// Owner: pick plan + how long. Returns (plan, until, days, note).
class GivePlanScreen extends StatefulWidget {
  const GivePlanScreen({super.key, required this.inst, required this.action});
  final Institute inst;
  final String action; // give | renew | trial
  @override
  State<GivePlanScreen> createState() => _GivePlanScreenState();
}

class _GivePlanScreenState extends State<GivePlanScreen> {
  late final PlanStatus _st = PlanStatus(planFrom(widget.inst.plan), widget.inst.planUntil);
  late Plan _plan = widget.action == 'trial' ? Plan.trial : (widget.action == 'renew' ? (_st.trial ? Plan.standard : _st.plan) : Plan.standard);
  int _days = 30;
  late bool _afterCurrent = widget.action != 'give' && _st.active;
  final _custom = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _until {
    final now = DateTime.now().millisecondsSinceEpoch;
    final from = _afterCurrent && _st.until > now ? _st.until : now;
    return from + _days * _day;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final title = switch (widget.action) { 'trial' => tr('extend_trial'), 'renew' => tr('renew'), _ => tr('give_plan') };
    const options = [(7, 'd7'), (15, 'd15'), (30, 'd30'), (90, 'd90'), (365, 'd365')];
    final custom = !options.any((o) => o.$1 == _days);
    return AppScaffold(
      title: title,
      subtitle: widget.inst.name,
      bottom: PrimaryButton(
        label: tr('start_plan_now'),
        arrow: false,
        onPressed: _days <= 0 ? null : () => Navigator.pop(context, (_plan.name, _until, _days, _note.text.trim())),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 6, 18, 20), children: [
        FieldLabel(tr('plan')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in Plan.values) ChoicePill(label: planName(x), selected: _plan == x, onTap: () => setState(() => _plan = x)),
        ]),
        const SizedBox(height: 16),
        FieldLabel(tr('how_many_days')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in options) ChoicePill(label: tr(o.$2), selected: _days == o.$1, onTap: () => setState(() => _days = o.$1)),
          ChoicePill(label: tr('custom_days'), selected: custom, onTap: () => setState(() => _days = int.tryParse(_custom.text) ?? 45)),
        ]),
        if (custom) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _custom,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) => setState(() => _days = int.tryParse(v) ?? 0),
            decoration: InputDecoration(hintText: '45', suffixText: tr('days')),
          ),
        ],
        const SizedBox(height: 16),
        FieldLabel(tr('from_when')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoicePill(label: tr('from_today'), selected: !_afterCurrent, onTap: () => setState(() => _afterCurrent = false)),
          if (_st.active) ChoicePill(label: tr('after_current'), selected: _afterCurrent, onTap: () => setState(() => _afterCurrent = true)),
        ]),
        const SizedBox(height: 16),
        FieldLabel(tr('note_only_you')),
        TextField(controller: _note, decoration: InputDecoration(hintText: tr('note_only_you_hint'))),
        const SizedBox(height: 16),
        AppCard(
          color: p.successTint,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Text(tr('new_plan'), style: TextStyle(color: p.success, fontWeight: FontWeight.w700)),
            const Spacer(),
            Flexible(child: Text('${planName(_plan)} · ${trf('till_date', {'date': _d(_until)})}', textAlign: TextAlign.right, style: TextStyle(color: p.success, fontWeight: FontWeight.w800))),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.notifications_active_outlined, size: 18, color: p.brand),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('admin_gets_notified'), style: TextStyle(color: p.ink2, fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Coupons
// ---------------------------------------------------------------------------

class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});
  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  int _v = 0;

  Future<void> _edit([Coupon? c]) async {
    final saved = await push<bool>(context, CouponEditScreen(coupon: c));
    if (saved == true && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: tr('coupons'), subtitle: tr('coupons_sub'), trailing: IconBtn(icon: Icons.add_rounded, filled: true, tooltip: tr('new_coupon'), onTap: () => _edit())),
      body: Loader<List<Coupon>>(
        key: ValueKey(_v),
        load: () => context.appRead.backend.coupons(),
        builder: (context, list, reload) => ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
          if (list.isEmpty) EmptyState(icon: Icons.local_offer_outlined, text: tr('no_coupons')),
          for (final c in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: EdgeInsets.zero,
                onTap: () => _edit(c),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(width: 8, decoration: BoxDecoration(color: c.problem(c.plans.isEmpty ? 'basic' : c.plans.first, true).isEmpty ? p.warn : p.muted, borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)))),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.code, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1)),
                          Text('${c.pct ? '${c.value}%' : rupees(c.value)} ${tr('off')} · ${c.plans.length == 3 ? tr('all_plans') : c.plans.map((x) => planName(planFrom(x))).join(', ')}${c.yearlyOnly ? ' · ${tr('yearly_only')}' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          Text('${c.until > 0 ? trf('till_date', {'date': _d(c.until)}) : tr('no_end')} · ${c.maxUses > 0 ? '${c.used}/${c.maxUses}' : '${c.used}'} ${tr('uses')}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ]),
                      ),
                    ),
                    Switch(
                      value: c.active,
                      onChanged: (v) async {
                        setState(() => c.active = v);
                        try {
                          await context.appRead.backend.saveCoupon(c);
                        } catch (e) {
                          if (context.mounted) toast(context, errorMessage(e));
                        }
                      },
                    ),
                    IconButton(
                      tooltip: tr('delete'),
                      icon: Icon(Icons.delete_outline_rounded, color: p.danger),
                      onPressed: () async {
                        if (!await confirmDelete(context, trf('delete_coupon_q', {'code': c.code}))) return;
                        try {
                          await context.appRead.backend.deleteCoupon(c.code);
                          if (context.mounted) toast(context, tr('deleted'));
                          setState(() => _v++);
                        } catch (e) {
                          if (context.mounted) toast(context, errorMessage(e));
                        }
                      },
                    ),
                    const SizedBox(width: 2),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class CouponEditScreen extends StatefulWidget {
  const CouponEditScreen({super.key, this.coupon});
  final Coupon? coupon;
  @override
  State<CouponEditScreen> createState() => _CouponEditScreenState();
}

class _CouponEditScreenState extends State<CouponEditScreen> {
  late final _code = TextEditingController(text: widget.coupon?.code ?? '');
  late final _value = TextEditingController(text: widget.coupon == null ? '' : '${widget.coupon!.value}');
  late final _max = TextEditingController(text: (widget.coupon?.maxUses ?? 0) == 0 ? '' : '${widget.coupon!.maxUses}');
  late bool _pct = widget.coupon?.pct ?? true;
  late final Set<String> _plans = {...(widget.coupon?.plans ?? ['basic', 'standard', 'pro'])};
  late bool _yearly = widget.coupon?.yearlyOnly ?? false;
  late int _until = widget.coupon?.until ?? 0;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = _code.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final v = int.tryParse(_value.text.trim()) ?? 0;
    if (code.length < 3) return setState(() => _err = tr('err_coupon_code'));
    if (v <= 0 || (_pct && v > 100)) return setState(() => _err = tr('err_coupon_value'));
    if (_plans.isEmpty) return setState(() => _err = tr('err_coupon_plans'));
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final c = Coupon(
        code: code,
        pct: _pct,
        value: v,
        plans: _plans.toList(),
        yearlyOnly: _yearly,
        until: _until,
        maxUses: int.tryParse(_max.text.trim()) ?? 0,
        used: widget.coupon?.used ?? 0,
        active: widget.coupon?.active ?? true,
        createdAt: widget.coupon?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      );
      final b = context.appRead.backend;
      if (widget.coupon != null && widget.coupon!.code != code) await b.deleteCoupon(widget.coupon!.code);
      await b.saveCoupon(c);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _err = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: widget.coupon == null ? tr('new_coupon') : widget.coupon!.code,
      actions: [
        if (widget.coupon != null)
          IconBtn(
            icon: Icons.delete_outline_rounded,
            tooltip: tr('delete'),
            onTap: () async {
              if (!await confirmDelete(context, trf('delete_coupon_q', {'code': widget.coupon!.code}))) return;
              if (!context.mounted) return;
              await context.appRead.backend.deleteCoupon(widget.coupon!.code);
              if (context.mounted) Navigator.pop(context, true);
            },
          ),
      ],
      bottom: PrimaryButton(label: widget.coupon == null ? tr('make_coupon') : tr('save'), arrow: false, busy: _busy, onPressed: _save),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 6, 18, 20), children: [
        FieldLabel(tr('coupon_code')),
        TextField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: 'NEWYEAR25')),
        const SizedBox(height: 14),
        FieldLabel(tr('discount')),
        Row(children: [
          ChoicePill(label: '% ${tr('off')}', selected: _pct, onTap: () => setState(() => _pct = true)),
          const SizedBox(width: 8),
          ChoicePill(label: '₹ ${tr('off')}', selected: !_pct, onTap: () => setState(() => _pct = false)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _value,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(hintText: _pct ? '25' : '100', suffixText: _pct ? '%' : '₹'),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        FieldLabel(tr('which_plans')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in paidPlans)
            ChoicePill(label: planName(x), selected: _plans.contains(x.name), onTap: () => setState(() => _plans.contains(x.name) ? _plans.remove(x.name) : _plans.add(x.name))),
          ChoicePill(label: tr('yearly_only'), selected: _yearly, onTap: () => setState(() => _yearly = !_yearly)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel(tr('valid_till')),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(_until == 0 ? tr('no_end') : _d(_until)),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(context: context, firstDate: now, lastDate: DateTime(now.year + 3), initialDate: _until == 0 ? now.add(const Duration(days: 30)) : DateTime.fromMillisecondsSinceEpoch(_until));
                  if (d != null) setState(() => _until = DateTime(d.year, d.month, d.day, 23, 59).millisecondsSinceEpoch);
                },
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel(tr('max_uses')),
              TextField(controller: _max, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(hintText: tr('no_limit'))),
            ]),
          ),
        ]),
        if (_err != null) ...[const SizedBox(height: 12), Text(_err!, style: TextStyle(color: p.danger, fontWeight: FontWeight.w700))],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Home banners (owner)
// ---------------------------------------------------------------------------

const bannerColors = [
  (Color(0xFFF59E0B), Color(0xFFD9480F)),
  (Color(0xFF3B9EF5), Color(0xFF5545D6)),
  (Color(0xFF12B886), Color(0xFF0B7A5C)),
  (Color(0xFFF0466E), Color(0xFF9C36B5)),
  (Color(0xFF7A6AF0), Color(0xFF4B3FC4)),
  (Color(0xFF334155), Color(0xFF0F172A)),
];

/// One banner card (also used on home pages).
class BannerCard extends StatelessWidget {
  const BannerCard({super.key, required this.b, this.onTap, this.height = 150});
  final AppBanner b;
  final VoidCallback? onTap;
  final double height;
  @override
  Widget build(BuildContext context) {
    final c = bannerColors[b.color.clamp(0, bannerColors.length - 1)];
    final img = Avatar.bytesOf(b.image);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(colors: [c.$1, c.$2], begin: Alignment.topLeft, end: Alignment.bottomRight),
          image: img == null ? null : DecorationImage(image: MemoryImage(img), fit: BoxFit.cover),
        ),
        child: Stack(children: [
          if (img == null) Positioned(right: -24, bottom: -36, child: Container(width: 150, height: 150, decoration: const BoxDecoration(color: Color(0x26FFFFFF), shape: BoxShape.circle))),
          if (img != null) Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.black.withValues(alpha: .55), Colors.transparent], begin: Alignment.bottomLeft, end: Alignment.topRight)))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (b.title.isNotEmpty) Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
              if (b.sub.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(b.sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
              const Spacer(),
              if (b.action != 'none')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Text('${tr('see')} →', style: TextStyle(color: c.$2, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class BannersScreen extends StatefulWidget {
  const BannersScreen({super.key});
  @override
  State<BannersScreen> createState() => _BannersScreenState();
}

class _BannersScreenState extends State<BannersScreen> {
  int _v = 0;

  Future<void> _edit([AppBanner? b, int order = 0]) async {
    final saved = await push<bool>(context, BannerEditScreen(banner: b, order: order));
    if (saved == true && mounted) setState(() => _v++);
  }

  Future<void> _move(List<AppBanner> list, int i, int dir) async {
    final j = i + dir;
    if (j < 0 || j >= list.length) return;
    final a = list[i], b = list[j];
    final t = a.order == b.order ? i : a.order;
    a.order = b.order == a.order ? j : b.order;
    b.order = t;
    final be = context.appRead.backend;
    await be.saveBanner(a);
    await be.saveBanner(b);
    if (mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: tr('home_banners'), subtitle: tr('home_banners_sub'), trailing: IconBtn(icon: Icons.add_rounded, filled: true, tooltip: tr('new_banner'), onTap: () => _edit(null, DateTime.now().millisecondsSinceEpoch ~/ 1000))),
      body: Loader<List<AppBanner>>(
        key: ValueKey(_v),
        load: () => context.appRead.backend.allBanners(),
        builder: (context, list, reload) => ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
          if (list.isEmpty) EmptyState(icon: Icons.view_carousel_outlined, text: tr('no_banners')),
          for (var i = 0; i < list.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Opacity(opacity: list[i].active ? 1 : .45, child: BannerCard(b: list[i], height: 110, onTap: () => _edit(list[i]))),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('who_sees'), style: TextStyle(color: p.muted, fontSize: 12)),
                        Text(list[i].roles.length == 4 ? tr('everyone') : list[i].roles.map((r) => tr('role_$r')).join(' · '), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      ]),
                    ),
                    IconButton(onPressed: i == 0 ? null : () => _move(list, i, -1), icon: const Icon(Icons.arrow_upward_rounded)),
                    IconButton(onPressed: i == list.length - 1 ? null : () => _move(list, i, 1), icon: const Icon(Icons.arrow_downward_rounded)),
                    IconButton(
                      tooltip: tr('delete'),
                      icon: Icon(Icons.delete_outline_rounded, color: p.danger),
                      onPressed: () async {
                        if (!await confirmDelete(context, tr('delete_banner_q'))) return;
                        try {
                          await context.appRead.backend.deleteBanner(list[i].id);
                          if (context.mounted) toast(context, tr('deleted'));
                          setState(() => _v++);
                        } catch (e) {
                          if (context.mounted) toast(context, errorMessage(e));
                        }
                      },
                    ),
                    Switch(
                      value: list[i].active,
                      onChanged: (v) async {
                        setState(() => list[i].active = v);
                        try {
                          await context.appRead.backend.saveBanner(list[i]);
                          if (context.mounted) toast(context, v ? tr('banner_on') : tr('banner_off'));
                        } catch (e) {
                          if (context.mounted) toast(context, errorMessage(e));
                        }
                      },
                    ),
                  ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class BannerEditScreen extends StatefulWidget {
  const BannerEditScreen({super.key, this.banner, this.order = 0});
  final AppBanner? banner;
  final int order;
  @override
  State<BannerEditScreen> createState() => _BannerEditScreenState();
}

class _BannerEditScreenState extends State<BannerEditScreen> {
  late final AppBanner _b = widget.banner ?? AppBanner(id: 'bn${DateTime.now().millisecondsSinceEpoch}', order: widget.order, createdAt: DateTime.now().millisecondsSinceEpoch);
  late final _title = TextEditingController(text: _b.title);
  late final _sub = TextEditingController(text: _b.sub);
  late final _url = TextEditingController(text: _b.url);
  bool _notify = false;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _sub.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _photo() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 900, maxHeight: 500, imageQuality: 70);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      setState(() => _b.image = base64Encode(bytes));
    } catch (_) {
      if (mounted) toast(context, tr('err_photo'));
    }
  }

  Future<void> _save() async {
    _b
      ..title = _title.text.trim()
      ..sub = _sub.text.trim()
      ..url = _url.text.trim();
    if (_b.title.isEmpty && _b.image.isEmpty) return toast(context, tr('err_banner_empty'));
    if (_b.roles.isEmpty) return toast(context, tr('err_banner_roles'));
    if (_b.action == 'url' && _b.url.length < 5) return toast(context, tr('err_link'));
    setState(() => _busy = true);
    try {
      await context.appRead.backend.saveBanner(_b);
      if (_notify && _b.active) await Push.broadcast(_b.title.isEmpty ? 'VidyaDesk' : _b.title, _b.sub);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const roles = ['admin', 'teacher', 'student', 'parent'];
    return AppScaffold(
      title: widget.banner == null ? tr('new_banner') : tr('edit_banner'),
      actions: [
        if (widget.banner != null)
          IconBtn(
            icon: Icons.delete_outline_rounded,
            tooltip: tr('delete'),
            onTap: () async {
              if (!await confirmDelete(context, tr('delete_banner_q'))) return;
              if (!context.mounted) return;
              await context.appRead.backend.deleteBanner(_b.id);
              if (context.mounted) Navigator.pop(context, true);
            },
          ),
      ],
      bottom: PrimaryButton(label: tr('save_banner'), arrow: false, busy: _busy, onPressed: _save),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 6, 18, 20), children: [
        AnimatedBuilder(
          animation: Listenable.merge([_title, _sub]),
          builder: (_, _) => BannerCard(b: AppBanner(id: '', title: _title.text, sub: _sub.text, color: _b.color, image: _b.image, action: _b.action)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: SoftButton(label: _b.image.isEmpty ? tr('add_photo') : tr('change_photo'), icon: Icons.image_outlined, height: 44, onPressed: _photo)),
          if (_b.image.isNotEmpty) ...[
            const SizedBox(width: 8),
            SoftButton(label: tr('remove'), height: 44, color: p.dangerTint, textColor: p.danger, onPressed: () => setState(() => _b.image = '')),
          ],
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < bannerColors.length; i++)
            GestureDetector(
              onTap: () => setState(() => _b.color = i),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [bannerColors[i].$1, bannerColors[i].$2]),
                  border: Border.all(color: _b.color == i ? p.ink : Colors.transparent, width: 3),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        FieldLabel(tr('heading')),
        TextField(controller: _title, maxLength: 50, decoration: const InputDecoration(counterText: '')),
        const SizedBox(height: 10),
        FieldLabel(tr('small_text')),
        TextField(controller: _sub, maxLength: 90, decoration: const InputDecoration(counterText: '')),
        const SizedBox(height: 14),
        FieldLabel(tr('on_tap_open')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in ['plans', 'url', 'none']) ChoicePill(label: tr('bact_$a'), selected: _b.action == a, onTap: () => setState(() => _b.action = a)),
        ]),
        if (_b.action == 'url') ...[
          const SizedBox(height: 10),
          TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://… (website / YouTube)', prefixIcon: Icon(Icons.link_rounded))),
        ],
        const SizedBox(height: 14),
        FieldLabel(tr('who_sees')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in roles)
            ChoicePill(
              label: tr('role_$r'),
              selected: _b.roles.contains(r),
              onTap: () => setState(() => _b.roles = _b.roles.contains(r) ? (_b.roles.where((x) => x != r).toList()) : [..._b.roles, r]),
            ),
          ChoicePill(label: tr('everyone'), selected: _b.roles.length == 4, onTap: () => setState(() => _b.roles = [...roles])),
        ]),
        const SizedBox(height: 10),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _b.active, onChanged: (v) => setState(() => _b.active = v), title: Text(tr('banner_active'), style: const TextStyle(fontWeight: FontWeight.w700))),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _notify, onChanged: (v) => setState(() => _notify = v), title: Text(tr('also_notify_all'), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(tr('also_notify_all_sub'))),
      ]),
    );
  }
}

/// Owner: one notification to every VidyaDesk user.
Future<void> showBroadcast(BuildContext context) async {
  final t = TextEditingController(), b = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('notice_to_all')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: t, decoration: InputDecoration(hintText: tr('heading'))),
        const SizedBox(height: 8),
        TextField(controller: b, minLines: 2, maxLines: 4, decoration: InputDecoration(hintText: tr('message'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('send'))),
      ],
    ),
  );
  if (ok != true || t.text.trim().isEmpty) return;
  final sent = await Push.broadcast(t.text.trim(), b.text.trim());
  if (context.mounted) toast(context, sent ? tr('sent_to_all') : tr('err_unknown'));
}

/// Banners on top of the home page. Slides by itself every 4 seconds.
class HomeBanners extends StatefulWidget {
  const HomeBanners({super.key, required this.role, this.onPlans});
  final Role role;
  final VoidCallback? onPlans;
  @override
  State<HomeBanners> createState() => _HomeBannersState();
}

class _HomeBannersState extends State<HomeBanners> {
  static List<AppBanner>? _cache;
  List<AppBanner> _list = _cache ?? const [];
  final _pc = PageController(viewportFraction: .94);
  int _i = 0;
  bool _alive = true;

  @override
  void initState() {
    super.initState();
    context.appRead.backend.banners().then((l) {
      _cache = l;
      if (mounted) setState(() => _list = l);
    }).catchError((_) {});
    _tick();
  }

  Future<void> _tick() async {
    while (_alive) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!_alive || !mounted || !_pc.hasClients) continue;
      final shown = _shown;
      if (shown.length < 2) continue;
      _pc.animateToPage((_i + 1) % shown.length, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  List<AppBanner> get _shown => _list.where((b) => b.roles.isEmpty || b.roles.contains(widget.role.name)).toList();

  @override
  void dispose() {
    _alive = false;
    _pc.dispose();
    super.dispose();
  }

  void _open(AppBanner b) {
    switch (b.action) {
      case 'plans':
        widget.onPlans?.call();
      case 'url':
        if (b.url.isNotEmpty) openExternal(context, b.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!featureOn(context, 'banners')) return const SizedBox.shrink();
    final p = context.pal;
    final shown = _shown;
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _pc,
            padEnds: shown.length == 1,
            itemCount: shown.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(right: 8), child: BannerCard(b: shown[i], onTap: () => _open(shown[i]))),
          ),
        ),
        if (shown.length > 1) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < shown.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _i ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(color: i == _i ? p.brand : p.border, borderRadius: BorderRadius.circular(3)),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Small helper so other screens can refer to plan colors without importing subscription.dart.
Color ownerPlanColor(Palette p, Plan x) => planColor(p, x);
