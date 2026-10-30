import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'doubts.dart';
import 'notices.dart';
import 'payments.dart';
import 'people.dart';
import 'resources.dart';
import 'tests.dart';

class _Item {
  _Item({required this.icon, required this.color, required this.title, required this.body, required this.at, required this.open});
  final IconData icon;
  final Color color;
  final String title, body;
  final int at;
  final Future<void> Function(BuildContext context) open;
}

/// One feed of everything new: notices, study material, results, doubts,
/// payments to confirm and join requests.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.m});
  final Membership m;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _seenBefore = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _seenBefore = context.appRead.lastSeenNotif;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.appRead.markNotifSeen();
    });
  }

  Future<List<_Item>> _load(Palette p) async {
    final app = context.appRead;
    final b = app.backend;
    final m = widget.m;
    final id = m.instituteId;
    final staff = m.isStaff;
    final uid = learnerUid(context, m);
    final now = DateTime.now().millisecondsSinceEpoch;
    const month = 30 * 86400000;
    // start everything at once (faster than one after another)
    final batchesF = b.batches(id);
    final noticesF = b.notices(id);
    final resF = b.resources(id);
    final testsF = staff ? null : b.tests(id, publishedOnly: true);
    final doubtsF = m.role == Role.parent ? null : b.doubts(id, studentUid: staff ? null : m.uid);
    final claimsF = m.role == Role.admin ? b.feeClaims(id) : null;
    final membersF = staff ? b.members(id) : null;
    final batches = await batchesF;
    final out = <_Item>[];

    // notices
    final notices = await noticesF;
    for (final n in notices) {
      if (m.role == Role.student && n.batchId.isNotEmpty && !m.batchIds.contains(n.batchId)) continue;
      final s = noticeStyle(p, n.kind);
      out.add(_Item(icon: s.$1, color: s.$2, title: tr('kind_${n.kind}'), body: n.text, at: n.createdAt, open: (c) => push(c, NoticesPage(m: m, back: true))));
    }

    // study material
    final res = visibleResources(m, await resF, batches);
    for (final r in res.where((r) => now - r.createdAt < month && r.byUid != m.uid)) {
      final s = kindStyle(r.kind);
      out.add(_Item(
        icon: s.icon,
        color: s.color,
        title: trf('new_kind', {'kind': tr('rk_${r.kind}')}),
        body: r.title,
        at: r.createdAt,
        open: (c) => openResource(c, m, r, batches),
      ));
      // homework due tomorrow / today
      if (!staff && r.kind == 'homework' && r.dueAt > 0) {
        final left = r.dueAt - now;
        if (left > -86400000 && left < 2 * 86400000) {
          out.add(_Item(
            icon: Icons.alarm_rounded,
            color: p.warn,
            title: tr('hw_due_soon'),
            body: '${r.title} · ${prettyDay(DateTime.fromMillisecondsSinceEpoch(r.dueAt))}',
            at: now - 60000,
            open: (c) => openResource(c, m, r, batches),
          ));
        }
      }
    }

    // results
    if (!staff) {
      for (final t in await testsF!) {
        final v = t.marks[uid];
        if (v == null || now - t.date > 2 * month) continue;
        out.add(_Item(
          icon: Icons.emoji_events_rounded,
          color: p.success,
          title: trf('result_out', {'t': t.title}),
          body: '${fmtMarks(v)}/${t.maxMarks} · ${trf('rank_of', {'r': '${t.rankOf(uid)}', 'n': '${t.marks.length}'})}',
          at: t.date + 3600000,
          open: (c) => push(c, TestsPage(m: m)),
        ));
      }
    }

    // doubts
    if (m.role != Role.parent) {
      var doubts = await doubtsF!;
      if (m.role == Role.teacher) {
        final mine = myBatches(m, batches).map((x) => x.id).toSet();
        doubts = doubts.where((d) => mine.contains(d.batchId)).toList();
      }
      for (final d in doubts) {
        if (staff && !d.solved && !d.answered) {
          out.add(_Item(
            icon: Icons.help_outline_rounded,
            color: p.warn,
            title: trf('new_doubt_from', {'name': d.studentName}),
            body: '${d.subject}: ${d.text}',
            at: d.lastAt,
            open: (c) => push(c, DoubtThreadScreen(m: m, doubt: d, batch: batches.where((x) => x.id == d.batchId).firstOrNull)),
          ));
        } else if (!staff && d.replies.isNotEmpty && d.replies.last.staff) {
          out.add(_Item(
            icon: Icons.mark_chat_read_rounded,
            color: p.indigo,
            title: trf('teacher_replied', {'name': d.replies.last.byName}),
            body: d.replies.last.text.isEmpty ? d.text : d.replies.last.text,
            at: d.replies.last.at,
            open: (c) => push(c, DoubtThreadScreen(m: m, doubt: d, batch: batches.where((x) => x.id == d.batchId).firstOrNull)),
          ));
        }
      }
    }

    // admin: UPI payments to confirm
    if (m.role == Role.admin) {
      for (final f in await claimsF!) {
        out.add(_Item(
          icon: Icons.currency_rupee_rounded,
          color: p.success,
          title: trf('fee_received_from', {'name': f.studentName}),
          body: '${rupees(f.amount)} · ${monthLabel(f.month)}${f.claimUtr.isEmpty ? '' : ' · UTR ${f.claimUtr}'} — ${tr('tap_to_confirm')}',
          at: f.claimAt,
          open: (c) => push(c, ConfirmPaymentsScreen(m: m)),
        ));
      }
    }

    // staff: join requests
    if (staff) {
      final pend = pendingFor(m, await membersF!, batches);
      for (final x in pend) {
        out.add(_Item(
          icon: Icons.person_add_alt_1_rounded,
          color: p.brand,
          title: trf('wants_to_join', {'name': x.name}),
          body: tr('role_${x.role.name}'),
          at: x.createdAt,
          open: (c) => push(c, RequestsScreen(m: m)),
        ));
      }
    }

    out.sort((a, b) => b.at.compareTo(a.at));
    return out.take(80).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('notifications'),
      subtitle: widget.m.instituteName,
      body: Loader<List<_Item>>(
        load: () => _load(p),
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [EmptyState(icon: Icons.notifications_none_rounded, text: tr('no_notifications'))]);
          }
          final fresh = items.where((x) => x.at > _seenBefore).toList();
          final old = items.where((x) => x.at <= _seenBefore).toList();
          var i = 0;
          Widget tile(_Item x, bool isNew) => FadeIn(
                delay: stagger(i++),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    onTap: () async {
                      await x.open(context);
                      reload();
                    },
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      IconBox(x.icon, fg: x.color, bg: x.color.withValues(alpha: .13)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                            if (isNew) Container(width: 8, height: 8, decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle)),
                          ]),
                          const SizedBox(height: 2),
                          Text(x.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink2, fontSize: 13, height: 1.35)),
                          const SizedBox(height: 4),
                          Text(ago(x.at), style: TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              );
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
            children: [
              if (fresh.isNotEmpty) ...[SectionTitle(tr('new_label')), const SizedBox(height: 6), for (final x in fresh) tile(x, true)],
              if (old.isNotEmpty) ...[
                if (fresh.isNotEmpty) const SizedBox(height: 10),
                SectionTitle(tr('earlier')),
                const SizedBox(height: 6),
                for (final x in old) tile(x, false),
              ],
            ],
          );
        },
      ),
    );
  }
}
