import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/backend.dart' show newId;
import '../data/models.dart';
import '../services/reports.dart';
import '../services/push.dart';
import '../ui/widgets.dart';
import 'checkin.dart';
import 'common.dart';
import 'file_sheet.dart';
import 'payments.dart' show askUtr;
import '../services/upi.dart';

const expenseCats = ['rent', 'electricity', 'salary', 'stationery', 'marketing', 'internet', 'maintenance', 'other'];
const incomeCats = ['admission', 'books', 'other_income'];

IconData catIcon(String c) => switch (c) {
      'rent' => Icons.home_work_outlined,
      'electricity' => Icons.bolt_rounded,
      'salary' => Icons.badge_outlined,
      'stationery' => Icons.edit_outlined,
      'marketing' => Icons.campaign_outlined,
      'internet' => Icons.wifi_rounded,
      'maintenance' => Icons.build_outlined,
      'admission' => Icons.how_to_reg_outlined,
      'books' => Icons.menu_book_outlined,
      'fees' => Icons.school_outlined,
      _ => Icons.more_horiz_rounded,
    };

/// Month picker row used on money screens.
class MonthBar extends StatelessWidget {
  const MonthBar({super.key, required this.month, required this.onShift});
  final DateTime month;
  final ValueChanged<int> onShift;
  @override
  Widget build(BuildContext context) {
    final isThis = monthKey(month) == monthKey(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Row(children: [
        IconBtn(icon: Icons.chevron_left_rounded, box: 40, onTap: () => onShift(-1)),
        Expanded(child: Text(monthLabel(monthKey(month)), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        Opacity(opacity: isThis ? .35 : 1, child: IconBtn(icon: Icons.chevron_right_rounded, box: 40, onTap: isThis ? null : () => onShift(1))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Income & expenses
// ---------------------------------------------------------------------------

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, required this.m});
  final Membership m;
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _v = 0;

  Future<(List<Txn>, int)> _load() async {
    final b = context.appRead.backend;
    final id = widget.m.instituteId;
    final mk = monthKey(_month);
    final fees = await b.feesForMonth(id, mk);
    return (await b.ledger(id, mk), fees.fold<int>(0, (a, f) => a + f.paidSoFar));
  }

  Future<void> _add(bool income) async {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => TxnSheet(m: widget.m, income: income, month: _month));
    if (ok == true) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('income_expenses'),
      subtitle: widget.m.instituteName,
      body: Column(children: [
        MonthBar(
          month: _month,
          onShift: (d) => setState(() {
            _month = DateTime(_month.year, _month.month + d);
            _v++;
          }),
        ),
        Expanded(
          child: Loader<(List<Txn>, int)>(
            key: ValueKey(_v),
            load: _load,
            builder: (context, d, reload) {
              final txns = d.$1;
              final feeIncome = d.$2;
              final other = txns.where((t) => t.isIncome).fold<int>(0, (a, t) => a + t.amount);
              final income = feeIncome + other;
              final spent = txns.where((t) => !t.isIncome).fold<int>(0, (a, t) => a + t.amount);
              final profit = income - spent;
              final byCat = <String, int>{};
              for (final t in txns.where((t) => !t.isIncome)) {
                byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
              }
              final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
                children: [
                  FadeIn(
                    child: FeatureCard(
                      gradient: profit < 0 ? LinearGradient(colors: [p.danger, const Color(0xFFC92A55)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text((profit < 0 ? tr('loss') : tr('profit')).toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .5)),
                        const SizedBox(height: 4),
                        Text(rupees(profit.abs()), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          GlassChip('${tr('income')} ${rupees(income)}', icon: Icons.south_west_rounded),
                          GlassChip('${tr('expenses')} ${rupees(spent)}', icon: Icons.north_east_rounded),
                        ]),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: SoftButton(label: tr('add_income'), icon: Icons.add_rounded, color: p.successTint, textColor: p.success, onPressed: () => _add(true))),
                    const SizedBox(width: 10),
                    Expanded(child: SoftButton(label: tr('add_expense'), icon: Icons.remove_rounded, color: p.dangerTint, textColor: p.danger, onPressed: () => _add(false))),
                  ]),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('income'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 8),
                      _bar(p, tr('cat_fees'), feeIncome, income, p.success, Icons.school_outlined),
                      for (final c in incomeCats)
                        if (txns.any((t) => t.isIncome && t.category == c))
                          _bar(p, tr('cat_$c'), txns.where((t) => t.isIncome && t.category == c).fold<int>(0, (a, t) => a + t.amount), income, p.success, catIcon(c)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('expenses'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 8),
                      if (cats.isEmpty) Text(tr('no_expenses'), style: TextStyle(color: p.muted)),
                      for (final c in cats) _bar(p, tr('cat_${c.key}'), c.value, spent, p.danger, catIcon(c.key)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  SectionTitle(tr('entries')),
                  const SizedBox(height: 6),
                  if (txns.isEmpty) EmptyState(icon: Icons.receipt_long_outlined, text: tr('no_entries')),
                  for (var i = 0; i < txns.length; i++)
                    FadeIn(
                      delay: stagger(i, stepMs: 35),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TxnTile(
                          t: txns[i],
                          onDelete: () async {
                            final yes = await confirmDelete(context, txns[i].note.isEmpty ? tr('cat_${txns[i].category}') : txns[i].note);
                            if (!yes || !context.mounted) return;
                            try {
                              await context.appRead.backend.deleteTxn(widget.m.instituteId, txns[i].id);
                              setState(() => _v++);
                            } catch (e) {
                              if (context.mounted) toast(context, errorMessage(e));
                            }
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SoftButton(
                    label: tr('download_report'),
                    icon: Icons.download_rounded,
                    onPressed: () => showReportShare(context, ledgerReport(widget.m.instituteName, monthKey(_month), txns, feeIncome)),
                  ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _bar(Palette p, String label, int v, int total, Color c, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          Row(children: [
            Icon(icon, size: 17, color: c),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
            Text(rupees(v), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          GrowBar(value: total == 0 ? 0 : v / total, color: c, track: c.withValues(alpha: .12), height: 6),
        ]),
      );
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.t, required this.onDelete});
  final Txn t;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = t.isIncome ? p.success : p.danger;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        IconBox(catIcon(t.category), fg: c, bg: c.withValues(alpha: .12)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.refName.isNotEmpty ? '${tr('cat_${t.category}')} · ${t.refName}' : (t.note.isEmpty ? tr('cat_${t.category}') : t.note), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text([prettyDate(DateTime.fromMillisecondsSinceEpoch(t.date)), if (t.mode.isNotEmpty) t.mode, if (t.note.isNotEmpty && t.refName.isEmpty) tr('cat_${t.category}')].join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        Text('${t.isIncome ? '+' : '−'}${rupees(t.amount)}', style: TextStyle(fontWeight: FontWeight.w800, color: c)),
        PopupMenuButton<int>(
          icon: Icon(Icons.more_vert_rounded, color: p.muted, size: 20),
          onSelected: (_) => onDelete(),
          itemBuilder: (_) => [PopupMenuItem(value: 0, child: Text(tr('delete'), style: TextStyle(color: p.danger)))],
        ),
      ]),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String what) async {
  final p = context.pal;
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('delete_q')),
      content: Text(what),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('delete'), style: TextStyle(color: p.danger))),
      ],
    ),
  );
  return yes == true;
}

class TxnSheet extends StatefulWidget {
  const TxnSheet({super.key, required this.m, required this.income, required this.month});
  final Membership m;
  final bool income;
  final DateTime month;
  @override
  State<TxnSheet> createState() => _TxnSheetState();
}

class _TxnSheetState extends State<TxnSheet> {
  final _amt = TextEditingController();
  final _note = TextEditingController();
  late String _cat = widget.income ? incomeCats.first : expenseCats.first;
  String _mode = 'Cash';
  late DateTime _date = monthKey(widget.month) == monthKey(DateTime.now()) ? DateTime.now() : DateTime(widget.month.year, widget.month.month, 1);
  bool _busy = false;

  @override
  void dispose() {
    _amt.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt = int.tryParse(_amt.text.trim()) ?? 0;
    if (amt <= 0) {
      toast(context, tr('err_amount'));
      return;
    }
    setState(() => _busy = true);
    try {
      final app = context.appRead;
      await app.backend.saveTxn(
        widget.m.instituteId,
        Txn(
          id: newId(),
          isIncome: widget.income,
          category: _cat,
          amount: amt,
          date: DateTime(_date.year, _date.month, _date.day, 12).millisecondsSinceEpoch,
          note: _note.text.trim(),
          mode: _mode,
          byName: app.profile?.name ?? widget.m.name,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = widget.income ? p.success : p.danger;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.income ? tr('add_income') : tr('add_expense'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: _amt,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c),
            decoration: const InputDecoration(prefixText: '₹ ', hintText: '0'),
          ),
          const SizedBox(height: 12),
          FieldLabel(tr('category')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in widget.income ? incomeCats : expenseCats.where((k) => k != 'salary'))
              ChoiceChip(
                avatar: Icon(catIcon(k), size: 17, color: _cat == k ? c : p.muted),
                label: Text(tr('cat_$k')),
                selected: _cat == k,
                selectedColor: c.withValues(alpha: .14),
                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: _cat == k ? c : p.ink),
                side: BorderSide(color: _cat == k ? c : p.border),
                showCheckmark: false,
                onSelected: (_) => setState(() => _cat = k),
              ),
          ]),
          const SizedBox(height: 12),
          FieldLabel(tr('note_optional')),
          TextField(controller: _note, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: widget.income ? tr('income_note_hint') : tr('expense_note_hint'))),
          const SizedBox(height: 12),
          Row(children: [
            for (final mode in ['Cash', 'UPI', 'Bank'])
              Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: ChoicePill(label: mode, selected: _mode == mode, onTap: () => setState(() => _mode = mode)))),
          ]),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(12),
            onTap: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDate: _date.isAfter(DateTime.now()) ? DateTime.now() : _date);
              if (d != null) setState(() => _date = d);
            },
            child: Row(children: [
              Icon(Icons.event_rounded, color: p.brand),
              const SizedBox(width: 10),
              Expanded(child: Text(prettyDate(_date), style: const TextStyle(fontWeight: FontWeight.w700))),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ]),
          ),
          const SizedBox(height: 18),
          PrimaryButton(label: tr('save'), arrow: false, busy: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}

TableReport ledgerReport(String inst, String month, List<Txn> txns, int feeIncome) {
  final income = feeIncome + txns.where((t) => t.isIncome).fold<int>(0, (a, t) => a + t.amount);
  final spent = txns.where((t) => !t.isIncome).fold<int>(0, (a, t) => a + t.amount);
  final sorted = [...txns]..sort((a, b) => a.date.compareTo(b.date));
  return TableReport(
    title: 'Income & Expenses — ${monthLabel(month)}',
    institute: inst,
    summary: [('Income', rupees(income)), ('Expenses', rupees(spent)), (income >= spent ? 'Profit' : 'Loss', rupees((income - spent).abs()))],
    headers: ['Date', 'Type', 'Category', 'Details', 'Mode', 'Amount (₹)'],
    numeric: {5},
    rows: [
      ['—', 'Income', 'Fees', 'Monthly fees collected', '', '$feeIncome'],
      for (final t in sorted)
        [
          prettyDate(DateTime.fromMillisecondsSinceEpoch(t.date)),
          t.isIncome ? 'Income' : 'Expense',
          tr('cat_${t.category}'),
          [t.refName, t.note].where((x) => x.isNotEmpty).join(' — '),
          t.mode,
          '${t.isIncome ? '' : '-'}${t.amount}',
        ],
    ],
  );
}

/// Download or share a report as PDF or Excel.
Future<void> showReportShare(BuildContext context, TableReport r) =>
    showFileSheet(context, title: r.title, subtitle: r.institute, files: [pdfOption(r), excelOption(r)]);

// ---------------------------------------------------------------------------
// Teacher payroll
// ---------------------------------------------------------------------------

class _PayRow {
  _PayRow(this.t, this.classes, this.days, this.paid);
  final Membership t;
  final int classes, days;
  final Txn? paid;
  int get due => t.payType == 'class' ? t.salary * classes : t.salary;
}

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key, required this.m});
  final Membership m;
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _v = 0;

  Future<List<_PayRow>> _load() async {
    final b = context.appRead.backend;
    final id = widget.m.instituteId;
    final mk = monthKey(_month);
    final members = await b.members(id);
    final batches = await b.batches(id);
    final ledger = await b.ledger(id, mk);
    final checks = await b.checkIns(id, mk);
    final teachers = members.where((x) => x.role == Role.teacher && x.approved).toList()..sort((a, c) => a.name.compareTo(c.name));
    final out = <_PayRow>[];
    for (final t in teachers) {
      var classes = 0;
      for (final bt in batches.where((x) => x.teacherUid == t.uid)) {
        classes += (await b.attendanceForBatch(id, bt.id)).where((a) => a.dateKey.startsWith(mk.replaceAll('-', ''))).length;
      }
      final days = checks.where((c) => c.uid == t.uid).length;
      out.add(_PayRow(t, classes, days, ledger.where((x) => x.id == 'pay_${t.uid}_$mk').firstOrNull));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('payroll'),
      subtitle: widget.m.instituteName,
      actions: [IconBtn(icon: Icons.how_to_reg_outlined, tooltip: tr('teacher_checkins'), onTap: () => push(context, CheckInsScreen(m: widget.m)))],
      body: Column(children: [
        MonthBar(
          month: _month,
          onShift: (d) => setState(() {
            _month = DateTime(_month.year, _month.month + d);
            _v++;
          }),
        ),
        Expanded(
          child: Loader<List<_PayRow>>(
            key: ValueKey(_v),
            load: _load,
            builder: (context, rows, reload) {
              final total = rows.fold<int>(0, (a, r) => a + (r.paid?.amount ?? r.due));
              final paid = rows.where((r) => r.paid != null).fold<int>(0, (a, r) => a + r.paid!.amount);
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
                children: [
                  FadeIn(
                    child: AppCard(
                      child: Row(children: [
                        Ring(
                          value: total == 0 ? 0 : paid / total,
                          size: 70,
                          stroke: 8,
                          color: p.success,
                          track: p.successTint,
                          center: Icon(Icons.payments_outlined, color: p.success),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tr('salary_this_month'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 12.5)),
                            Text(rupees(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                            Text('${tr('paid')} ${rupees(paid)} · ${tr('pending')} ${rupees(total - paid)}', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (rows.isEmpty) EmptyState(icon: Icons.badge_outlined, text: tr('no_teachers')),
                  for (var i = 0; i < rows.length; i++)
                    FadeIn(
                      delay: stagger(i + 1),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Builder(builder: (context) {
                          final r = rows[i];
                          final setUp = r.t.salary > 0;
                          return AppCard(
                            onTap: () async {
                              final ok = await showModalBottomSheet<bool>(
                                context: context,
                                isScrollControlled: true,
                                showDragHandle: true,
                                builder: (_) => _PaySheet(m: widget.m, r: r, month: monthKey(_month)),
                              );
                              if (ok == true) setState(() => _v++);
                            },
                            child: Row(children: [
                              Avatar(r.t.name, size: 46, photo: r.t.photo, index: i),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(r.t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                  Text(
                                    !setUp
                                        ? tr('set_salary')
                                        : (r.t.payType == 'class' ? '${rupees(r.t.salary)} × ${r.classes} ${tr('classes')}' : '${tr('fixed')} ${rupees(r.t.salary)}'),
                                    style: TextStyle(color: setUp ? p.muted : p.brand, fontSize: 12.5, fontWeight: FontWeight.w600),
                                  ),
                                  Text('${r.classes} ${tr('classes')} · ${r.days} ${tr('checkin_days')}', style: TextStyle(color: p.muted, fontSize: 12)),
                                ]),
                              ),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(rupees(r.paid?.amount ?? r.due), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(height: 4),
                                r.paid != null ? Tag(tr('paid'), fg: p.success, bg: p.successTint) : Tag(tr('to_pay'), fg: p.warn, bg: p.warnTint),
                              ]),
                            ]),
                          );
                        }),
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
}

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.m, required this.r, required this.month});
  final Membership m;
  final _PayRow r;
  final String month;
  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late final _salary = TextEditingController(text: widget.r.t.salary == 0 ? '' : '${widget.r.t.salary}');
  late final _amt = TextEditingController(text: '${widget.r.paid?.amount ?? widget.r.due}');
  late final _note = TextEditingController(text: widget.r.paid?.note ?? '');
  late String _type = widget.r.t.payType;
  late final _upi = TextEditingController(text: widget.r.t.upiId);
  String _mode = 'Bank';
  int _app = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amt.addListener(() => setState(() {}));
  }

  Future<void> _savePaid(int amt, String mode, String note) {
    final app = context.appRead;
    final r = widget.r;
    Future<void> notify() => Push.send(
          inst: widget.m.instituteId,
          kind: 'salary',
          title: '💸 ${tr('push_salary_paid')}',
          body: '${rupees(amt)} · ${monthLabel(widget.month)} · $mode',
          topics: [Push.person(widget.m.instituteId, r.t.uid)],
        );
    return _run(() async {
      await app.backend.saveTxn(
          widget.m.instituteId,
          Txn(
            id: 'pay_${r.t.uid}_${widget.month}',
            isIncome: false,
            category: 'salary',
            amount: amt,
            date: monthKey(DateTime.now()) == widget.month
                ? DateTime.now().millisecondsSinceEpoch
                : DateTime(int.parse(widget.month.substring(0, 4)), int.parse(widget.month.substring(5)) + 1, 0, 12).millisecondsSinceEpoch,
            note: note,
            mode: mode,
            refUid: r.t.uid,
            refName: r.t.name,
            byName: app.profile?.name ?? widget.m.name,
          ),
        );
      await notify();
    });
  }

  /// Opens GPay / PhonePe / Paytm with the teacher's UPI ID; marks paid with the UTR.
  Future<void> _payUpi() async {
    final app = context.appRead;
    final r = widget.r;
    final vpa = _upi.text.trim();
    final amt = int.tryParse(_amt.text.trim()) ?? 0;
    if (!RegExp(r'^[\w.\-]{2,}@[A-Za-z]{2,}$').hasMatch(vpa)) {
      toast(context, tr('err_upi'));
      return;
    }
    if (amt <= 0) {
      toast(context, tr('err_amount'));
      return;
    }
    final upiApp = upiApps[_app];
    setState(() => _busy = true);
    try {
      if (vpa != r.t.upiId) await app.backend.setUpi(r.t, vpa);
      UpiResult res;
      if (app.isDemo) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        res = UpiResult(UpiStatus.success, utr: '${DateTime.now().millisecondsSinceEpoch}'.substring(1, 13));
      } else {
        res = await payByUpi(
          vpa: vpa,
          payee: r.t.name,
          amount: amt,
          note: 'Salary ${monthLabel(widget.month)}',
          ref: 'VDS${DateTime.now().millisecondsSinceEpoch}',
          package: upiApp.package,
          activity: upiApp.activity,
        );
      }
      if (!mounted) return;
      setState(() => _busy = false);
      switch (res.status) {
        case UpiStatus.noApp:
          toast(context, trf('upi_no_app', {'app': upiApp.name}));
          return;
        case UpiStatus.failed:
          toast(context, tr('upi_failed'));
          return;
        case UpiStatus.success:
        case UpiStatus.unknown:
          var utr = res.utr;
          if (utr.isEmpty || res.status == UpiStatus.unknown) {
            final typed = await askUtr(context, utr);
            if (typed == null) return;
            utr = typed;
          }
          final note = _note.text.trim();
          await _savePaid(amt, 'UPI · ${upiApp.name.split(' ').first}', ['UTR ${cleanUtr(utr)}', if (note.isNotEmpty) note].join(' · '));
      }
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_salary, _amt, _note, _upi]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
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
    final paid = r.paid;
    final rate = int.tryParse(_salary.text.trim()) ?? 0;
    final calc = _type == 'class' ? rate * r.classes : rate;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(r.t.name, size: 46, photo: r.t.photo),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.t.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                Text('${monthLabel(widget.month)} · ${r.classes} ${tr('classes')} · ${r.days} ${tr('checkin_days')}', style: TextStyle(color: p.muted, fontSize: 12.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          FieldLabel(tr('pay_type')),
          Row(children: [
            Expanded(child: ChoicePill(label: tr('fixed_monthly'), selected: _type == 'fixed', onTap: () => setState(() => _type = 'fixed'))),
            const SizedBox(width: 8),
            Expanded(child: ChoicePill(label: tr('per_class'), selected: _type == 'class', onTap: () => setState(() => _type = 'class'))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _salary,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(prefixText: '₹ ', suffixText: _type == 'class' ? '/ ${tr('class_word')}' : '/ ${tr('month_short')}'),
              ),
            ),
            const SizedBox(width: 8),
            SoftButton(
              label: tr('save'),
              height: 56,
              onPressed: _busy ? null : () => _run(() => context.appRead.backend.setPay(r.t, salary: rate, payType: _type)),
            ),
          ]),
          if (_type == 'class') Padding(padding: const EdgeInsets.only(top: 6), child: Text(trf('per_class_calc', {'n': '${r.classes}', 'amt': rupees(calc)}), style: TextStyle(color: p.brand, fontWeight: FontWeight.w700, fontSize: 12.5))),
          const SizedBox(height: 14),
          Divider(color: p.border),
          const SizedBox(height: 6),
          if (paid != null) ...[
            AppCard(
              color: p.successTint,
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: p.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${tr('paid')} ${rupees(paid.amount)} · ${paid.mode} · ${prettyDate(DateTime.fromMillisecondsSinceEpoch(paid.date))}',
                      style: TextStyle(color: p.success, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            SoftButton(label: tr('payslip_pdf'), icon: Icons.picture_as_pdf_outlined, onPressed: () => sharePayslip(context, widget.m.instituteName, r.t, paid, r.classes, r.days)),
            TextButton(
              onPressed: _busy ? null : () => _run(() => context.appRead.backend.deleteTxn(widget.m.instituteId, paid.id)),
              child: Text(tr('mark_unpaid'), style: TextStyle(color: p.danger)),
            ),
          ] else ...[
            FieldLabel(tr('teacher_upi')),
            TextField(
              controller: _upi,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(hintText: 'name@okaxis', prefixIcon: const Icon(Icons.account_balance_wallet_outlined), helperText: r.t.upiId.isEmpty ? tr('teacher_upi_help') : null),
            ),
            const SizedBox(height: 12),
            FieldLabel(tr('amount_to_pay')),
            TextField(
              controller: _amt,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(prefixText: '₹ '),
            ),
            const SizedBox(height: 10),
            TextField(controller: _note, decoration: InputDecoration(hintText: tr('salary_note_hint'))),
            const SizedBox(height: 12),
            FieldLabel(tr('pay_with')),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
              for (var i = 0; i < upiApps.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: GestureDetector(
                    onTap: () => setState(() => _app = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _app == i ? p.brandTint : p.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _app == i ? p.brand : p.border, width: _app == i ? 2 : 1),
                      ),
                      child: Column(children: [
                        UpiIcon(upiApps[i], size: 34),
                        const SizedBox(height: 5),
                        Text(upiApps[i].name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
                      ]),
                    ),
                  ),
                ),
              ],
            ]),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: trf('pay_amount_with', {'amt': rupees(int.tryParse(_amt.text.trim()) ?? 0), 'app': upiApps[_app].name.split(' ').first}),
              icon: Icons.bolt_rounded,
              arrow: false,
              busy: _busy,
              onPressed: _payUpi,
            ),
            const SizedBox(height: 6),
            Text(tr('salary_upi_note'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Divider(color: p.border),
            Text(tr('paid_other_way'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(children: [
              for (final mode in ['Bank', 'Cash'])
                Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: ChoicePill(label: mode, selected: _mode == mode, onTap: () => setState(() => _mode = mode)))),
              Expanded(
                flex: 2,
                child: SoftButton(
                  label: tr('mark_salary_paid'),
                  icon: Icons.check_rounded,
                  onPressed: _busy
                      ? null
                      : () {
                          final amt = int.tryParse(_amt.text.trim()) ?? 0;
                          if (amt <= 0) {
                            toast(context, tr('err_amount'));
                            return;
                          }
                          _savePaid(amt, _mode, _note.text.trim());
                        },
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

Future<void> sharePayslip(BuildContext context, String inst, Membership t, Txn pay, int classes, int days) async {
  try {
    final r = TableReport(
      title: 'Salary slip — ${monthLabel(pay.month)}',
      subtitle: t.name,
      institute: inst,
      summary: [('Amount paid', rupees(pay.amount)), ('Paid on', prettyDate(DateTime.fromMillisecondsSinceEpoch(pay.date))), ('Mode', pay.mode.isEmpty ? '—' : pay.mode)],
      headers: ['Item', 'Details'],
      rows: [
        ['Teacher', t.name],
        ['Month', monthLabel(pay.month)],
        ['Pay type', t.payType == 'class' ? 'Per class (${rupees(t.salary)} each)' : 'Fixed monthly'],
        ['Classes taken', '$classes'],
        ['Check-in days', '$days'],
        if (pay.note.isNotEmpty) ['Note', pay.note],
        ['Amount', rupees(pay.amount)],
      ],
      footer: 'Generated by VidyaDesk',
    );
    await showFileSheet(context, title: r.title, subtitle: t.name, files: [pdfOption(r)]);
  } catch (e) {
    if (context.mounted) toast(context, errorMessage(e));
  }
}

/// Teacher: own salary entries.
class MySalaryScreen extends StatelessWidget {
  const MySalaryScreen({super.key, required this.m});
  final Membership m;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('my_salary'),
      subtitle: m.instituteName,
      body: Loader<(List<Txn>, List<CheckIn>)>(
        load: () async {
          final b = context.appRead.backend;
          return (await b.payslips(m.instituteId, m.uid), await b.checkIns(m.instituteId, monthKey(DateTime.now()), uid: m.uid));
        },
        builder: (context, d, reload) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
          children: [
            _MyUpiCard(m: m),
            const SizedBox(height: 12),
            AppCard(
              child: Row(children: [
                IconBox(Icons.how_to_reg_rounded, fg: p.success, bg: p.successTint),
                const SizedBox(width: 12),
                Expanded(child: Text(trf('checkins_this_month', {'n': '${d.$2.length}'}), style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ),
            const SizedBox(height: 14),
            SectionTitle(tr('salary_history')),
            const SizedBox(height: 6),
            if (d.$1.isEmpty) EmptyState(icon: Icons.payments_outlined, text: tr('no_salary_yet')),
            for (final t in d.$1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () => sharePayslip(context, m.instituteName, m, t, 0, 0),
                  child: Row(children: [
                    IconBox(Icons.payments_outlined, fg: p.success, bg: p.successTint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(monthLabel(t.month), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${prettyDate(DateTime.fromMillisecondsSinceEpoch(t.date))} · ${t.mode}', style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(rupees(t.amount), style: TextStyle(fontWeight: FontWeight.w800, color: p.success)),
                      Text('PDF ↓', style: TextStyle(color: p.brand, fontWeight: FontWeight.w800, fontSize: 11.5)),
                    ]),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Teacher sets the UPI ID where the salary should come.
class _MyUpiCard extends StatefulWidget {
  const _MyUpiCard({required this.m});
  final Membership m;
  @override
  State<_MyUpiCard> createState() => _MyUpiCardState();
}

class _MyUpiCardState extends State<_MyUpiCard> {
  late final _c = TextEditingController(text: widget.m.upiId);
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _c.text.trim();
    if (v.isNotEmpty && !RegExp(r'^[\w.\-]{2,}@[A-Za-z]{2,}$').hasMatch(v)) {
      toast(context, tr('err_upi'));
      return;
    }
    setState(() => _busy = true);
    try {
      await context.appRead.backend.setUpi(widget.m, v);
      if (mounted) toast(context, tr('saved'));
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconBox(Icons.account_balance_wallet_outlined, fg: p.brand, bg: p.brandTint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('my_upi_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(tr('my_upi_sub'), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _c, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'name@okaxis')),
        const SizedBox(height: 10),
        PrimaryButton(label: tr('save_upi'), arrow: false, busy: _busy, onPressed: _save),
      ]),
    );
  }
}
