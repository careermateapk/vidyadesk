import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'payments.dart';
import 'reports.dart';
import 'subscription.dart';
import '../core/plan.dart';

// ---------------------------------------------------------------------------
// Fee rules: due date, late fee
// ---------------------------------------------------------------------------

/// Last day to pay [month] ("2026-10") without a late fee.
DateTime feeDueDate(String month, Institute? inst) {
  final p = month.split('-');
  final y = int.tryParse(p.first) ?? DateTime.now().year;
  final m = p.length > 1 ? int.tryParse(p[1]) ?? 1 : 1;
  return DateTime(y, m, inst?.dueDay ?? 10);
}

/// Adds the institute's late fee to an unpaid fee once the due date has passed.
/// lateFee -1 means the admin waived it.
FeeRecord withLateFee(FeeRecord r, Institute? inst) {
  if (r.paid || r.lateFee != 0 || r.amount <= 0 || inst == null || inst.lateFee <= 0) return r;
  final due = feeDueDate(r.month, inst);
  if (!DateTime.now().isAfter(DateTime(due.year, due.month, due.day, 23, 59))) return r;
  return FeeRecord.fromMap({...r.toMap(), 'amount': r.amount + inst.lateFee, 'lateFee': inst.lateFee});
}

String _receiptNo() => 'R-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';

class _FeeRow {
  _FeeRow(this.s, this.f, this.parents);
  final Membership s;
  final FeeRecord f; // may be unsaved (not paid yet)
  final List<Membership> parents;
}

/// Admin: who has paid this month, mark paid, send reminders.
class FeesPage extends StatefulWidget {
  const FeesPage({super.key, required this.m});
  final Membership m;
  @override
  State<FeesPage> createState() => _FeesPageState();
}

class _FeesPageState extends State<FeesPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _filter = 0; // 0 all, 1 pending, 2 paid
  int _v = 0;
  Institute? _inst;

  Future<List<_FeeRow>> _load() async {
    final b = context.appRead.backend;
    final id = widget.m.instituteId;
    final members = await b.members(id);
    final fees = await b.feesForMonth(id, monthKey(_month));
    _inst = await b.institute(id);
    if (widget.m.role == Role.admin) b.syncParentFees(id); // parents see what is due
    final byUid = {for (final f in fees) f.studentUid: f};
    final parents = members.where((x) => x.role == Role.parent && x.approved).toList();
    return [
      for (final s in approvedStudents(members))
        _FeeRow(
          s,
          withLateFee(byUid[s.uid] ?? FeeRecord(studentUid: s.uid, studentName: s.name, month: monthKey(_month), amount: s.monthlyFee), _inst),
          parents.where((x) => x.childUids.contains(s.uid)).toList(),
        ),
    ];
  }

  void _shift(int by) => setState(() {
        _month = DateTime(_month.year, _month.month + by);
        _v++;
      });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final isThis = monthKey(_month) == monthKey(DateTime.now());
    return Scaffold(
      appBar: InnerBar(
        title: tr('nav_fees'),
        subtitle: tr('collection'),
        showBack: false,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconBtn(icon: Icons.bar_chart_rounded, tooltip: tr('reports'), onTap: () => gated(context, Feature.reports, () => push(context, ReportsScreen(m: widget.m)))),
          const SizedBox(width: 10),
          IconBtn(
            icon: Icons.tune_rounded,
            tooltip: tr('fee_rules'),
            onTap: () async {
              final ok = await push<bool>(context, InstituteSettingsScreen(m: widget.m));
              if (ok == true) setState(() => _v++);
            },
          ),
        ]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
          child: Row(children: [
            IconBtn(icon: Icons.chevron_left_rounded, box: 40, onTap: () => _shift(-1)),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(monthLabel(monthKey(_month)), key: ValueKey(_month), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
            Opacity(opacity: isThis ? .35 : 1, child: IconBtn(icon: Icons.chevron_right_rounded, box: 40, onTap: isThis ? null : () => _shift(1))),
          ]),
        ),
        Expanded(
          child: Loader<List<_FeeRow>>(
            key: ValueKey(_v),
            load: _load,
            builder: (context, rows, reload) {
              final paid = rows.where((r) => r.f.paid).toList();
              final pend = rows.where((r) => !r.f.paid && r.f.amount > 0).toList();
              final got = rows.fold<int>(0, (a, r) => a + r.f.paidSoFar);
              final due = rows.fold<int>(0, (a, r) => a + r.f.balance);
              final shown = switch (_filter) { 1 => pend, 2 => paid, _ => rows };
              final dueDate = feeDueDate(monthKey(_month), _inst);
              final late = DateTime.now().isAfter(dueDate.add(const Duration(days: 1)));
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                children: [
                  FutureBuilder<List<FeeRecord>>(
                    future: context.appRead.backend.feeClaims(widget.m.instituteId),
                    builder: (context, snap) {
                      final n = snap.data?.length ?? 0;
                      if (n == 0) return const SizedBox.shrink();
                      return FadeIn(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            onTap: () async {
                              await push(context, ConfirmPaymentsScreen(m: widget.m));
                              setState(() => _v++);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: p.successTint, borderRadius: BorderRadius.circular(Gap.rCard)),
                              child: Row(children: [
                                IconBox(Icons.currency_rupee_rounded, fg: Colors.white, bg: p.success),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(trf('n_to_confirm', {'n': '$n'}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                                    Text(tr('tap_check_utr'), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  ]),
                                ),
                                PulseDot(color: p.success),
                                const SizedBox(width: 6),
                                Icon(Icons.chevron_right_rounded, color: p.success),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  FadeIn(
                    child: AppCard(
                      child: Row(children: [
                        Ring(
                          value: got + due == 0 ? 0 : got / (got + due),
                          size: 104,
                          stroke: 12,
                          color: p.success,
                          track: got + due == 0 ? p.cardAlt : p.dangerTint,
                          center: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('${pct(got, got + due)}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                            Text(tr('collected').toLowerCase(), style: TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            LegendDot(p.success, tr('collected')),
                            Padding(
                              padding: const EdgeInsets.only(left: 15, top: 2, bottom: 10),
                              child: CountUp(got, prefix: '₹', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -.5)),
                            ),
                            LegendDot(p.danger, tr('pending')),
                            Padding(
                              padding: const EdgeInsets.only(left: 15, top: 2),
                              child: Text(rupees(due), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -.5, color: p.danger)),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FadeIn(
                    delay: stagger(1),
                    child: Row(children: [
                      Icon(late ? Icons.warning_amber_rounded : Icons.event_rounded, size: 16, color: late ? p.danger : p.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${tr('due_by')} ${prettyDate(dueDate)}${(_inst?.lateFee ?? 0) > 0 ? ' · ${tr('late_fee')} ${rupees(_inst!.lateFee)}' : ''}',
                          style: TextStyle(color: late ? p.danger : p.muted, fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (pend.isNotEmpty)
                    FadeIn(
                      delay: stagger(2),
                      child: Row(children: [
                        Expanded(
                          child: SoftButton(
                            label: trf('remind_n', {'n': '${pend.length}'}),
                            icon: Icons.notifications_active_rounded,
                            color: p.successTint,
                            textColor: p.success,
                            onPressed: () => gated(
                              context,
                              Feature.feePlan,
                              () => showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                showDragHandle: true,
                                builder: (_) => _ReminderRun(rows: pend, message: _reminder),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SoftButton(
                          label: tr('group'),
                          icon: Icons.groups_rounded,
                          onPressed: () => SharePlus.instance.share(ShareParams(text: _bulkReminder())),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 12),
                  Segmented(
                    items: ['${tr('all')} ${rows.length}', '${tr('pending')} ${pend.length}', '${tr('paid')} ${paid.length}'],
                    index: _filter,
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                  const SizedBox(height: 12),
                  if (shown.isEmpty) EmptyState(icon: Icons.celebration_rounded, text: _filter == 1 ? tr('all_paid') : tr('no_students_yet')),
                  for (var i = 0; i < shown.length; i++)
                    FadeIn(
                      delay: stagger(i, stepMs: 35),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FeeTile(
                          r: shown[i],
                          index: i,
                          onTap: () async {
                            final changed = await _openSheet(shown[i]);
                            if (changed == true) setState(() => _v++);
                          },
                          onRemind: () => openWhatsApp(context, shown[i].parents.isNotEmpty ? shown[i].parents.first.phone : shown[i].s.phone, _reminder(shown[i])),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }

  String _reminder(_FeeRow r) {
    final upi = _inst?.upiId ?? '';
    return trf('fee_reminder_msg2', {
      'name': r.s.name,
      'month': monthLabel(r.f.month),
      'amt': rupees(r.f.balance),
      'due': prettyDate(feeDueDate(r.f.month, _inst)),
      'inst': widget.m.instituteName,
    }) +
        (upi.isEmpty ? '' : '\n${tr('pay_upi_to')} $upi') +
        '\n${tr('pay_in_app')}';
  }

  String _bulkReminder() => trf('fee_bulk_msg', {'month': monthLabel(monthKey(_month)), 'inst': widget.m.instituteName});

  Future<bool?> _openSheet(_FeeRow r) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FeeSheet(m: widget.m, r: r, reminder: _reminder(r)),
    );
  }
}

class _FeeTile extends StatelessWidget {
  const _FeeTile({required this.r, required this.index, required this.onTap, required this.onRemind});
  final _FeeRow r;
  final int index;
  final VoidCallback onTap, onRemind;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final f = r.f;
    final paid = f.paid;
    final sub = paid
        ? '${tr('paid')} · ${f.mode} · ${prettyDate(DateTime.fromMillisecondsSinceEpoch(f.paidOn))}'
        : [
            rupees(f.amount),
            if (f.partly) '${tr('paid')} ${rupees(f.paidSoFar)}',
            if (f.lateFee > 0) '+${tr('late_fee')}',
            if (r.s.feeNote.isNotEmpty) r.s.feeNote,
          ].join(' · ');
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Avatar(r.s.name, size: 42, index: index, photo: r.s.photo),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
          ]),
        ),
        if (paid)
          Tag(rupees(f.amount), fg: p.success, bg: p.successTint, leading: Icon(Icons.check_circle_rounded, size: 14, color: p.success))
        else if (f.waiting)
          Tag(tr('confirm_q'), fg: p.warn, bg: p.warnTint, leading: Icon(Icons.hourglass_top_rounded, size: 13, color: p.warn))
        else if (f.amount == 0)
          Tag(tr('no_fee_set'), fg: p.muted, bg: p.cardAlt)
        else ...[
          IconButton(onPressed: onRemind, tooltip: tr('remind'), icon: Icon(Icons.chat_rounded, color: p.success)),
          Tag(f.partly ? '${rupees(f.balance)} ${tr('left')}' : tr('due'), fg: f.partly ? p.warn : p.danger, bg: f.partly ? p.warnTint : p.dangerTint),
        ],
      ]),
    );
  }
}

/// Goes through every unpaid student one by one: WhatsApp the parent or student.
class _ReminderRun extends StatefulWidget {
  const _ReminderRun({required this.rows, required this.message});
  final List<_FeeRow> rows;
  final String Function(_FeeRow) message;
  @override
  State<_ReminderRun> createState() => _ReminderRunState();
}

class _ReminderRunState extends State<_ReminderRun> {
  int _i = 0;
  final Set<int> _sent = {};

  Future<void> _send(String phone) async {
    await openWhatsApp(context, phone, widget.message(widget.rows[_i]));
    setState(() {
      _sent.add(_i);
      if (_i < widget.rows.length - 1) _i++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = widget.rows[_i];
    final done = _sent.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('smart_reminders'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text(trf('n_of_m_sent', {'n': '$done', 'm': '${widget.rows.length}'}), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          GrowBar(value: widget.rows.isEmpty ? 0 : done / widget.rows.length, color: p.success, track: p.successTint),
          const SizedBox(height: 16),
          AppCard(
            color: p.cardAlt,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Avatar(r.s.name, size: 44, photo: r.s.photo),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${rupees(r.f.balance)} · ${monthLabel(r.f.month)}', style: TextStyle(color: p.danger, fontWeight: FontWeight.w700)),
                  ]),
                ),
                if (_sent.contains(_i)) Icon(Icons.check_circle_rounded, color: p.success),
              ]),
              const SizedBox(height: 10),
              Text(widget.message(r), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink2, fontSize: 12.5, height: 1.4)),
            ]),
          ),
          const SizedBox(height: 14),
          for (final par in r.parents.where((x) => x.phone.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PrimaryButton(label: '${tr('whatsapp')} · ${par.name} (${tr('role_parent')})', icon: Icons.chat_rounded, arrow: false, onPressed: () => _send(par.phone)),
            ),
          if (r.s.phone.isNotEmpty)
            SoftButton(label: '${tr('whatsapp')} · ${r.s.name}', icon: Icons.chat_outlined, color: p.successTint, textColor: p.success, onPressed: () => _send(r.s.phone)),
          const SizedBox(height: 10),
          Row(children: [
            TextButton.icon(onPressed: _i == 0 ? null : () => setState(() => _i--), icon: const Icon(Icons.chevron_left_rounded), label: Text(tr('back'))),
            const Spacer(),
            Text('${_i + 1} / ${widget.rows.length}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: _i >= widget.rows.length - 1 ? () => Navigator.pop(context) : () => setState(() => _i++),
              icon: Icon(_i >= widget.rows.length - 1 ? Icons.done_rounded : Icons.chevron_right_rounded),
              label: Text(_i >= widget.rows.length - 1 ? tr('done') : tr('skip')),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _FeeSheet extends StatefulWidget {
  const _FeeSheet({required this.m, required this.r, required this.reminder});
  final Membership m;
  final _FeeRow r;
  final String reminder;
  @override
  State<_FeeSheet> createState() => _FeeSheetState();
}

class _FeeSheetState extends State<_FeeSheet> {
  late final _amt = TextEditingController(text: '${widget.r.f.balance}');
  late final _base = TextEditingController(text: '${widget.r.s.monthlyFee + widget.r.s.discount}');
  late final _disc = TextEditingController(text: widget.r.s.discount == 0 ? '' : '${widget.r.s.discount}');
  late final _note = TextEditingController(text: widget.r.s.feeNote);
  late String _mode = widget.r.f.waiting ? 'UPI' : 'Cash';
  bool _busy = false;
  bool _plan = false;

  @override
  void initState() {
    super.initState();
    _amt.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_amt, _base, _disc, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job, String done, {int coin = 0, String who = ''}) async {
    setState(() => _busy = true);
    try {
      await job();
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      final nav = Navigator.of(context);
      if (coin <= 0) toast(context, done);
      nav.pop(true);
      // money came in: the ₹ coin drops into Vidu's bag
      if (coin > 0) showCoinDrop(nav.context, coin, title: who);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  FeeRecord _copy(FeeRecord f, Map<String, dynamic> change) => FeeRecord.fromMap({...f.toMap(), ...change});

  Future<void> _receive() async {
    final f = widget.r.f;
    final amt = int.tryParse(_amt.text.trim()) ?? 0;
    if (amt <= 0) {
      toast(context, tr('err_amount'));
      return;
    }
    if (!await ensureReceiptAddress(context, widget.m)) return;
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final by = f.claimBy.isNotEmpty ? f.claimBy : f.studentName;
    final utr = _mode == 'UPI' ? f.claimUtr : '';
    final FeeRecord rec;
    if (amt >= f.balance) {
      // whole (rest of the) fee received
      rec = _copy(f, {
        'amount': f.paidSoFar + amt,
        'paid': true,
        'paidOn': now,
        'mode': _mode,
        'receiptNo': _receiptNo(),
        'paidBy': by,
        'utr': utr,
        'claimed': false,
      });
    } else {
      final part = FeePart(amount: amt, at: now, mode: _mode, receiptNo: _receiptNo(), utr: utr, by: by);
      rec = _copy(f, {
        'parts': [...f.parts.map((x) => x.toMap()), part.toMap()],
        'claimed': false,
      });
    }
    await _run(() => context.appRead.backend.saveFee(widget.m.instituteId, rec), rec.paid ? tr('marked_paid') : trf('part_saved', {'amt': rupees(amt), 'left': rupees(rec.balance)}), coin: amt, who: f.studentName);
  }

  Future<void> _unpay() {
    final f = widget.r.f;
    final rec = FeeRecord(studentUid: f.studentUid, studentName: f.studentName, month: f.month, amount: f.amount, lateFee: f.lateFee);
    return _run(() => context.appRead.backend.saveFee(widget.m.instituteId, rec), tr('marked_unpaid'));
  }

  Future<void> _waive() {
    final f = widget.r.f;
    final rec = _copy(f, {'amount': f.amount - f.lateFee, 'lateFee': -1});
    return _run(() => context.appRead.backend.saveFee(widget.m.instituteId, rec), tr('late_fee_waived'));
  }

  Future<void> _savePlan() async {
    if (!planHas(context, Feature.feePlan)) return showUpgradeSheet(context, need: minPlan(Feature.feePlan));
    final base = int.tryParse(_base.text.trim()) ?? 0;
    var disc = int.tryParse(_disc.text.trim()) ?? 0;
    if (disc > base) disc = base;
    final b = context.appRead.backend;
    return _run(() async {
      await b.setFeePlan(widget.r.s, monthlyFee: base - disc, discount: disc, note: _note.text.trim());
      await b.syncParentFees(widget.m.instituteId);
    }, tr('saved'));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = widget.r;
    final f = r.f;
    final amt = int.tryParse(_amt.text.trim()) ?? 0;
    final full = amt >= f.balance;
    final base = int.tryParse(_base.text.trim()) ?? 0;
    final disc = int.tryParse(_disc.text.trim()) ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(r.s.name, size: 48, photo: r.s.photo),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.s.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                Text([monthLabel(f.month), if (r.s.feeNote.isNotEmpty) r.s.feeNote].join(' · '), style: TextStyle(color: p.muted)),
              ]),
            ),
            f.paid
                ? Tag(tr('paid'), fg: p.success, bg: p.successTint)
                : (f.partly ? Tag(tr('partly_paid'), fg: p.warn, bg: p.warnTint) : Tag(tr('due'), fg: p.danger, bg: p.dangerTint)),
          ]),
          const SizedBox(height: 16),
          if (f.paid) ...[
            AppCard(
              color: p.successTint,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rupees(f.amount), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.success)),
                Text('${f.mode} · ${prettyDate(DateTime.fromMillisecondsSinceEpoch(f.paidOn))}', style: TextStyle(color: p.success, fontWeight: FontWeight.w700)),
                if (f.receiptNo.isNotEmpty) Text('${tr('receipt')}: ${f.receiptNo}', style: TextStyle(color: p.success)),
              ]),
            ),
            if (f.parts.isNotEmpty) ...[const SizedBox(height: 10), _parts(p, f)],
            const SizedBox(height: 12),
            SoftButton(
              label: tr('receipt_pdf'),
              icon: Icons.picture_as_pdf_outlined,
              onPressed: () => shareFeeReceipt(context, widget.m.instituteId, f, studentCode: r.s.studentCode),
            ),
            const SizedBox(height: 8),
            SoftButton(
              label: tr('send_receipt'),
              color: p.successTint,
              textColor: p.success,
              icon: Icons.chat_outlined,
              onPressed: () => openWhatsApp(
                  context,
                  r.parents.isNotEmpty ? r.parents.first.phone : r.s.phone,
                  trf('receipt_msg', {
                    'name': r.s.name,
                    'amt': rupees(f.amount),
                    'month': monthLabel(f.month),
                    'mode': f.mode,
                    'no': f.receiptNo,
                    'inst': widget.m.instituteName,
                  })),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : _unpay, child: Text(tr('mark_unpaid'), style: TextStyle(color: p.danger))),
          ] else ...[
            if (f.waiting)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.warnTint, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.hourglass_top_rounded, color: p.warn, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(trf('claim_info', {'by': f.claimBy, 'utr': f.claimUtr.isEmpty ? '—' : f.claimUtr}),
                        style: TextStyle(color: p.warn, fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.35)),
                  ),
                ]),
              ),
            AppCard(
              color: p.cardAlt,
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                _line(p, tr('month_fee'), rupees(f.amount - (f.lateFee > 0 ? f.lateFee : 0))),
                if (f.lateFee > 0)
                  Row(children: [
                    Expanded(child: Text('${tr('late_fee')} (+)', style: TextStyle(color: p.danger, fontWeight: FontWeight.w700))),
                    TextButton(onPressed: _busy ? null : _waive, child: Text(tr('waive'))),
                    Text(rupees(f.lateFee), style: TextStyle(color: p.danger, fontWeight: FontWeight.w800)),
                  ]),
                if (f.lateFee < 0) _line(p, tr('late_fee'), tr('waived')),
                if (f.partly) _line(p, tr('paid_so_far'), '− ${rupees(f.paidSoFar)}', color: p.success),
                const Divider(),
                _line(p, tr('balance'), rupees(f.balance), bold: true),
              ]),
            ),
            if (f.partly) ...[const SizedBox(height: 10), _parts(p, f)],
            const SizedBox(height: 12),
            FieldLabel(tr('amount_received')),
            TextField(
              controller: _amt,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: InputDecoration(prefixText: '₹ ', helperText: full ? null : tr('instalment_help')),
            ),
            const SizedBox(height: 12),
            FieldLabel(tr('paid_by')),
            Row(children: [
              for (final mode in ['Cash', 'UPI', 'Bank'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoicePill(label: mode, selected: _mode == mode, onTap: () => setState(() => _mode = mode)),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            PrimaryButton(
              label: full ? tr('mark_paid') : trf('record_part', {'amt': rupees(amt)}),
              icon: full ? Icons.check_circle_rounded : Icons.call_split_rounded,
              arrow: false,
              busy: _busy,
              onPressed: _receive,
            ),
            const SizedBox(height: 10),
            SoftButton(
              label: tr('remind_whatsapp'),
              icon: Icons.chat_rounded,
              color: p.successTint,
              textColor: p.success,
              onPressed: () => openWhatsApp(context, r.parents.isNotEmpty ? r.parents.first.phone : r.s.phone, widget.reminder),
            ),
          ],
          const SizedBox(height: 14),
          Divider(color: p.border),
          InkWell(
            onTap: () => setState(() => _plan = !_plan),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                IconBox(Icons.sell_outlined, fg: p.brand, bg: p.brandTint, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('fee_plan'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      '${rupees(r.s.monthlyFee)}/${tr('month_short')}${r.s.discount > 0 ? ' · ${tr('discount')} ${rupees(r.s.discount)}' : ''}${r.s.feeNote.isEmpty ? '' : ' · ${r.s.feeNote}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12.5),
                    ),
                  ]),
                ),
                Icon(_plan ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.muted),
              ]),
            ),
          ),
          if (_plan) ...[
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FieldLabel(tr('full_fee')),
                  TextField(controller: _base, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixText: '₹ ')),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FieldLabel(tr('discount')),
                  TextField(controller: _disc, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixText: '− ₹ ', hintText: '0')),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in ['Merit scholarship', 'Sibling discount', 'Staff child', 'Need-based'])
                ChoicePill(label: n, selected: _note.text == n, onTap: () => setState(() => _note.text = _note.text == n ? '' : n)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _note, decoration: InputDecoration(hintText: tr('scholarship_hint'), prefixIcon: const Icon(Icons.school_outlined))),
            const SizedBox(height: 10),
            Text(trf('pays_per_month', {'amt': rupees((base - disc).clamp(0, base))}), style: TextStyle(color: p.brand, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('monthly_fee_note'), style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 10),
            PrimaryButton(label: tr('save_plan'), arrow: false, busy: _busy, onPressed: _savePlan),
          ],
        ]),
      ),
    );
  }

  Widget _line(Palette p, String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? p.ink2))),
          Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: bold ? 17 : 14, color: color ?? p.ink)),
        ]),
      );

  Widget _parts(Palette p, FeeRecord f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('instalments'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final x in f.parts)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(Icons.check_circle_outline_rounded, size: 16, color: p.success),
              const SizedBox(width: 6),
              Expanded(child: Text('${prettyDate(DateTime.fromMillisecondsSinceEpoch(x.at))} · ${x.mode}${x.receiptNo.isEmpty ? '' : ' · ${x.receiptNo}'}', style: TextStyle(color: p.ink2, fontSize: 12.5))),
              Text(rupees(x.amount), style: TextStyle(fontWeight: FontWeight.w800, color: p.success)),
            ]),
          ),
      ]);
}


// ---------------------------------------------------------------------------
// Student / parent: own fees (either can pay)
// ---------------------------------------------------------------------------

class MyFeesPage extends StatefulWidget {
  const MyFeesPage({super.key, required this.m, required this.studentUid, required this.studentName});
  final Membership m;
  final String studentUid, studentName;
  @override
  State<MyFeesPage> createState() => _MyFeesPageState();
}

class _MyFeesPageState extends State<MyFeesPage> {
  int _v = 0;

  Future<(List<FeeRecord>, Institute?)> _load() async {
    final b = context.appRead.backend;
    return (await b.feesForStudent(widget.m.instituteId, widget.studentUid), await b.institute(widget.m.instituteId));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = widget.m;
    return Scaffold(
      appBar: InnerBar(title: m.role == Role.parent ? '${tr('nav_fees')} · ${firstName(widget.studentName)}' : tr('my_fees'), subtitle: m.instituteName, showBack: false),
      body: Loader<(List<FeeRecord>, Institute?)>(
        key: ValueKey(_v),
        load: _load,
        builder: (context, d, reload) {
          final fees = d.$1;
          final inst = d.$2;
          final cur = monthKey(DateTime.now());
          final saved = fees.where((f) => f.month == cur).firstOrNull;
          final monthly = m.role == Role.student
              ? m.monthlyFee
              : (saved?.amount ?? m.childFees[widget.studentUid] ?? (fees.isEmpty ? 0 : fees.first.amount - fees.first.lateFee.clamp(0, 1 << 30)));
          // this month's fee, with the late fee once the due date has passed
          final rec = withLateFee(saved ?? FeeRecord(studentUid: widget.studentUid, studentName: widget.studentName, month: cur, amount: monthly), inst);
          final thisOne = saved == null ? null : rec;
          final amount = rec.balance;
          final paidThis = rec.paid;
          final waiting = rec.waiting;
          final dueDate = feeDueDate(cur, inst);
          final canPay = !paidThis && !waiting && amount > 0 && (inst?.upiId ?? '').isNotEmpty && planHas(context, Feature.upiFees);
          final total = fees.fold<int>(0, (a, f) => a + f.paidSoFar);
          Future<void> pay() async {
            final done = await showPayFee(context,
                m: m,
                inst: inst!,
                studentUid: widget.studentUid,
                studentName: widget.studentName,
                month: cur,
                amount: amount,
                existing: rec);
            if (done == true) setState(() => _v++);
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
            children: [
              FadeIn(
                child: FeatureCard(
                  gradient: paidThis ? LinearGradient(colors: [p.success, const Color(0xFF0E9F76)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(monthLabel(cur).toUpperCase(), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: .5))),
                      if (paidThis)
                        const GlassChip('Paid', icon: Icons.check_rounded, solid: true)
                      else if (waiting)
                        GlassChip(tr('waiting_confirm'), icon: Icons.hourglass_top_rounded)
                      else
                        GlassChip(tr('due')),
                    ]),
                    const SizedBox(height: 6),
                    Text(paidThis ? rupees(rec.amount) : (amount == 0 ? '—' : rupees(amount)), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1)),
                    const SizedBox(height: 4),
                    if (paidThis)
                      Text('${tr('paid_on')} ${prettyDate(DateTime.fromMillisecondsSinceEpoch(thisOne!.paidOn))} · ${thisOne.mode}${thisOne.paidBy.isEmpty ? '' : ' · ${thisOne.paidBy}'}',
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))
                    else if (waiting)
                      Text(trf('waiting_sub', {'utr': thisOne!.claimUtr.isEmpty ? '—' : thisOne.claimUtr}), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, height: 1.35))
                    else ...[
                      Text(
                        [
                          '${tr('due_by')} ${prettyDate(dueDate)}',
                          if (rec.lateFee > 0) '${tr('late_fee')} ${rupees(rec.lateFee)} ${tr('added')}',
                          if (rec.partly) '${tr('paid_so_far')} ${rupees(rec.paidSoFar)}',
                        ].join(' · '),
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, height: 1.35),
                      ),
                      if (!canPay) Text(tr('pay_at_institute'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    ],
                    if (canPay) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: pay,
                        child: Pressable(
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.bolt_rounded, color: p.brandDeep),
                              const SizedBox(width: 6),
                              Text(tr('pay_now_upi'), style: TextStyle(color: p.brandDeep, fontWeight: FontWeight.w800, fontSize: 15.5)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(m.role == Role.parent ? tr('either_pays_parent') : tr('either_pays_student'), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, height: 1.35)),
                    ],
                    if (paidThis) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => shareFeeReceipt(context, m.instituteId, thisOne!, inst: inst, studentCode: m.role == Role.student ? m.studentCode : ''),
                        child: const GlassChip('Receipt PDF', icon: Icons.picture_as_pdf_outlined, solid: true),
                      ),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              FadeIn(
                delay: stagger(1),
                child: Row(children: [
                  Expanded(child: _mini(p, tr('total_paid'), rupees(total), p.success)),
                  const SizedBox(width: 10),
                  Expanded(child: _mini(p, tr('monthly_fee'), monthly == 0 ? '—' : rupees(monthly), p.brand)),
                ]),
              ),
              const SizedBox(height: 8),
              SectionTitle(tr('history')),
              const SizedBox(height: 8),
              if (fees.isEmpty) EmptyState(icon: Icons.receipt_long_outlined, text: tr('no_fee_records')),
              for (var i = 0; i < fees.length; i++)
                FadeIn(
                  delay: stagger(i + 2, stepMs: 40),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(12),
                      onTap: fees[i].paid ? () => shareFeeReceipt(context, m.instituteId, fees[i], inst: inst, studentCode: m.role == Role.student ? m.studentCode : '') : null,
                      child: Row(children: [
                        IconBox(
                          fees[i].paid ? Icons.check_rounded : (fees[i].waiting ? Icons.hourglass_top_rounded : Icons.schedule_rounded),
                          fg: fees[i].paid ? p.success : (fees[i].waiting ? p.warn : p.danger),
                          bg: fees[i].paid ? p.successTint : (fees[i].waiting ? p.warnTint : p.dangerTint),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(monthLabel(fees[i].month), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(
                              fees[i].paid
                                  ? [fees[i].mode, if (fees[i].paidBy.isNotEmpty) '${tr('by')} ${fees[i].paidBy}', fees[i].receiptNo].where((e) => e.isNotEmpty).join(' · ')
                                  : (fees[i].waiting ? tr('waiting_confirm') : (fees[i].partly ? '${tr('partly_paid')} · ${rupees(fees[i].paidSoFar)}' : tr('due'))),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(rupees(fees[i].amount), style: TextStyle(fontWeight: FontWeight.w800, color: fees[i].paid ? p.success : (fees[i].waiting ? p.warn : p.danger))),
                          if (fees[i].paid) Text('PDF ↓', style: TextStyle(color: p.brand, fontWeight: FontWeight.w800, fontSize: 11.5)),
                        ]),
                      ]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _mini(Palette p, String k, String v, Color c) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: c)),
        ]),
      );
}
