import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'money.dart' show MonthBar;

String clock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return timeLabel(d.hour * 60 + d.minute);
}

/// Teacher home: one tap to check in when arriving and out when leaving.
class CheckInCard extends StatefulWidget {
  const CheckInCard({super.key, required this.m});
  final Membership m;
  @override
  State<CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends State<CheckInCard> {
  CheckIn? _today;
  int _days = 0;
  bool _loaded = false, _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    _loaded = true;
    try {
      final now = DateTime.now();
      final list = await context.appRead.backend.checkIns(widget.m.instituteId, monthKey(now), uid: widget.m.uid);
      if (!mounted) return;
      setState(() {
        _today = list.where((c) => c.dateKey == dateKey(now)).firstOrNull;
        _days = list.length;
      });
    } catch (_) {}
  }

  Future<void> _tap() async {
    final app = context.appRead;
    final now = DateTime.now();
    setState(() => _busy = true);
    try {
      final c = _today ?? CheckIn(uid: widget.m.uid, name: app.profile?.name ?? widget.m.name, dateKey: dateKey(now), inAt: now.millisecondsSinceEpoch);
      if (_today != null) c.outAt = now.millisecondsSinceEpoch;
      await app.backend.saveCheckIn(widget.m.instituteId, c);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        if (_today == null) _days++;
        _today = c;
      });
      toast(context, c.outAt > 0 ? trf('checked_out_at', {'t': clock(c.outAt)}) : trf('checked_in_at', {'t': clock(c.inAt)}));
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final t = _today;
    final inNow = t != null && t.outAt == 0;
    final done = t != null && t.outAt > 0;
    final c = done ? p.muted : (inNow ? p.danger : p.success);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        IconBox(done ? Icons.task_alt_rounded : Icons.how_to_reg_rounded, fg: done ? p.success : p.brand, bg: done ? p.successTint : p.brandTint),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              t == null ? tr('not_checked_in') : (done ? '${clock(t.inAt)} – ${clock(t.outAt)}' : trf('in_since', {'t': clock(t.inAt)})),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
            Text(trf('checkins_this_month', {'n': '$_days'}), style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        if (!done)
          GestureDetector(
            onTap: _busy || !_loaded ? null : _tap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12), boxShadow: p.glow(c)),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : Text(inNow ? tr('check_out') : tr('check_in'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          )
        else
          Tag(tr('done'), fg: p.success, bg: p.successTint),
      ]),
    );
  }
}

/// Admin: who came today and how many days each teacher came this month.
class CheckInsScreen extends StatefulWidget {
  const CheckInsScreen({super.key, required this.m});
  final Membership m;
  @override
  State<CheckInsScreen> createState() => _CheckInsScreenState();
}

class _CheckInsScreenState extends State<CheckInsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('teacher_checkins'),
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
          child: Loader<(List<CheckIn>, List<Membership>)>(
            key: ValueKey(_v),
            load: () async {
              final b = context.appRead.backend;
              return (await b.checkIns(widget.m.instituteId, monthKey(_month)), await b.members(widget.m.instituteId));
            },
            builder: (context, d, reload) {
              final teachers = d.$2.where((x) => x.role == Role.teacher && x.approved).toList();
              final todayKey = dateKey(DateTime.now());
              final today = d.$1.where((c) => c.dateKey == todayKey).toList();
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
                children: [
                  if (monthKey(_month) == monthKey(DateTime.now())) ...[
                    SectionTitle(tr('today')),
                    const SizedBox(height: 6),
                    for (final t in teachers)
                      Builder(builder: (context) {
                        final c = today.where((x) => x.uid == t.uid).firstOrNull;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            padding: const EdgeInsets.all(12),
                            child: Row(children: [
                              Avatar(t.name, size: 40, photo: t.photo),
                              const SizedBox(width: 10),
                              Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                              c == null
                                  ? Tag(tr('not_yet'), fg: p.muted, bg: p.cardAlt)
                                  : Tag(c.outAt > 0 ? '${clock(c.inAt)} – ${clock(c.outAt)}' : '${tr('in_word')} ${clock(c.inAt)}', fg: p.success, bg: p.successTint),
                            ]),
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                  ],
                  SectionTitle(tr('this_month')),
                  const SizedBox(height: 6),
                  if (teachers.isEmpty) EmptyState(icon: Icons.badge_outlined, text: tr('no_teachers')),
                  for (final t in teachers)
                    Builder(builder: (context) {
                      final mine = d.$1.where((x) => x.uid == t.uid).toList();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Avatar(t.name, size: 40, photo: t.photo),
                              const SizedBox(width: 10),
                              Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                              Text(trf('n_days', {'n': '${mine.length}'}), style: TextStyle(fontWeight: FontWeight.w800, color: p.brand)),
                            ]),
                            if (mine.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                for (final c in mine.reversed)
                                  Tooltip(
                                    message: '${clock(c.inAt)}${c.outAt > 0 ? ' – ${clock(c.outAt)}' : ''}',
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(color: p.successTint, borderRadius: BorderRadius.circular(9)),
                                      child: Text(c.dateKey.substring(6), style: TextStyle(color: p.success, fontWeight: FontWeight.w800, fontSize: 12)),
                                    ),
                                  ),
                              ]),
                            ],
                          ]),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}
