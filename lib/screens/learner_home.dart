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
import 'attendance.dart';
import 'insights.dart';
import 'notices.dart';
import 'notifications.dart';
import 'tools.dart';
import 'tests.dart' show TestsPage;
import 'doubts.dart' show DoubtsPage;
import 'onboarding.dart';
import 'schedule.dart';
import '../ui/mascot.dart';
import 'subscription.dart';
import '../core/plan.dart';
import 'owner.dart' show HomeBanners;

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
          childSwitcher: _KidsRow(m: m, selected: i, onPick: onChild),
        );
      },
    );
  }
}

/// Round photos of each child + "Add kid" — tap to switch.
class _KidsRow extends StatelessWidget {
  const _KidsRow({required this.m, required this.selected, required this.onPick});
  final Membership m;
  final int selected;
  final ValueChanged<int> onPick;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget kid(Widget circle, String label, bool on, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? p.brand : Colors.transparent, width: 2.5)),
                child: circle,
              ),
              const SizedBox(height: 5),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w800 : FontWeight.w700, color: on ? p.brand : p.ink2)),
            ]),
          ),
        );
    return SizedBox(
      height: 92,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        kid(
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.brand, boxShadow: p.glow(p.brand)),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
          tr('add_kid'),
          false,
          () => context.appRead.startNewJoin(Role.parent),
        ),
        for (var k = 0; k < m.childUids.length; k++)
          kid(
            ClipOval(child: Avatar(m.childNames.length > k ? m.childNames[k] : '?', size: 58, index: k, photo: context.app.childPhotos[m.childUids[k]] ?? '')),
            m.childNames.length > k ? firstName(m.childNames[k]) : '—',
            k == selected,
            () => onPick(k),
          ),
      ]),
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
      padding: EdgeInsets.fromLTRB(0, MediaQuery.of(context).padding.top + 8, 0, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              item(Row(children: [
                GestureDetector(onTap: () => shell?.goToNamed('profile'), child: Avatar(app.profile?.name ?? m.name, size: 46, photo: app.profile?.photo ?? '')),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${greeting()} 👋', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(app.profile?.name ?? m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.3)),
                  ]),
                ),
                if (!isParent) ...[
                  IconBtn(icon: Icons.badge_outlined, tooltip: tr('id_card'), onTap: () => push(context, IdCardScreen(m: m, batches: batches))),
                  const SizedBox(width: 10),
                ],
                IconBtn(
                  icon: Icons.notifications_none_rounded,
                  dot: notices.any((n) => n.createdAt > app.lastSeenNotif),
                  tooltip: tr('notifications'),
                  onTap: () => push(context, NotificationsScreen(m: m)),
                ),
              ])),
              if (childSwitcher != null) ...[const SizedBox(height: 14), childSwitcher!],
              const SizedBox(height: 16),
              HomeBanners(role: m.role),
              PlanBanner(m: m),
              item(FeatureCard(
                onTap: () => push(context, ScheduleScreen(m: m)),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(
                            (next == null ? tr('no_upcoming') : (live ? tr('class_on_now') : '${tr('next_class')} · ${nextClassText(next)}')).toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .4),
                          ),
                        ),
                        if (live) ...[const SizedBox(width: 6), const PulseDot(color: Color(0xFF4ADE80), size: 8)],
                      ]),
                      const SizedBox(height: 6),
                      Text(next?.subject ?? m.instituteName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                      if (next != null)
                        Text('${timeLabel(next.startMin)} – ${timeLabel(next.endMin)} · ${next.teacherName}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        GlassChip(tr('nav_schedule'), icon: Icons.calendar_month_outlined, solid: true),
                        if (isParent) GlassChip(firstName(name)),
                      ]),
                    ]),
                  ),
                  const Mascot(size: 96, book: false),
                ]),
              )),
              const SizedBox(height: 12),
              item(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: AppCard(
                    onTap: () => isParent ? shell?.goToNamed('attendance') : push(context, MyAttendancePage(m: m, studentUid: studentUid, studentName: name, back: true)),
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Ring(
                        value: c.total == 0 ? 0 : c.present / c.total,
                        size: 58,
                        stroke: 7,
                        color: col,
                        track: c.total == 0 ? p.cardAlt : col.withValues(alpha: .15),
                        center: Text(c.total == 0 ? '—' : '$v%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: col)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('attendance'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          Text('${c.present}/${c.total} ${tr('days')}', style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 138,
                  child: AppCard(
                    onTap: () => shell?.goToNamed('fees'),
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        IconBox(paid ? Icons.check_rounded : Icons.account_balance_wallet_outlined, fg: paid ? p.success : p.danger, bg: paid ? p.successTint : p.dangerTint, size: 30),
                        const SizedBox(width: 6),
                        Expanded(child: Text(tr('m${now.month}'), style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 8),
                      Text(feeAmt == 0 ? '—' : rupees(feeAmt), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                      const SizedBox(height: 4),
                      Tag(paid ? tr('paid') : tr('due'), fg: paid ? p.success : p.danger, bg: paid ? p.successTint : p.dangerTint),
                    ]),
                  ),
                ),
              ])),
              if (c.total > 0 && v < 75) ...[
                const SizedBox(height: 10),
                item(Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.dangerTint, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: p.danger),
                    const SizedBox(width: 8),
                    Expanded(child: Text(isParent ? tr('att_low_parent') : tr('att_low_warn'), style: TextStyle(color: p.danger, fontWeight: FontWeight.w700, fontSize: 13))),
                  ]),
                )),
              ],
              const SizedBox(height: 12),
              item(ToolsRow(m: m, studentUid: studentUid, studentName: name)),
              const SizedBox(height: 12),
              if (app.newItems.isNotEmpty) ...[
                item(SectionTitle(tr('whats_new'))),
                for (final n in app.newItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(12),
                      onTap: () async {
                        app.markSeen(n.$1);
                        await push(context, switch (n.$1) { 'notices' => NoticesPage(m: m, back: true), 'results' => TestsPage(m: m), _ => DoubtsPage(m: m) });
                        app.loadBadges();
                      },
                      child: Row(children: [
                        IconBox(
                          switch (n.$1) { 'notices' => Icons.campaign_rounded, 'results' => Icons.emoji_events_rounded, _ => Icons.forum_rounded },
                          fg: switch (n.$1) { 'notices' => p.danger, 'results' => p.warn, _ => p.brand },
                          bg: p.cardAlt,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(n.$1 == 'doubts' ? trf('doubt_answered_new', {'s': n.$2}) : (n.$1 == 'results' ? trf('result_out_new', {'s': n.$2}) : n.$2),
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text('${tr('wn_${n.$1}')} · ${ago(n.$3)}', style: TextStyle(color: p.muted, fontSize: 12)),
                          ]),
                        ),
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle)),
                      ]),
                    ),
                  ),
                const SizedBox(height: 4),
              ],
              if (planHas(context, Feature.doubts)) BadgesCard(m: m),
              const DemoBanner(),
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
                            Text(b.title, style: const TextStyle(fontWeight: FontWeight.w800)),
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
                item(SectionTitle(tr('latest_notice'), trailing: TextButton(onPressed: () => push(context, NoticesPage(m: m, back: true)), child: Text(tr('see_all'))))),
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
                            Text(m.instituteName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
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
                            child: Avatar(name, size: 76, photo: app.profile?.photo ?? ''),
                          ),
                        ),
                        Transform.translate(
                          offset: const Offset(0, -24),
                          child: Column(children: [
                            Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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
                            Text(m.studentCode, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: p.brand)),
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
