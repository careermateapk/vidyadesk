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

class _FeeRow {
  _FeeRow(this.s, this.f);
  final Membership s;
  final FeeRecord f; // may be unsaved (not paid yet)
}

String _receiptNo() => 'R-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';

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

  Future<List<_FeeRow>> _load() async {
    final b = context.appRead.backend;
    final members = await b.members(widget.m.instituteId);
    final fees = await b.feesForMonth(widget.m.instituteId, monthKey(_month));
    final byUid = {for (final f in fees) f.studentUid: f};
    return [
      for (final s in approvedStudents(members))
        _FeeRow(s, byUid[s.uid] ?? FeeRecord(studentUid: s.uid, studentName: s.name, month: monthKey(_month), amount: s.monthlyFee)),
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
      appBar: InnerBar(title: tr('nav_fees'), subtitle: tr('collection'), showBack: false),
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
              final pend = rows.where((r) => !r.f.paid).toList();
              final got = paid.fold<int>(0, (a, r) => a + r.f.amount);
              final due = pend.fold<int>(0, (a, r) => a + r.f.amount);
              final shown = switch (_filter) { 1 => pend, 2 => paid, _ => rows };
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
                  const SizedBox(height: 12),
                  if (pend.isNotEmpty)
                    FadeIn(
                      delay: stagger(1),
                      child: SoftButton(
                        label: trf('remind_all', {'n': '${pend.length}'}),
                        icon: Icons.campaign_rounded,
                        color: p.successTint,
                        textColor: p.success,
                        onPressed: () => SharePlus.instance.share(ShareParams(text: _bulkReminder(pend))),
                      ),
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
                            if (changed == true) reload();
                          },
                          onRemind: () => openWhatsApp(context, shown[i].s.phone, _reminder(shown[i])),
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

  String _reminder(_FeeRow r) => trf('fee_reminder_msg', {'name': r.s.name, 'month': monthLabel(r.f.month), 'amt': rupees(r.f.amount), 'inst': widget.m.instituteName});

  String _bulkReminder(List<_FeeRow> pend) => trf('fee_bulk_msg', {'month': monthLabel(monthKey(_month)), 'inst': widget.m.instituteName});

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
    final paid = r.f.paid;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Avatar(r.s.name, size: 42, index: index, photo: r.s.photo),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              paid ? '${tr('paid')} · ${r.f.mode} · ${prettyDate(DateTime.fromMillisecondsSinceEpoch(r.f.paidOn))}' : rupees(r.f.amount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 12.5),
            ),
          ]),
        ),
        if (paid)
          Tag(rupees(r.f.amount), fg: p.success, bg: p.successTint, leading: Icon(Icons.check_circle_rounded, size: 14, color: p.success))
        else if (r.f.waiting)
          Tag(tr('confirm_q'), fg: p.warn, bg: p.warnTint, leading: Icon(Icons.hourglass_top_rounded, size: 13, color: p.warn))
        else ...[
          IconButton(onPressed: onRemind, tooltip: tr('remind'), icon: Icon(Icons.chat_rounded, color: p.success)),
          Tag(tr('due'), fg: p.danger, bg: p.dangerTint),
        ],
      ]),
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
  late final _amt = TextEditingController(text: '${widget.r.f.amount}');
  late final _monthly = TextEditingController(text: '${widget.r.s.monthlyFee}');
  late String _mode = widget.r.f.waiting ? 'UPI' : 'Cash';
  bool _busy = false;

  @override
  void dispose() {
    _amt.dispose();
    _monthly.dispose();
    super.dispose();
  }

  Future<void> _markPaid(bool paid) async {
    final f = widget.r.f;
    final amt = int.tryParse(_amt.text.trim()) ?? f.amount;
    setState(() => _busy = true);
    try {
      final rec = FeeRecord(
        studentUid: f.studentUid,
        studentName: f.studentName,
        month: f.month,
        amount: amt,
        paid: paid,
        paidOn: paid ? DateTime.now().millisecondsSinceEpoch : 0,
        mode: paid ? _mode : '',
        receiptNo: paid ? _receiptNo() : '',
        paidBy: paid ? (f.claimBy.isNotEmpty ? f.claimBy : f.studentName) : '',
        utr: paid && _mode == 'UPI' ? f.claimUtr : '',
      );
      await context.appRead.backend.saveFee(widget.m.instituteId, rec);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      toast(context, paid ? tr('marked_paid') : tr('marked_unpaid'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMonthly() async {
    final v = int.tryParse(_monthly.text.trim());
    if (v == null || v < 0) return;
    setState(() => _busy = true);
    try {
      await context.appRead.backend.setMonthlyFee(widget.r.s, v);
      if (!mounted) return;
      toast(context, tr('saved'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = widget.r;
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
                Text(monthLabel(r.f.month), style: TextStyle(color: p.muted)),
              ]),
            ),
            r.f.paid ? Tag(tr('paid'), fg: p.success, bg: p.successTint) : Tag(tr('due'), fg: p.danger, bg: p.dangerTint),
          ]),
          const SizedBox(height: 16),
          if (r.f.paid) ...[
            AppCard(
              color: p.successTint,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rupees(r.f.amount), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.success)),
                Text('${r.f.mode} · ${prettyDate(DateTime.fromMillisecondsSinceEpoch(r.f.paidOn))}', style: TextStyle(color: p.success, fontWeight: FontWeight.w700)),
                if (r.f.receiptNo.isNotEmpty) Text('${tr('receipt')}: ${r.f.receiptNo}', style: TextStyle(color: p.success)),
              ]),
            ),
            const SizedBox(height: 12),
            SoftButton(
              label: tr('receipt_pdf'),
              icon: Icons.picture_as_pdf_outlined,
              onPressed: () => shareFeeReceipt(context, widget.m.instituteId, r.f, studentCode: r.s.studentCode),
            ),
            const SizedBox(height: 8),
            SoftButton(
              label: tr('send_receipt'),
              color: p.successTint,
              textColor: p.success,
              icon: Icons.chat_outlined,
              onPressed: () => openWhatsApp(
                  context,
                  r.s.phone,
                  trf('receipt_msg', {
                    'name': r.s.name,
                    'amt': rupees(r.f.amount),
                    'month': monthLabel(r.f.month),
                    'mode': r.f.mode,
                    'no': r.f.receiptNo,
                    'inst': widget.m.instituteName,
                  })),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : () => _markPaid(false), child: Text(tr('mark_unpaid'), style: TextStyle(color: p.danger))),
          ] else ...[
            if (r.f.waiting)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.warnTint, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.hourglass_top_rounded, color: p.warn, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(trf('claim_info', {'by': r.f.claimBy, 'utr': r.f.claimUtr.isEmpty ? '—' : r.f.claimUtr}),
                        style: TextStyle(color: p.warn, fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.35)),
                  ),
                ]),
              ),
            FieldLabel(tr('amount')),
            TextField(
              controller: _amt,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(prefixText: '₹ '),
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
            PrimaryButton(label: tr('mark_paid'), icon: Icons.check_circle_rounded, arrow: false, busy: _busy, onPressed: () => _markPaid(true)),
            const SizedBox(height: 10),
            SoftButton(label: tr('remind_whatsapp'), icon: Icons.chat_rounded, color: p.successTint, textColor: p.success, onPressed: () => openWhatsApp(context, r.s.phone, widget.reminder)),
          ],
          const SizedBox(height: 18),
          Divider(color: p.border),
          const SizedBox(height: 8),
          FieldLabel(tr('monthly_fee')),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _monthly,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(prefixText: '₹ '),
              ),
            ),
            const SizedBox(width: 8),
            SoftButton(label: tr('save'), onPressed: _busy ? null : _saveMonthly, height: 56),
          ]),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('monthly_fee_note'), style: TextStyle(color: p.muted, fontSize: 12))),
        ]),
      ),
    );
  }
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
          final thisOne = fees.where((f) => f.month == cur).firstOrNull;
          final monthly = m.role == Role.student ? m.monthlyFee : (thisOne?.amount ?? (fees.isEmpty ? 0 : fees.first.amount));
          final amount = thisOne?.amount ?? monthly;
          final paidThis = thisOne?.paid == true;
          final waiting = thisOne?.waiting == true;
          final canPay = !paidThis && !waiting && amount > 0 && (inst?.upiId ?? '').isNotEmpty;
          final total = fees.where((f) => f.paid).fold<int>(0, (a, f) => a + f.amount);
          Future<void> pay() async {
            final done = await showPayFee(context,
                m: m,
                inst: inst!,
                studentUid: widget.studentUid,
                studentName: widget.studentName,
                month: cur,
                amount: amount,
                existing: thisOne);
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
                    Text(amount == 0 ? '—' : rupees(amount), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1)),
                    const SizedBox(height: 4),
                    if (paidThis)
                      Text('${tr('paid_on')} ${prettyDate(DateTime.fromMillisecondsSinceEpoch(thisOne!.paidOn))} · ${thisOne.mode}${thisOne.paidBy.isEmpty ? '' : ' · ${thisOne.paidBy}'}',
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))
                    else if (waiting)
                      Text(trf('waiting_sub', {'utr': thisOne!.claimUtr.isEmpty ? '—' : thisOne.claimUtr}), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, height: 1.35))
                    else if (!canPay)
                      Text(tr('pay_at_institute'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
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
                                  : (fees[i].waiting ? tr('waiting_confirm') : tr('due')),
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
