import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'attendance.dart';
import 'common.dart';
import 'home_shell.dart';
import 'notices.dart';
import 'onboarding.dart';
import 'people.dart';
import 'schedule.dart';

class _StaffData {
  _StaffData(this.members, this.batches, this.today, this.fees, this.lastFees, this.notices, this.week);
  final List<Membership> members;
  final List<Batch> batches;
  final Map<String, AttendanceDay?> today;
  final List<FeeRecord> fees, lastFees;
  final List<Notice> notices;
  final List<int?> week; // attendance % Mon..Sun of this week
}

class StaffHome extends StatefulWidget {
  const StaffHome({super.key, required this.m});
  final Membership m;
  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  bool _onlyMine = false;

  Future<_StaffData> _load() async {
    final b = context.appRead.backend;
    final m = widget.m;
    final id = m.instituteId;
    final members = await b.members(id);
    final batches = await b.batches(id);
    final now = DateTime.now();
    final mine = myBatches(m, batches);
    final today = <String, AttendanceDay?>{};
    for (final x in mine.where((x) => x.runsOn(now))) {
      today[x.id] = await b.attendance(id, x.id, dateKey(now));
    }
    // this week's attendance, from every batch's history
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final present = List.filled(7, 0), marked = List.filled(7, 0);
    for (final x in mine) {
      for (final a in await b.attendanceForBatch(id, x.id)) {
        final d = dateFromKey(a.dateKey);
        final diff = DateTime(d.year, d.month, d.day).difference(monday).inDays;
        if (diff < 0 || diff > 6) continue;
        present[diff] += a.present.length;
        marked[diff] += a.marked.length;
      }
    }
    final week = [for (var i = 0; i < 7; i++) marked[i] == 0 ? null : pct(present[i], marked[i])];
    final admin = m.role == Role.admin;
    final fees = admin ? await b.feesForMonth(id, monthKey(now)) : <FeeRecord>[];
    final lastFees = admin ? await b.feesForMonth(id, monthKey(DateTime(now.year, now.month - 1))) : <FeeRecord>[];
    final notices = await b.notices(id);
    return _StaffData(members, batches, today, fees, lastFees, notices, week);
  }

  @override
  Widget build(BuildContext context) {
    return Loader<_StaffData>(load: _load, builder: (context, d, reload) => _body(context, d, reload));
  }

  Widget _body(BuildContext context, _StaffData d, Future<void> Function() reload) {
    final p = context.pal;
    final app = context.app;
    final m = widget.m;
    final admin = m.role == Role.admin;
    final now = DateTime.now();
    final mine = myBatches(m, d.batches);
    final colorIdx = {for (var i = 0; i < mine.length; i++) mine[i].id: i};
    final mineIds = mine.map((b) => b.id).toSet();
    final students = admin ? approvedStudents(d.members) : approvedStudents(d.members).where((s) => s.batchIds.any(mineIds.contains)).toList();
    final pending = pendingFor(m, d.members, d.batches);
    var todays = mine.where((b) => b.runsOn(now)).toList()..sort((a, b) => a.startMin.compareTo(b.startMin));
    if (_onlyMine) todays = todays.where((b) => b.teacherUid == m.uid).toList();

    var marked = 0, present = 0;
    for (final a in d.today.values) {
      if (a == null) continue;
      marked += a.marked.length;
      present += a.present.length;
    }

    // fees: students without a record this month still owe their monthly fee
    final feeByUid = {for (final f in d.fees) f.studentUid: f};
    var due = 0, got = 0, dueCount = 0;
    for (final s in approvedStudents(d.members)) {
      final f = feeByUid[s.uid];
      final amt = f?.amount ?? s.monthlyFee;
      due += amt;
      if (f?.paid == true) {
        got += amt;
      } else if (amt > 0) {
        dueCount++;
      }
    }
    final lastGot = d.lastFees.where((f) => f.paid).fold<int>(0, (a, f) => a + f.amount);
    final change = lastGot == 0 ? null : ((got - lastGot) * 100 / lastGot).round();
    final freshNotice = d.notices.any((n) => now.millisecondsSinceEpoch - n.createdAt < 86400000);
    final nowMin = now.hour * 60 + now.minute;
    final next = todays.where((b) => b.endMin >= nowMin).firstOrNull;

    var i = 0;
    Widget item(Widget w) => FadeIn(delay: stagger(i++), child: w);
    final shell = HomeShell.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 8, 18, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        item(Row(children: [
          GestureDetector(onTap: () => shell?.goToNamed('profile'), child: Avatar(app.profile?.name ?? m.name, size: 46, photo: app.profile?.photo ?? '')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${greeting()} 👋', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(app.profile?.name ?? m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.3)),
            ]),
          ),
          IconBtn(icon: Icons.calendar_month_outlined, tooltip: tr('week_schedule'), onTap: () => push(context, ScheduleScreen(m: m))),
          const SizedBox(width: 10),
          IconBtn(
            icon: Icons.notifications_none_rounded,
            dot: freshNotice,
            tooltip: tr('nav_notices'),
            onTap: () async {
              await push(context, NoticesPage(m: m, back: true));
              reload();
            },
          ),
        ])),
        const SizedBox(height: 16),
        if (admin)
          item(FeatureCard(
            onTap: () => shell?.goToNamed('fees'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${m.instituteName} · ${trf('fees_of', {'m': tr('m${now.month}')})}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      CountUp(got, prefix: '₹', style: const TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w800, letterSpacing: -1)),
                      Padding(padding: const EdgeInsets.only(bottom: 5, left: 4), child: Text('/ ${rupees(due)}', style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600))),
                    ]),
                  ]),
                ),
                Ring(
                  value: due == 0 ? 0 : got / due,
                  size: 64,
                  stroke: 7,
                  color: Colors.white,
                  track: Colors.white24,
                  center: Text('${pct(got, due)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
                ),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (change != null) GlassChip('${change >= 0 ? '+' : ''}$change% ${tr('vs_last_month')}', icon: change >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded),
                GlassChip(dueCount == 0 ? tr('all_paid_short') : trf('n_due', {'n': '$dueCount'})),
              ]),
            ]),
          ))
        else
          item(FeatureCard(
            onTap: next == null ? null : () => push(context, MarkAttendanceScreen(m: m, batch: next)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(next == null ? tr('no_more_classes') : (nowMin >= next.startMin ? tr('class_on_now') : tr('next_class')).toUpperCase(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .5)),
              const SizedBox(height: 6),
              Text(next?.title ?? m.instituteName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
              if (next != null)
                Text('${timeLabel(next.startMin)} – ${timeLabel(next.endMin)} · ${approvedStudents(d.members, batchId: next.id).length} ${tr('students_short')}',
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [GlassChip(tr('mark_attendance'), icon: Icons.fact_check_outlined, solid: true)]),
            ]),
          )),
        const SizedBox(height: 12),
        item(Row(children: [
          Expanded(child: StatTile(icon: Icons.groups_outlined, value: students.length, label: tr('students'), fg: p.brand, bg: p.brandTint, onTap: () => push(context, Scaffold(appBar: InnerBar(title: tr('people')), body: PeoplePage(m: m, embedded: true))))),
          const SizedBox(width: 10),
          Expanded(child: StatTile(icon: Icons.layers_outlined, value: mine.length, label: tr('batches'), fg: p.indigo, bg: p.indigoTint, onTap: () => shell?.goToNamed('batches'))),
          const SizedBox(width: 10),
          Expanded(child: StatTile(icon: Icons.fact_check_outlined, value: pct(present, marked), suffix: '%', label: tr('today_present'), fg: p.success, bg: p.successTint, empty: marked == 0)),
        ])),
        const SizedBox(height: 12),
        const DemoBanner(),
        if (pending.isNotEmpty)
          item(Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: GestureDetector(
              onTap: () async {
                await push(context, RequestsScreen(m: m));
                reload();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.warnTint, borderRadius: BorderRadius.circular(Gap.rCard)),
                child: Row(children: [
                  SizedBox(
                    width: 32.0 + (pending.take(3).length - 1) * 22,
                    height: 32,
                    child: Stack(children: [
                      for (var k = 0; k < pending.take(3).length; k++)
                        Positioned(left: k * 22.0, child: Container(decoration: BoxDecoration(border: Border.all(color: p.warnTint, width: 2), borderRadius: BorderRadius.circular(12)), child: Avatar(pending[k].name, size: 30, index: k + 2, photo: pending[k].photo))),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(trf('n_requests', {'n': '${pending.length}'}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      Text(pending.take(3).map((x) => x.name).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  Tag(tr('review'), fg: p.warn, bg: p.card),
                ]),
              ),
            ),
          )),
        item(SectionTitle(
          tr('todays_classes'),
          trailing: admin && m.teaches
              ? SizedBox(width: 140, child: Segmented(items: [tr('all'), tr('mine')], index: _onlyMine ? 1 : 0, onChanged: (v) => setState(() => _onlyMine = v == 1)))
              : GestureDetector(
                  onTap: () => push(context, ScheduleScreen(m: m)),
                  child: Text(prettyDay(now), style: TextStyle(color: p.brand, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
        )),
        const SizedBox(height: 8),
        if (todays.isEmpty)
          item(AppCard(child: EmptyState(icon: Icons.free_breakfast_outlined, text: mine.isEmpty ? tr('no_batches_yet') : tr('no_class_today'))))
        else
          for (final b in todays)
            item(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TodayClass(
                b: b,
                color: batchColors(p, colorIdx[b.id] ?? 0).$1,
                mine: b.teacherUid == m.uid,
                count: approvedStudents(d.members, batchId: b.id).length,
                att: d.today[b.id],
                onMark: () async {
                  await push(context, MarkAttendanceScreen(m: m, batch: b));
                  reload();
                },
              ),
            )),
        const SizedBox(height: 6),
        item(SectionTitle(tr('attendance_week'), trailing: Text(tr('this_week'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 12.5)))),
        const SizedBox(height: 8),
        item(AppCard(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
          child: BarChart(values: d.week, labels: [for (var k = 1; k <= 7; k++) dayShort(k).substring(0, 1)], highlight: now.weekday - 1),
        )),
        if (d.notices.isNotEmpty) ...[
          const SizedBox(height: 10),
          item(SectionTitle(tr('latest_notice'), trailing: TextButton(
            onPressed: () async {
              await push(context, NoticesPage(m: m, back: true));
              reload();
            },
            child: Text(tr('see_all')),
          ))),
          item(NoticeCard(n: d.notices.first, instituteName: m.instituteName)),
        ],
      ],
    );
  }
}

class _TodayClass extends StatelessWidget {
  const _TodayClass({required this.b, required this.color, required this.mine, required this.count, required this.att, required this.onMark});
  final Batch b;
  final Color color;
  final bool mine;
  final int count;
  final AttendanceDay? att;
  final VoidCallback onMark;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final live = nowMin >= b.startMin && nowMin <= b.endMin;
    final done = att != null;
    return AppCard(
      onTap: onMark,
      padding: const EdgeInsets.all(12),
      child: IntrinsicHeight(
        child: Row(children: [
          Container(width: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 10),
          SizedBox(
            width: 50,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(timeLabel(b.startMin).split(' ').first, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Text(timeLabel(b.startMin).split(' ').last, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: p.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
                if (live) ...[const SizedBox(width: 6), PulseDot(color: p.success, size: 8)],
              ]),
              const SizedBox(height: 2),
              Text('${daysCode(b.days)} · $count ${tr('students_short')} · ${mine ? tr('you') : b.teacherName}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 8),
          Center(
            child: done
                ? Tag('${att!.present.length}/${att!.marked.length} ✓', fg: p.success, bg: p.successTint)
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(999), boxShadow: p.glow(p.brand)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.fact_check_outlined, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(tr('mark'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}
