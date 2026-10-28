import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../services/reports.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'fees.dart' show feeDueDate;
import 'resources.dart' show learnerUid, learnerName;
import 'tests.dart' show fmtMarks;

const _day = 86400000;

// ---------------------------------------------------------------------------
// Risk alert: students who need attention
// ---------------------------------------------------------------------------

class RiskItem {
  RiskItem(this.s, this.reasons, this.parentPhone);
  final Membership s;
  final List<String> reasons;
  final String parentPhone;
  bool get high => reasons.length >= 2;
}

Future<List<RiskItem>> computeRisk(Backend b, Membership me) async {
  final id = me.instituteId;
  final now = DateTime.now();
  final since = now.millisecondsSinceEpoch - 30 * _day;
  final members = await b.members(id);
  final batches = myBatches(me, await b.batches(id));
  final ids = batches.map((x) => x.id).toSet();
  final students = approvedStudents(members).where((s) => me.role == Role.admin || s.batchIds.any(ids.contains)).toList();
  final parents = members.where((x) => x.role == Role.parent && x.approved).toList();
  final att = <AttendanceDay>[];
  for (final bt in batches) {
    att.addAll((await b.attendanceForBatch(id, bt.id)).where((a) => dateFromKey(a.dateKey).millisecondsSinceEpoch >= since));
  }
  final inst = await b.institute(id);
  final cur = monthKey(now), last = monthKey(DateTime(now.year, now.month - 1));
  final feesCur = {for (final f in await b.feesForMonth(id, cur)) f.studentUid: f};
  final feesLast = {for (final f in await b.feesForMonth(id, last)) f.studentUid: f};
  final tests = (await b.tests(id)).where((t) => ids.contains(t.batchId)).toList()..sort((a, c) => a.date.compareTo(c.date));
  final overdue = now.isAfter(feeDueDate(cur, inst).add(const Duration(days: 1)));
  final out = <RiskItem>[];
  for (final s in students) {
    final r = <String>[];
    final c = attendanceCount(s.uid, att);
    if (c.total >= 4 && pct(c.present, c.total) < 75) r.add(trf('risk_att', {'n': '${pct(c.present, c.total)}'}));
    final fl = feesLast[s.uid];
    if (s.monthlyFee > 0 && (fl == null || !fl.paid) && s.createdAt < DateTime(now.year, now.month - 1).millisecondsSinceEpoch) {
      r.add(trf('risk_fee_last', {'m': monthLabel(last)}));
    } else if (overdue && s.monthlyFee > 0 && feesCur[s.uid]?.paid != true) {
      r.add(trf('risk_fee_now', {'m': monthLabel(cur)}));
    }
    final mine = tests.where((t) => t.marks.containsKey(s.uid)).toList();
    if (mine.isNotEmpty) {
      final pcts = [for (final t in mine) (t.marks[s.uid]! * 100 / t.maxMarks).round()];
      final recent = pcts.length >= 2 ? (pcts[pcts.length - 1] + pcts[pcts.length - 2]) ~/ 2 : pcts.last;
      if (recent < 40) {
        r.add(trf('risk_marks', {'n': '$recent'}));
      } else if (pcts.length >= 2 && pcts[pcts.length - 2] - pcts.last >= 15) {
        r.add(trf('risk_drop', {'n': '${pcts[pcts.length - 2] - pcts.last}'}));
      }
    }
    if (r.isNotEmpty) {
      final par = parents.where((x) => x.childUids.contains(s.uid)).firstOrNull;
      out.add(RiskItem(s, r, par?.phone ?? ''));
    }
  }
  out.sort((a, c) => c.reasons.length.compareTo(a.reasons.length));
  return out;
}

/// Small card on the staff home (loads by itself).
class RiskCard extends StatefulWidget {
  const RiskCard({super.key, required this.m});
  final Membership m;
  @override
  State<RiskCard> createState() => _RiskCardState();
}

class _RiskCardState extends State<RiskCard> {
  Future<List<RiskItem>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= computeRisk(context.appRead.backend, widget.m);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return FutureBuilder<List<RiskItem>>(
      future: _f,
      builder: (context, snap) {
        final list = snap.data ?? const <RiskItem>[];
        if (list.isEmpty) return const SizedBox.shrink();
        final high = list.where((x) => x.high).length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () async {
              await push(context, RiskScreen(m: widget.m));
              if (!mounted) return;
              setState(() => _f = computeRisk(context.appRead.backend, widget.m));
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.dangerTint, borderRadius: BorderRadius.circular(Gap.rCard)),
              child: Row(children: [
                IconBox(Icons.warning_amber_rounded, fg: Colors.white, bg: p.danger),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(trf('n_at_risk', {'n': '${list.length}'}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    Text(high > 0 ? trf('n_high_risk', {'n': '$high'}) : list.take(3).map((x) => firstName(x.s.name)).join(', '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: p.danger),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class RiskScreen extends StatelessWidget {
  const RiskScreen({super.key, required this.m});
  final Membership m;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('risk_alert'),
      subtitle: tr('risk_alert_sub'),
      body: Loader<List<RiskItem>>(
        load: () => computeRisk(context.appRead.backend, m),
        builder: (context, list, reload) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
          children: [
            if (list.isEmpty) EmptyState(icon: Icons.verified_rounded, text: tr('no_risk')),
            for (var i = 0; i < list.length; i++)
              FadeIn(
                delay: stagger(i, stepMs: 40),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Avatar(list[i].s.name, size: 42, photo: list[i].s.photo, index: i),
                        const SizedBox(width: 10),
                        Expanded(child: Text(list[i].s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                        Tag(list[i].high ? tr('high') : tr('watch'), fg: list[i].high ? p.danger : p.warn, bg: list[i].high ? p.dangerTint : p.warnTint),
                      ]),
                      const SizedBox(height: 10),
                      for (final r in list[i].reasons)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            Icon(Icons.circle, size: 7, color: p.danger),
                            const SizedBox(width: 8),
                            Expanded(child: Text(r, style: TextStyle(color: p.ink2, fontWeight: FontWeight.w600, fontSize: 13))),
                          ]),
                        ),
                      const SizedBox(height: 8),
                      Row(children: [
                        if (list[i].parentPhone.isNotEmpty) ...[
                          Expanded(
                            child: SoftButton(
                              label: tr('tell_parent'),
                              icon: Icons.chat_rounded,
                              color: p.successTint,
                              textColor: p.success,
                              height: 42,
                              onPressed: () => openWhatsApp(
                                context,
                                list[i].parentPhone,
                                trf('risk_msg', {'name': list[i].s.name, 'points': list[i].reasons.map((x) => '• $x').join('\n'), 'inst': m.instituteName}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: SoftButton(
                            label: tr('report_card'),
                            icon: Icons.description_outlined,
                            height: 42,
                            onPressed: () => shareReportCard(context, m, list[i].s.uid, list[i].s.name),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report card (PDF)
// ---------------------------------------------------------------------------

Future<void> shareReportCard(BuildContext context, Membership m, String uid, String name, {String remark = ''}) async {
  toast(context, tr('making_pdf'));
  try {
    final b = context.appRead.backend;
    final id = m.instituteId;
    final batches = {for (final x in await b.batches(id)) x.id: x};
    final att = await b.attendanceForStudent(id, uid);
    final tests = (await b.tests(id, publishedOnly: !m.isStaff)).where((t) => t.marks.containsKey(uid)).toList()..sort((a, c) => a.date.compareTo(c.date));
    final c = attendanceCount(uid, att);
    final pcts = [for (final t in tests) t.marks[uid]! * 100 / t.maxMarks];
    final avg = pcts.isEmpty ? null : (pcts.reduce((a, x) => a + x) / pcts.length).round();
    final byBatch = <String, List<AttendanceDay>>{};
    for (final a in att) {
      (byBatch[a.batchId] ??= []).add(a);
    }
    final grade = avg == null ? '—' : (avg >= 90 ? 'A+' : avg >= 75 ? 'A' : avg >= 60 ? 'B' : avg >= 45 ? 'C' : 'D');
    await shareReportPdf(TableReport(
      title: 'Report card',
      subtitle: '$name · ${prettyDate(DateTime.now())}',
      institute: m.instituteName,
      summary: [
        ('Attendance', c.total == 0 ? '—' : '${pct(c.present, c.total)}%'),
        ('Average marks', avg == null ? '—' : '$avg%'),
        ('Grade', grade),
        ('Tests', '${tests.length}'),
      ],
      headers: ['Test', 'Subject', 'Date', 'Marks', 'Out of', '%', 'Rank', 'Class avg'],
      numeric: {3, 4, 5, 6, 7},
      rows: [
        for (final t in tests)
          [
            t.title,
            batches[t.batchId]?.subject ?? t.subject,
            prettyDate(DateTime.fromMillisecondsSinceEpoch(t.date)),
            fmtMarks(t.marks[uid]!),
            '${t.maxMarks}',
            '${(t.marks[uid]! * 100 / t.maxMarks).round()}%',
            '${t.rankOf(uid)} / ${t.marks.length}',
            t.average == null ? '—' : fmtMarks(t.average!),
          ],
      ],
      extra: [
        (
          'Attendance by batch',
          ['Batch', 'Present', 'Absent', 'Classes', '%'],
          [
            for (final e in byBatch.entries)
              () {
                final x = attendanceCount(uid, e.value);
                return [batches[e.key]?.title ?? '—', '${x.present}', '${x.total - x.present}', '${x.total}', x.total == 0 ? '—' : '${pct(x.present, x.total)}%'];
              }(),
          ],
        ),
        if (remark.isNotEmpty) ('Teacher\'s remark', ['Remark'], [[remark]]),
      ],
      footer: 'Report card generated by VidyaDesk',
    ));
  } catch (e) {
    if (context.mounted) toast(context, errorMessage(e));
  }
}

/// Staff: pick a student, add a remark, get the report card.
Future<void> pickReportCard(BuildContext context, Membership m) async {
  final b = context.appRead.backend;
  final members = await b.members(m.instituteId);
  final batches = myBatches(m, await b.batches(m.instituteId)).map((x) => x.id).toSet();
  final students = approvedStudents(members).where((s) => m.role == Role.admin || s.batchIds.any(batches.contains)).toList();
  if (!context.mounted) return;
  final remark = TextEditingController();
  final s = await showModalBottomSheet<Membership>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SizedBox(
      height: MediaQuery.of(c).size.height * .75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('report_card'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(controller: remark, decoration: InputDecoration(hintText: tr('remark_optional'), prefixIcon: const Icon(Icons.rate_review_outlined))),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
            for (final x in students)
              ListTile(
                leading: Avatar(x.name, size: 38, photo: x.photo),
                title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.picture_as_pdf_outlined),
                onTap: () => Navigator.pop(c, x),
              ),
          ]),
        ),
      ]),
    ),
  );
  final text = remark.text.trim();
  remark.dispose();
  if (s != null && context.mounted) await shareReportCard(context, m, s.uid, s.name, remark: text);
}

// ---------------------------------------------------------------------------
// Leaderboard & badges
// ---------------------------------------------------------------------------

class AwardBadge {
  const AwardBadge(this.id, this.icon, this.color, this.earned);
  final String id;
  final IconData icon;
  final Color color;
  final bool earned;
}

class _Board {
  _Board(this.batches, this.rows, this.badges);
  final List<Batch> batches;
  final Map<String, List<(String, String, int, int, int)>> rows; // batch -> (uid, name, score, test%, att%)
  final List<AwardBadge> badges;
}

Future<_Board> _loadBoard(BuildContext context, Membership m, String uid) async {
  final b = context.appRead.backend;
  final p = context.pal;
  final id = m.instituteId;
  final all = await b.batches(id);
  final tests = await b.tests(id, publishedOnly: !m.isStaff);
  final att = await b.attendanceForStudent(id, uid);
  final myBatchIds = m.isStaff ? myBatches(m, all).map((x) => x.id).toSet() : {...att.map((a) => a.batchId), ...m.batchIds};
  final batches = all.where((x) => myBatchIds.contains(x.id)).toList();
  final since = DateTime.now().millisecondsSinceEpoch - 30 * _day;
  final rows = <String, List<(String, String, int, int, int)>>{};
  for (final bt in batches) {
    final days = (await b.attendanceForBatch(id, bt.id)).where((a) => dateFromKey(a.dateKey).millisecondsSinceEpoch >= since).toList();
    final ts = tests.where((t) => t.batchId == bt.id).toList();
    final names = <String, String>{};
    for (final t in ts) {
      names.addAll(t.names);
      for (final u in t.marks.keys) {
        names.putIfAbsent(u, () => '');
      }
    }
    final list = <(String, String, int, int, int)>[];
    for (final e in names.entries) {
      final mine = ts.where((t) => t.marks.containsKey(e.key)).toList();
      final tp = mine.isEmpty ? 0 : (mine.map((t) => t.marks[e.key]! * 100 / t.maxMarks).reduce((a, x) => a + x) / mine.length).round();
      final c = attendanceCount(e.key, days);
      final ap = c.total == 0 ? tp : pct(c.present, c.total);
      list.add((e.key, e.value.isEmpty ? tr('student') : e.value, (tp * .6 + ap * .4).round(), tp, ap));
    }
    list.sort((a, c) => c.$3.compareTo(a.$3));
    rows[bt.id] = list;
  }
  // my badges
  final c = attendanceCount(uid, att.where((a) => dateFromKey(a.dateKey).millisecondsSinceEpoch >= since).toList());
  final mine = tests.where((t) => t.marks.containsKey(uid)).toList()..sort((a, x) => a.date.compareTo(x.date));
  final pcts = [for (final t in mine) (t.marks[uid]! * 100 / t.maxMarks).round()];
  final avg = pcts.isEmpty ? 0 : pcts.reduce((a, x) => a + x) ~/ pcts.length;
  var doubts = 0;
  if (!m.isStaff) {
    try {
      doubts = (await b.doubts(id, studentUid: uid)).length;
    } catch (_) {}
  }
  final badges = [
    AwardBadge('perfect', Icons.verified_rounded, p.success, c.total >= 4 && c.present == c.total),
    AwardBadge('regular', Icons.event_available_rounded, p.indigo, c.total >= 4 && pct(c.present, c.total) >= 90),
    AwardBadge('topper', Icons.emoji_events_rounded, const Color(0xFFF59F00), mine.any((t) => t.rankOf(uid) == 1)),
    AwardBadge('scholar', Icons.school_rounded, p.brand, pcts.isNotEmpty && avg >= 80),
    AwardBadge('rising', Icons.trending_up_rounded, p.danger, pcts.length >= 2 && pcts.last - pcts[pcts.length - 2] >= 10),
    AwardBadge('curious', Icons.lightbulb_rounded, const Color(0xFF0EA5B7), doubts >= 3),
  ];
  return _Board(batches, rows, badges);
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, required this.m});
  final Membership m;
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  int _b = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = widget.m;
    final uid = learnerUid(context, m);
    final name = learnerName(context, m);
    return AppScaffold(
      title: tr('leaderboard'),
      subtitle: m.isStaff ? m.instituteName : (m.role == Role.parent ? firstName(name) : tr('leaderboard_sub')),
      body: Loader<_Board>(
        load: () => _loadBoard(context, m, uid),
        builder: (context, d, reload) {
          final bi = _b.clamp(0, d.batches.isEmpty ? 0 : d.batches.length - 1);
          final rows = d.batches.isEmpty ? <(String, String, int, int, int)>[] : d.rows[d.batches[bi].id] ?? [];
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
            children: [
              if (!m.isStaff) ...[
                SectionTitle(trf('badges_n', {'n': '${d.badges.where((x) => x.earned).length}', 'm': '${d.badges.length}'})),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: .82,
                  children: [for (final x in d.badges) BadgeTile(x)],
                ),
                const SizedBox(height: 18),
              ],
              if (d.batches.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    height: 44,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (var i = 0; i < d.batches.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        FilterPill(label: d.batches[i].title, selected: bi == i, onTap: () => setState(() => _b = i)),
                      ],
                    ]),
                  ),
                ),
              SectionTitle(tr('top_students')),
              Text(tr('score_formula'), style: TextStyle(color: p.muted, fontSize: 12)),
              const SizedBox(height: 8),
              if (rows.isEmpty) EmptyState(icon: Icons.leaderboard_rounded, text: tr('no_leaderboard')),
              for (var i = 0; i < rows.length; i++)
                FadeIn(
                  delay: stagger(i, stepMs: 40),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      color: rows[i].$1 == uid && !m.isStaff ? p.brandTint : null,
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        SizedBox(
                          width: 34,
                          child: i < 3
                              ? Text(['🥇', '🥈', '🥉'][i], style: const TextStyle(fontSize: 24))
                              : Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: p.muted, fontSize: 16)),
                        ),
                        const SizedBox(width: 6),
                        Avatar(rows[i].$2, size: 38, index: i),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(rows[i].$1 == uid && !m.isStaff ? '${rows[i].$2} (${tr('you')})' : rows[i].$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('${tr('marks')} ${rows[i].$4}% · ${tr('attendance')} ${rows[i].$5}%', style: TextStyle(color: p.muted, fontSize: 12)),
                          ]),
                        ),
                        Text('${rows[i].$3}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: p.brand)),
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
}

class BadgeTile extends StatelessWidget {
  const BadgeTile(this.b, {super.key, this.small = false});
  final AwardBadge b;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = b.earned ? b.color : p.muted;
    return AppCard(
      padding: EdgeInsets.all(small ? 8 : 10),
      radius: 18,
      color: b.earned ? null : p.cardAlt,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: small ? 40 : 50,
          height: small ? 40 : 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.withValues(alpha: b.earned ? .14 : .08),
            border: Border.all(color: c.withValues(alpha: b.earned ? .5 : .2), width: 2),
          ),
          child: Icon(b.earned ? b.icon : Icons.lock_outline_rounded, color: c, size: small ? 20 : 24),
        ),
        const SizedBox(height: 6),
        Text(tr('badge_${b.id}'), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: small ? 10.5 : 11.5, color: b.earned ? p.ink : p.muted)),
        if (!small)
          Text(tr('badge_${b.id}_sub'), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 10, height: 1.2)),
      ]),
    );
  }
}

/// Learner home: earned badges + link to the leaderboard.
class BadgesCard extends StatefulWidget {
  const BadgesCard({super.key, required this.m});
  final Membership m;
  @override
  State<BadgesCard> createState() => _BadgesCardState();
}

class _BadgesCardState extends State<BadgesCard> {
  Future<_Board>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _loadBoard(context, widget.m, learnerUid(context, widget.m));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = widget.m;
    final uid = learnerUid(context, m);
    return FutureBuilder<_Board>(
      future: _f,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return const SizedBox.shrink();
        final earned = d.badges.where((x) => x.earned).toList();
        var rank = 0, of = 0;
        for (final rows in d.rows.values) {
          final i = rows.indexWhere((r) => r.$1 == uid);
          if (i >= 0 && (rank == 0 || i + 1 < rank)) {
            rank = i + 1;
            of = rows.length;
          }
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            onTap: () => push(context, LeaderboardScreen(m: m)),
            child: Row(children: [
              IconBox(Icons.leaderboard_rounded, fg: const Color(0xFFF59F00), bg: const Color(0xFFF59F00).withValues(alpha: .13)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rank > 0 ? trf('rank_in_batch', {'r': '$rank', 'n': '$of'}) : tr('leaderboard'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text(earned.isEmpty ? tr('earn_badges') : trf('badges_n', {'n': '${earned.length}', 'm': '${d.badges.length}'}), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
              for (final x in earned.take(3))
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: x.color.withValues(alpha: .14)),
                    child: Icon(x.icon, size: 17, color: x.color),
                  ),
                ),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ]),
          ),
        );
      },
    );
  }
}
