import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'home_shell.dart';
import 'notices.dart';
import 'onboarding.dart';

class _LearnerData {
  _LearnerData(this.batches, this.att, this.fees, this.notices);
  final List<Batch> batches;
  final List<AttendanceDay> att;
  final List<FeeRecord> fees;
  final List<Notice> notices;
}

Future<_LearnerData> _loadLearner(BuildContext context, String instId, String uid) async {
  final b = context.appRead.backend;
  return _LearnerData(
    await b.batches(instId),
    await b.attendanceForStudent(instId, uid),
    await b.feesForStudent(instId, uid),
    await b.notices(instId),
  );
}

// ---------------------------------------------------------------------------
// Student
// ---------------------------------------------------------------------------

class StudentHome extends StatelessWidget {
  const StudentHome({super.key, required this.m});
  final Membership m;

  @override
  Widget build(BuildContext context) {
    return Loader<_LearnerData>(
      load: () => _loadLearner(context, m.instituteId, m.uid),
      builder: (context, d, reload) {
        final mine = d.batches.where((b) => m.batchIds.contains(b.id)).toList();
        final notices = d.notices.where((n) => n.batchId.isEmpty || m.batchIds.contains(n.batchId)).toList();
        return _LearnerBody(
          m: m,
          name: context.app.profile?.name ?? m.name,
          studentUid: m.uid,
          studentCode: m.studentCode,
          monthlyFee: m.monthlyFee,
          batches: mine,
          d: d,
          notices: notices,
          isParent: false,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Parent
// ---------------------------------------------------------------------------

class ParentHome extends StatelessWidget {
  const ParentHome({super.key, required this.m, required this.childIndex, required this.onChild});
  final Membership m;
  final int childIndex;
  final ValueChanged<int> onChild;

  @override
  Widget build(BuildContext context) {
    if (m.childUids.isEmpty) return EmptyState(icon: Icons.child_care_rounded, text: tr('no_child'));
    final i = childIndex.clamp(0, m.childUids.length - 1);
    final uid = m.childUids[i];
    final name = m.childNames.length > i ? m.childNames[i] : '';
    return Loader<_LearnerData>(
      key: ValueKey(uid),
      load: () => _loadLearner(context, m.instituteId, uid),
      builder: (context, d, reload) {
        final ids = d.att.map((a) => a.batchId).toSet();
        final batches = d.batches.where((b) => ids.contains(b.id)).toList();
        return _LearnerBody(
          m: m,
          name: name,
          studentUid: uid,
          studentCode: '',
          monthlyFee: d.fees.isEmpty ? 0 : d.fees.first.amount,
          batches: batches,
          d: d,
          notices: d.notices,
          isParent: true,
          childSwitcher: m.childUids.length > 1
              ? Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var k = 0; k < m.childUids.length; k++)
                    ChoiceChip(
                      label: Text(m.childNames.length > k ? firstName(m.childNames[k]) : '—'),
                      selected: k == i,
                      onSelected: (_) => onChild(k),
                    ),
                ])
              : null,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared body
// ---------------------------------------------------------------------------

class _LearnerBody extends StatelessWidget {
  const _LearnerBody({
    required this.m,
    required this.name,
    required this.studentUid,
    required this.studentCode,
    required this.monthlyFee,
    required this.batches,
    required this.d,
    required this.notices,
    required this.isParent,
    this.childSwitcher,
  });
  final Membership m;
  final String name, studentUid, studentCode;
  final int monthlyFee;
  final List<Batch> batches;
  final _LearnerData d;
  final List<Notice> notices;
  final bool isParent;
  final Widget? childSwitcher;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final c = attendanceCount(studentUid, d.att);
    final v = pct(c.present, c.total);
    final col = c.total == 0 ? p.muted : (v >= 75 ? p.success : (v >= 50 ? p.warn : p.danger));
    final cur = d.fees.where((f) => f.month == monthKey(DateTime.now())).firstOrNull;
    final paid = cur?.paid == true;
    final feeAmt = cur?.amount ?? monthlyFee;

    // next class among the batches
    Batch? next;
    var bestScore = 1 << 30;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    for (final b in batches) {
      for (var add = 0; add < 8; add++) {
        final day = now.add(Duration(days: add));
        if (!b.days.contains(day.weekday)) continue;
        if (add == 0 && nowMin > b.endMin) continue;
        final score = add * 1440 + b.startMin;
        if (score < bestScore) {
          bestScore = score;
          next = b;
        }
        break;
      }
    }
    final live = next != null && next.runsOn(now) && nowMin >= next.startMin && nowMin <= next.endMin;

    var i = 0;
    Widget item(Widget w) => FadeIn(delay: stagger(i++), child: w);
    final shell = HomeShell.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        HeroHeader(
          gradient: isParent ? LinearGradient(colors: [p.success, const Color(0xFF0E6A70)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          bottomPad: 70,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${greeting()} 👋', style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(firstName(isParent ? (app.profile?.name ?? m.name) : name),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                ]),
              ),
              if (!isParent)
                _HeroBtn(icon: Icons.badge_rounded, label: tr('id_card'), onTap: () => push(context, IdCardScreen(m: m, batches: batches))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              Tag(m.instituteName, fg: Colors.white, bg: const Color(0x26FFFFFF), leading: const Icon(Icons.apartment_rounded, size: 14, color: Colors.white)),
              if (isParent) Tag('${tr('child')}: $name', fg: const Color(0xFF073B3F), bg: const Color(0xFFFFD27A)),
            ]),
            if (childSwitcher != null) ...[const SizedBox(height: 10), childSwitcher!],
          ]),
        ),
        Transform.translate(
          offset: const Offset(0, -50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              item(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: AppCard(
                    onTap: () => shell?.goTo(1),
                    child: Column(children: [
                      Ring(
                        value: c.total == 0 ? 0 : c.present / c.total,
                        size: 92,
                        stroke: 10,
                        color: col,
                        track: p.cardAlt,
                        center: c.total == 0
                            ? Text('—', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: p.muted))
                            : CountUp(v, suffix: '%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: col)),
                      ),
                      const SizedBox(height: 8),
                      Text(tr('attendance'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${c.present}/${c.total} ${tr('days')}', style: TextStyle(color: p.muted, fontSize: 12)),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppCard(
                    onTap: () => shell?.goTo(2),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      IconBox(paid ? Icons.verified_rounded : Icons.account_balance_wallet_rounded, fg: paid ? p.success : p.danger, bg: paid ? p.successTint : p.dangerTint, size: 42),
                      const SizedBox(height: 10),
                      Text(trf('fees_of', {'m': tr('m${now.month}')}), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text(feeAmt == 0 ? '—' : rupees(feeAmt), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Tag(paid ? tr('paid') : tr('due'), fg: paid ? p.success : p.danger, bg: paid ? p.successTint : p.dangerTint),
                    ]),
                  ),
                ),
              ])),
              if (c.total > 0 && v < 75) ...[
                const SizedBox(height: 10),
                item(AppCard(
                  color: p.dangerTint,
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: p.danger),
                    const SizedBox(width: 8),
                    Expanded(child: Text(isParent ? tr('att_low_parent') : tr('att_low_warn'), style: TextStyle(color: p.danger, fontWeight: FontWeight.w700, fontSize: 13))),
                  ]),
                )),
              ],
              const SizedBox(height: 12),
              const DemoBanner(),
              if (next != null)
                item(AppCard(
                  gradient: LinearGradient(colors: [p.indigo, p.indigo.withValues(alpha: .78)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  child: Row(children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.alarm_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(live ? tr('class_on_now') : tr('next_class'), style: const TextStyle(color: Color(0xCCFFFFFF), fontWeight: FontWeight.w700, fontSize: 12.5)),
                          if (live) ...[const SizedBox(width: 6), const PulseDot(color: Color(0xFF4ADE80), size: 8)],
                        ]),
                        Text(next.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                        Text('${nextClassText(next)} · ${next.teacherName}', style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 12.5)),
                      ]),
                    ),
                  ]),
                )),
              const SizedBox(height: 16),
              item(SectionTitle(isParent ? tr('child_timetable') : tr('my_timetable'))),
              const SizedBox(height: 8),
              if (batches.isEmpty) item(AppCard(child: EmptyState(icon: Icons.event_note_rounded, text: tr('no_batch_joined')))),
              for (final b in batches)
                item(Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        IconBox(Icons.menu_book_rounded, fg: p.indigo, bg: p.indigoTint),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                            Text('${b.teacherName} · ${timeLabel(b.startMin)}–${timeLabel(b.endMin)}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                          ]),
                        ),
                        Tag(daysCode(b.days), fg: p.indigo, bg: p.indigoTint),
                      ]),
                      const SizedBox(height: 10),
                      Row(
                        children: List.generate(7, (k) {
                          final on = b.days.contains(k + 1);
                          final today = now.weekday == k + 1;
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: on ? (today ? p.indigo : p.indigoTint) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: today && !on ? Border.all(color: p.border) : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(dayShort(k + 1), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: on ? (today ? Colors.white : p.indigo) : p.muted.withValues(alpha: .6))),
                            ),
                          );
                        }),
                      ),
                    ]),
                  ),
                )),
              if (!isParent && studentCode.isNotEmpty) ...[
                const SizedBox(height: 6),
                item(AppCard(
                  color: p.cardAlt,
                  child: Row(children: [
                    IconBox(Icons.family_restroom_rounded, fg: p.success, bg: p.successTint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('parent_code_title'), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(trf('parent_code_sub', {'code': studentCode}), style: TextStyle(color: p.muted, fontSize: 12.5)),
                      ]),
                    ),
                    IconButton(
                      onPressed: () => SharePlus.instance.share(ShareParams(text: trf('share_student_code', {'name': name, 'inst': m.instituteName, 'code': studentCode}))),
                      icon: Icon(Icons.share_rounded, color: p.success),
                    ),
                  ]),
                )),
              ],
              if (notices.isNotEmpty) ...[
                const SizedBox(height: 16),
                item(SectionTitle(tr('latest_notice'), trailing: TextButton(onPressed: () => shell?.goTo(3), child: Text(tr('see_all'))))),
                item(NoticeCard(n: notices.first, instituteName: m.instituteName)),
              ],
              const SizedBox(height: 14),
              item(SoftButton(
                label: isParent ? tr('add_another_child') : tr('join_another_batch'),
                icon: Icons.add_rounded,
                onPressed: () => app.startNewJoin(isParent ? Role.parent : Role.student),
              )),
            ]),
          ),
        ),
      ],
    );
  }
}

class _HeroBtn extends StatelessWidget {
  const _HeroBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0x26FFFFFF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// ID card with QR
// ---------------------------------------------------------------------------

class IdCardScreen extends StatelessWidget {
  const IdCardScreen({super.key, required this.m, required this.batches});
  final Membership m;
  final List<Batch> batches;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final u = app.profile;
    final name = u?.name ?? m.name;
    return Scaffold(
      appBar: InnerBar(title: tr('id_card')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          FadeIn(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: .6, end: 0),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutBack,
              builder: (context, v, child) => Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(v),
                child: child,
              ),
              child: Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), boxShadow: p.shadow),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Column(children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 46),
                      decoration: BoxDecoration(gradient: p.hero),
                      child: Row(children: [
                        const AppLogo(size: 38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.instituteName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                            Text(tr('student_id_card'), style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .5)),
                          ]),
                        ),
                      ]),
                    ),
                    Container(
                      color: p.card,
                      width: double.infinity,
                      child: Column(children: [
                        Transform.translate(
                          offset: const Offset(0, -34),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(28)),
                            child: Avatar(name, size: 76),
                          ),
                        ),
                        Transform.translate(
                          offset: const Offset(0, -24),
                          child: Column(children: [
                            Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(batches.map((b) => b.title).join('\n'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
                              child: QrImageView(
                                data: 'VIDYADESK:${m.studentCode.isEmpty ? m.uid : m.studentCode}',
                                size: 170,
                                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF073B3F)),
                                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF073B3F)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(m.studentCode, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: p.brand)),
                            if (u != null) ...[
                              const SizedBox(height: 6),
                              Text(u.fullPhone, style: TextStyle(color: p.muted)),
                            ],
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(tr('id_card_note'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}
