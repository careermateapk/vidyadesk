import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';

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
        Avatar(r.s.name, size: 42, index: index),
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
  String _mode = 'Cash';
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
            Avatar(r.s.name, size: 48),
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
              label: tr('send_receipt'),
              icon: Icons.receipt_long_rounded,
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
// Student / parent: own fees
// ---------------------------------------------------------------------------

class MyFeesPage extends StatelessWidget {
  const MyFeesPage({super.key, required this.m, required this.studentUid, required this.studentName});
  final Membership m;
  final String studentUid, studentName;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: m.role == Role.parent ? '${tr('nav_fees')} · ${firstName(studentName)}' : tr('my_fees'), showBack: false),
      body: Loader<List<FeeRecord>>(
        load: () => context.appRead.backend.feesForStudent(m.instituteId, studentUid),
        builder: (context, fees, reload) {
          final cur = monthKey(DateTime.now());
          final thisOne = fees.where((f) => f.month == cur).firstOrNull;
          final monthly = m.role == Role.student ? m.monthlyFee : (thisOne?.amount ?? 0);
          final paidThis = thisOne?.paid == true;
          final total = fees.where((f) => f.paid).fold<int>(0, (a, f) => a + f.amount);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
            children: [
              FadeIn(
                child: AppCard(
                  gradient: paidThis ? LinearGradient(colors: [p.success, p.success.withValues(alpha: .75)]) : p.hero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(monthLabel(cur), style: const TextStyle(color: Color(0xCCFFFFFF), fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Tag(paidThis ? tr('paid') : tr('due'), fg: paidThis ? p.success : const Color(0xFF7A4A00), bg: paidThis ? Colors.white : const Color(0xFFFFD27A)),
                    ]),
                    const SizedBox(height: 8),
                    Text(rupees(thisOne?.amount ?? monthly), style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -.5)),
                    const SizedBox(height: 4),
                    Text(
                      paidThis ? '${tr('paid_on')} ${prettyDate(DateTime.fromMillisecondsSinceEpoch(thisOne!.paidOn))} · ${thisOne.mode}' : tr('pay_at_institute'),
                      style: const TextStyle(color: Color(0xDDFFFFFF), fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              FadeIn(
                delay: stagger(1),
                child: Row(children: [
                  Expanded(child: _mini(p, tr('total_paid'), rupees(total), p.success)),
                  const SizedBox(width: 10),
                  Expanded(child: _mini(p, tr('monthly_fee'), monthly == 0 ? '—' : rupees(monthly), p.brand)),
                ]),
              ),
              const SizedBox(height: 16),
              SectionTitle(tr('history')),
              const SizedBox(height: 8),
              if (fees.isEmpty) EmptyState(icon: Icons.receipt_long_rounded, text: tr('no_fee_records')),
              for (var i = 0; i < fees.length; i++)
                FadeIn(
                  delay: stagger(i + 2, stepMs: 40),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        IconBox(fees[i].paid ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded,
                            fg: fees[i].paid ? p.success : p.danger, bg: fees[i].paid ? p.successTint : p.dangerTint),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(monthLabel(fees[i].month), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(
                              fees[i].paid ? '${fees[i].mode} · ${fees[i].receiptNo}' : tr('due'),
                              style: TextStyle(color: p.muted, fontSize: 12.5),
                            ),
                          ]),
                        ),
                        Text(rupees(fees[i].amount), style: TextStyle(fontWeight: FontWeight.w800, color: fees[i].paid ? p.success : p.danger)),
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
