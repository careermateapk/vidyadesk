import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/reports.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'insights.dart' show pickReportCard;
import 'money.dart';

/// Admin: download monthly reports as PDF or Excel.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.m});
  final Membership m;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _busy;

  String get _mk => monthKey(_month);
  String get _inst => widget.m.instituteName;

  Future<TableReport> _fees() async {
    final b = context.appRead.backend;
    final id = widget.m.instituteId;
    final members = await b.members(id);
    final batches = {for (final x in await b.batches(id)) x.id: x};
    final fees = {for (final f in await b.feesForMonth(id, _mk)) f.studentUid: f};
    final rows = <List<String>>[];
    var got = 0, due = 0;
    for (final s in approvedStudents(members)) {
      final f = fees[s.uid] ?? FeeRecord(studentUid: s.uid, studentName: s.name, month: _mk, amount: s.monthlyFee);
      got += f.paidSoFar;
      due += f.balance;
      rows.add([
        s.name,
        s.batchIds.map((x) => batches[x]?.title ?? '').where((x) => x.isNotEmpty).join(', '),
        '${f.amount}',
        '${f.paidSoFar}',
        '${f.balance}',
        f.paid ? 'Paid' : (f.partly ? 'Part paid' : (f.waiting ? 'To confirm' : 'Due')),
        f.paid ? '${f.mode} ${prettyDate(DateTime.fromMillisecondsSinceEpoch(f.paidOn))}' : '',
        f.receiptNo,
      ]);
    }
    return TableReport(
      title: 'Fee collection — ${monthLabel(_mk)}',
      institute: _inst,
      summary: [('Collected', rupees(got)), ('Pending', rupees(due)), ('Students', '${rows.length}')],
      headers: ['Student', 'Batch', 'Fee', 'Paid', 'Balance', 'Status', 'Paid on', 'Receipt'],
      numeric: {2, 3, 4},
      rows: rows,
    );
  }

  Future<TableReport> _attendance() async {
    final b = context.appRead.backend;
    final id = widget.m.instituteId;
    final members = await b.members(id);
    final batches = await b.batches(id);
    final prefix = _mk.replaceAll('-', '');
    final rows = <List<String>>[];
    var p = 0, t = 0;
    for (final bt in batches) {
      final days = (await b.attendanceForBatch(id, bt.id)).where((a) => a.dateKey.startsWith(prefix)).toList();
      for (final s in approvedStudents(members, batchId: bt.id)) {
        final c = attendanceCount(s.uid, days);
        p += c.present;
        t += c.total;
        rows.add([s.name, bt.title, '${c.present}', '${c.total - c.present}', '${c.total}', c.total == 0 ? '—' : '${pct(c.present, c.total)}%']);
      }
    }
    return TableReport(
      title: 'Attendance — ${monthLabel(_mk)}',
      institute: _inst,
      summary: [('Average attendance', t == 0 ? '—' : '${pct(p, t)}%'), ('Batches', '${batches.length}')],
      headers: ['Student', 'Batch', 'Present', 'Absent', 'Classes', '%'],
      numeric: {2, 3, 4, 5},
      rows: rows,
    );
  }

  Future<TableReport> _money() async {
    final b = context.appRead.backend;
    final id = widget.m.instituteId;
    final fees = await b.feesForMonth(id, _mk);
    return ledgerReport(_inst, _mk, await b.ledger(id, _mk), fees.fold<int>(0, (a, f) => a + f.paidSoFar));
  }

  Future<TableReport> _results() async {
    final b = context.appRead.backend;
    final id = widget.m.instituteId;
    final members = {for (final x in await b.members(id)) x.uid: x};
    final batches = {for (final x in await b.batches(id)) x.id: x};
    final tests = (await b.tests(id)).where((t) => monthKey(DateTime.fromMillisecondsSinceEpoch(t.date)) == _mk).toList()..sort((a, c) => a.date.compareTo(c.date));
    final rows = <List<String>>[];
    for (final t in tests) {
      final sorted = t.marks.entries.toList()..sort((a, c) => c.value.compareTo(a.value));
      for (final e in sorted) {
        rows.add([
          t.title,
          batches[t.batchId]?.title ?? t.subject,
          members[e.key]?.name ?? '—',
          e.value == e.value.roundToDouble() ? '${e.value.toInt()}' : e.value.toStringAsFixed(1),
          '${t.maxMarks}',
          '${(e.value * 100 / t.maxMarks).round()}%',
          '${t.rankOf(e.key)}',
        ]);
      }
    }
    return TableReport(
      title: 'Test results — ${monthLabel(_mk)}',
      institute: _inst,
      summary: [('Tests', '${tests.length}'), ('Entries', '${rows.length}')],
      headers: ['Test', 'Batch', 'Student', 'Marks', 'Out of', '%', 'Rank'],
      numeric: {3, 4, 5, 6},
      rows: rows,
    );
  }

  Future<TableReport> _students() async {
    final b = context.appRead.backend;
    final id = widget.m.instituteId;
    final members = await b.members(id);
    final batches = {for (final x in await b.batches(id)) x.id: x};
    final parents = members.where((x) => x.role == Role.parent && x.approved).toList();
    final list = approvedStudents(members);
    return TableReport(
      title: 'Students list',
      subtitle: monthLabel(monthKey(DateTime.now())),
      institute: _inst,
      summary: [('Students', '${list.length}'), ('Monthly fees', rupees(list.fold<int>(0, (a, s) => a + s.monthlyFee)))],
      headers: ['Name', 'Phone', 'Batch', 'Parent', 'Parent phone', 'Monthly fee', 'Discount', 'Code'],
      numeric: {5, 6},
      rows: [
        for (final s in list)
          () {
            final par = parents.where((x) => x.childUids.contains(s.uid)).firstOrNull;
            return [
              s.name,
              s.phone,
              s.batchIds.map((x) => batches[x]?.title ?? '').where((x) => x.isNotEmpty).join(', '),
              par?.name ?? '',
              par?.phone ?? '',
              '${s.monthlyFee}',
              s.discount == 0 ? '' : '${s.discount}${s.feeNote.isEmpty ? '' : ' (${s.feeNote})'}',
              s.studentCode,
            ];
          }(),
      ],
    );
  }

  Future<void> _make(String id, Future<TableReport> Function() build, bool pdf) async {
    setState(() => _busy = '$id$pdf');
    try {
      final r = await build();
      if (pdf) {
        await shareReportPdf(r);
      } else {
        await shareReportCsv(r);
      }
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final items = <(String, IconData, Color, Future<TableReport> Function())>[
      ('fees', Icons.account_balance_wallet_outlined, p.success, _fees),
      ('attendance', Icons.fact_check_outlined, p.indigo, _attendance),
      ('money', Icons.savings_outlined, p.warn, _money),
      ('results', Icons.emoji_events_outlined, p.brand, _results),
      ('students', Icons.groups_outlined, p.danger, _students),
    ];
    return AppScaffold(
      title: tr('reports'),
      subtitle: tr('reports_sub'),
      body: Column(children: [
        MonthBar(month: _month, onShift: (d) => setState(() => _month = DateTime(_month.year, _month.month + d))),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
            children: [
              FadeIn(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    onTap: () => pickReportCard(context, widget.m),
                    child: Row(children: [
                      IconBox(Icons.description_outlined, fg: p.indigo, bg: p.indigoTint),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('report_cards'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Text(tr('report_cards_sub'), style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: p.muted),
                    ]),
                  ),
                ),
              ),
              for (var i = 0; i < items.length; i++)
                FadeIn(
                  delay: stagger(i),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          IconBox(items[i].$2, fg: items[i].$3, bg: items[i].$3.withValues(alpha: .12)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(tr('rep_${items[i].$1}'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              Text(tr('rep_${items[i].$1}_sub'), style: TextStyle(color: p.muted, fontSize: 12.5)),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: _btn(p, 'PDF', Icons.picture_as_pdf_outlined, p.danger, _busy == '${items[i].$1}true', () => _make(items[i].$1, items[i].$4, true)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _btn(p, 'Excel', Icons.grid_on_rounded, p.success, _busy == '${items[i].$1}false', () => _make(items[i].$1, items[i].$4, false)),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _btn(Palette p, String label, IconData icon, Color c, bool busy, VoidCallback onTap) => GestureDetector(
        onTap: _busy == null ? onTap : null,
        child: Container(
          height: 44,
          decoration: BoxDecoration(color: c.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy) SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c)) else Icon(icon, size: 18, color: c),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
          ]),
        ),
      );
}
