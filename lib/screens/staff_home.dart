import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'attendance.dart';
import 'batches.dart';
import 'common.dart';
import 'home_shell.dart';
import 'notices.dart';
import 'onboarding.dart';
import 'people.dart';

class _StaffData {
  _StaffData(this.members, this.batches, this.today, this.fees, this.notices);
  final List<Membership> members;
  final List<Batch> batches;
  final Map<String, AttendanceDay?> today;
  final List<FeeRecord> fees;
  final List<Notice> notices;
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
    final id = widget.m.instituteId;
    final members = await b.members(id);
    final batches = await b.batches(id);
    final now = DateTime.now();
    final dk = dateKey(now);
    final today = <String, AttendanceDay?>{};
    for (final x in myBatches(widget.m, batches).where((x) => x.runsOn(now))) {
      today[x.id] = await b.attendance(id, x.id, dk);
    }
    final fees = widget.m.role == Role.admin ? await b.feesForMonth(id, monthKey(now)) : <FeeRecord>[];
    final notices = await b.notices(id);
    return _StaffData(members, batches, today, fees, notices);
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
    final students = admin ? approvedStudents(d.members) : approvedStudents(d.members).where((s) => s.batchIds.any((id) => mine.any((b) => b.id == id))).toList();
    final pending = pendingFor(m, d.members, d.batches);
    var todays = mine.where((b) => b.runsOn(now)).toList()..sort((a, b) => a.startMin.compareTo(b.startMin));
    if (_onlyMine) todays = todays.where((b) => b.teacherUid == m.uid).toList();

    var marked = 0, present = 0;
    for (final a in d.today.values) {
      if (a == null) continue;
      marked += a.marked.length;
      present += a.present.length;
    }
    final attPct = pct(present, marked);

    // fees: students without a record this month still owe their monthly fee
    final feeByUid = {for (final f in d.fees) f.studentUid: f};
    var due = 0, got = 0;
    for (final s in approvedStudents(d.members)) {
      final f = feeByUid[s.uid];
      final amt = f?.amount ?? s.monthlyFee;
      due += amt;
      if (f?.paid == true) got += amt;
    }

    var i = 0;
    Widget item(Widget w) => FadeIn(delay: stagger(i++), child: w);

    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        HeroHeader(
          bottomPad: 70,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${greeting()} 👋', style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(trf('hello_ji', {'n': firstName(app.profile?.name ?? m.name)}),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                ]),
              ),
              GestureDetector(
                onTap: () => HomeShell.of(context)?.goTo(4),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x66FFFFFF), width: 2)),
                  child: ClipOval(child: Avatar(app.profile?.name ?? m.name, size: 44)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              Tag(m.instituteName, fg: Colors.white, bg: const Color(0x26FFFFFF), leading: const Icon(Icons.apartment_rounded, size: 14, color: Colors.white)),
              Tag(roleName(m.role) + (admin && m.teaches ? ' + ${tr('role_teacher')}' : ''), fg: const Color(0xFF073B3F), bg: const Color(0xFFFFD27A)),
            ]),
            if (admin) ...[
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text(trf('fees_this_month', {'m': tr('m${now.month}')}), style: const TextStyle(color: Color(0xCCFFFFFF), fontWeight: FontWeight.w700, fontSize: 13))),
                CountUp(got, prefix: '₹', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                Text(' / ${rupees(due)}', style: const TextStyle(color: Color(0xAAFFFFFF), fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
              const SizedBox(height: 8),
              GrowBar(value: due == 0 ? 0 : got / due, color: const Color(0xFFF5A524), track: const Color(0x33FFFFFF), gradient: p.gold, height: 9),
            ],
          ]),
        ),
        Transform.translate(
          offset: const Offset(0, -50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              item(Row(children: [
                Expanded(child: _Stat(icon: Icons.groups_rounded, value: students.length, label: tr('students'), fg: p.brand, bg: p.brandTint)),
                const SizedBox(width: 10),
                Expanded(child: _Stat(icon: Icons.class_rounded, value: mine.length, label: tr('batches'), fg: p.indigo, bg: p.indigoTint)),
                const SizedBox(width: 10),
                Expanded(child: _Stat(icon: Icons.fact_check_rounded, value: attPct, suffix: '%', label: tr('today_present'), fg: p.success, bg: p.successTint, empty: marked == 0)),
              ])),
              const SizedBox(height: 12),
              const DemoBanner(),
              if (pending.isNotEmpty)
                item(Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    gradient: LinearGradient(colors: [p.warnTint, p.card]),
                    onTap: () async {
                      await push(context, RequestsScreen(m: m));
                      reload();
                    },
                    child: Row(children: [
                      Stack(clipBehavior: Clip.none, children: [
                        IconBox(Icons.person_add_alt_1_rounded, fg: p.warn, bg: p.card),
                        Positioned(right: -2, top: -2, child: PulseDot(color: p.danger)),
                      ]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(trf('n_requests', {'n': '${pending.length}'}), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          Text(pending.take(3).map((x) => x.name).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ]),
                      ),
                      Tag(tr('review'), fg: p.warn, bg: p.card),
                    ]),
                  ),
                )),
              item(SectionTitle(
                tr('todays_classes'),
                trailing: admin && m.teaches
                    ? SizedBox(
                        width: 150,
                        child: Segmented(items: [tr('all'), tr('mine')], index: _onlyMine ? 1 : 0, onChanged: (v) => setState(() => _onlyMine = v == 1)),
                      )
                    : Text(prettyDay(now), style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 13)),
              )),
              const SizedBox(height: 8),
              if (todays.isEmpty)
                item(AppCard(child: EmptyState(icon: Icons.free_breakfast_rounded, text: mine.isEmpty ? tr('no_batches_yet') : tr('no_class_today'))))
              else
                for (final b in todays)
                  item(Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TodayClass(
                      b: b,
                      mine: b.teacherUid == m.uid,
                      count: approvedStudents(d.members, batchId: b.id).length,
                      att: d.today[b.id],
                      onMark: () async {
                        await push(context, MarkAttendanceScreen(m: m, batch: b));
                        reload();
                      },
                    ),
                  )),
              const SizedBox(height: 8),
              item(SectionTitle(tr('quick_actions'))),
              const SizedBox(height: 8),
              item(GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.02,
                children: [
                  _Action(icon: Icons.add_box_rounded, label: tr('new_batch'), fg: p.indigo, bg: p.indigoTint, onTap: () async {
                    await push(context, CreateBatchScreen(m: m, members: d.members));
                    reload();
                  }),
                  _Action(icon: Icons.groups_rounded, label: tr('students'), fg: p.brand, bg: p.brandTint, onTap: () async {
                    await push(context, Scaffold(appBar: InnerBar(title: tr('people')), body: PeoplePage(m: m, embedded: true)));
                    reload();
                  }),
                  _Action(icon: Icons.campaign_rounded, label: tr('send_notice'), fg: p.warn, bg: p.warnTint, onTap: () async {
                    await push(context, PostNoticeScreen(m: m, batches: mine));
                    reload();
                  }),
                  if (admin)
                    _Action(icon: Icons.qr_code_2_rounded, label: tr('institute_code'), fg: p.success, bg: p.successTint, onTap: () => push(context, InstituteCodeScreen(m: m))),
                  _Action(icon: Icons.how_to_reg_rounded, label: tr('requests'), fg: p.danger, bg: p.dangerTint, badge: pending.length, onTap: () async {
                    await push(context, RequestsScreen(m: m));
                    reload();
                  }),
                  if (admin)
                    _Action(icon: Icons.account_balance_wallet_rounded, label: tr('nav_fees'), fg: p.accent, bg: p.warnTint, onTap: () => HomeShell.of(context)?.goTo(2))
                  else
                    _Action(icon: Icons.class_rounded, label: tr('nav_batches'), fg: p.accent, bg: p.warnTint, onTap: () => HomeShell.of(context)?.goTo(1)),
                ],
              )),
              if (d.notices.isNotEmpty) ...[
                const SizedBox(height: 16),
                item(SectionTitle(tr('latest_notice'), trailing: TextButton(onPressed: () => HomeShell.of(context)?.goTo(3), child: Text(tr('see_all'))))),
                item(NoticeCard(n: d.notices.first)),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label, required this.fg, required this.bg, this.suffix = '', this.empty = false});
  final IconData icon;
  final int value;
  final String label, suffix;
  final Color fg, bg;
  final bool empty;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconBox(icon, fg: fg, bg: bg, size: 34),
        const SizedBox(height: 10),
        empty
            ? Text('—', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: p.muted))
            : CountUp(value, suffix: suffix, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.5)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.fg, required this.bg, required this.onTap, this.badge = 0});
  final IconData icon;
  final String label;
  final Color fg, bg;
  final VoidCallback onTap;
  final int badge;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(clipBehavior: Clip.none, children: [
          IconBox(icon, fg: fg, bg: bg, size: 44),
          if (badge > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(10)),
                child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.15)),
      ]),
    );
  }
}

class _TodayClass extends StatelessWidget {
  const _TodayClass({required this.b, required this.mine, required this.count, required this.att, required this.onMark});
  final Batch b;
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
      padding: const EdgeInsets.all(14),
      border: live ? p.success : null,
      child: Row(children: [
        Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: live ? p.successTint : p.cardAlt, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(timeLabel(b.startMin).split(' ').first, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: live ? p.success : p.ink)),
            Text(timeLabel(b.startMin).split(' ').last, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: p.muted)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5))),
              if (live) ...[const SizedBox(width: 6), PulseDot(color: p.success, size: 8)],
            ]),
            const SizedBox(height: 3),
            Text('${daysCode(b.days)} · $count ${tr('students_short')} · ${mine ? tr('you') : b.teacherName}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
            if (done) ...[
              const SizedBox(height: 4),
              Text('✓ ${att!.present.length}/${att!.marked.length} ${tr('present')}', style: TextStyle(color: p.success, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        done
            ? IconButton.filledTonal(onPressed: onMark, icon: const Icon(Icons.edit_rounded, size: 20), tooltip: tr('edit'))
            : SoftButton(label: tr('mark'), icon: Icons.fact_check_rounded, height: 40, onPressed: onMark),
      ]),
    );
  }
}
