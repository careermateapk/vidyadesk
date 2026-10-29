import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/push.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// Teacher marks who came today (or on another date).
class MarkAttendanceScreen extends StatefulWidget {
  const MarkAttendanceScreen({super.key, required this.m, required this.batch, this.date});
  final Membership m;
  final Batch batch;
  final DateTime? date;
  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  late DateTime _date = widget.date ?? DateTime.now();
  List<Membership>? _students;
  List<Membership> _all = [];
  final Set<String> _present = {};
  bool _existed = false;
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = context.appRead.backend;
      final members = _students == null ? await b.members(widget.m.instituteId) : null;
      final day = await b.attendance(widget.m.instituteId, widget.batch.id, dateKey(_date));
      setState(() {
        if (members != null) {
          _all = members;
          _students = approvedStudents(members, batchId: widget.batch.id);
        }
        _present.clear();
        _existed = day != null;
        if (day != null) {
          _present.addAll(day.present);
        } else {
          _present.addAll(_students!.map((s) => s.uid));
        }
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 120)), lastDate: DateTime.now());
    if (d == null) return;
    _date = d;
    _load();
  }

  /// First time today's attendance is saved: tell absent students and their parents.
  void _tellParents(List<Membership> studs) {
    final today = dateKey(DateTime.now()) == dateKey(_date);
    if (_existed || !today || !(context.appRead.inst?.notifOn('absent') ?? true)) return;
    final i = widget.m.instituteId;
    for (final s in studs.where((s) => !_present.contains(s.uid))) {
      final parents = _all.where((x) => x.role == Role.parent && x.approved && x.childUids.contains(s.uid)).map((x) => Push.person(i, x.uid));
      Push.send(
        inst: i,
        kind: 'absent',
        title: '⚠️ ${trf('push_absent', {'name': s.name})}',
        body: '${widget.batch.title} · ${timeLabel(widget.batch.startMin)}',
        topics: [Push.person(i, s.uid), ...parents].take(5).toList(),
      );
    }
  }

  Future<void> _save() async {
    final studs = _students ?? [];
    setState(() => _saving = true);
    try {
      await context.appRead.backend.saveAttendance(
        widget.m.instituteId,
        AttendanceDay(batchId: widget.batch.id, dateKey: dateKey(_date), marked: studs.map((s) => s.uid).toList(), present: studs.where((s) => _present.contains(s.uid)).map((s) => s.uid).toList()),
      );
      if (!mounted) return;
      _tellParents(studs);
      HapticFeedback.heavyImpact();
      toast(context, trf('att_saved', {'p': '${_present.length}', 't': '${studs.length}'}));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final studs = _students ?? [];
    final presentCount = studs.where((s) => _present.contains(s.uid)).length;
    final runs = widget.batch.runsOn(_date);
    return Scaffold(
      appBar: InnerBar(title: tr('attendance')),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : _students == null
              ? const LoadingView()
              : Column(children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                      children: [
                        AppCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(widget.batch.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                            Text('${daysCode(widget.batch.days)} · ${timeLabel(widget.batch.startMin)}', style: TextStyle(color: p.muted, fontSize: 13)),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: _pickDate,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(color: p.brandTint, borderRadius: BorderRadius.circular(14)),
                                    child: Row(children: [
                                      Icon(Icons.event_rounded, color: p.brand, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(prettyDay(_date), style: TextStyle(fontWeight: FontWeight.w800, color: p.brand))),
                                      Icon(Icons.arrow_drop_down_rounded, color: p.brand),
                                    ]),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Ring(
                                key: ValueKey('$presentCount/${studs.length}'),
                                value: studs.isEmpty ? 0 : presentCount / studs.length,
                                size: 58,
                                stroke: 7,
                                color: p.success,
                                track: p.successTint,
                                center: Text('$presentCount/${studs.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                              ),
                            ]),
                            if (!runs) ...[
                              const SizedBox(height: 8),
                              Text(tr('not_class_day'), style: TextStyle(color: p.warn, fontWeight: FontWeight.w700, fontSize: 12.5)),
                            ],
                            if (_existed) ...[
                              const SizedBox(height: 8),
                              Text(tr('att_already'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 12.5)),
                            ],
                          ]),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: SoftButton(label: tr('all_present'), icon: Icons.done_all_rounded, color: p.successTint, textColor: p.success, onPressed: () => setState(() => _present.addAll(studs.map((s) => s.uid))))),
                          const SizedBox(width: 8),
                          Expanded(child: SoftButton(label: tr('all_absent'), icon: Icons.remove_done_rounded, color: p.dangerTint, textColor: p.danger, onPressed: () => setState(_present.clear))),
                        ]),
                        const SizedBox(height: 12),
                        if (_loading) const LinearProgressIndicator(minHeight: 2),
                        if (studs.isEmpty) EmptyState(icon: Icons.group_add_rounded, text: tr('no_students_batch')),
                        for (var i = 0; i < studs.length; i++)
                          FadeIn(
                            delay: stagger(i, stepMs: 35),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _MarkRow(
                                s: studs[i],
                                index: i,
                                present: _present.contains(studs[i].uid),
                                onChanged: (v) {
                                  HapticFeedback.selectionClick();
                                  setState(() => v ? _present.add(studs[i].uid) : _present.remove(studs[i].uid));
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: PrimaryButton(label: trf('save_att', {'p': '$presentCount', 't': '${studs.length}'}), busy: _saving, onPressed: studs.isEmpty ? null : _save),
                    ),
                  ),
                ]),
    );
  }
}

class _MarkRow extends StatelessWidget {
  const _MarkRow({required this.s, required this.index, required this.present, required this.onChanged});
  final Membership s;
  final int index;
  final bool present;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: present ? p.card : p.dangerTint.withValues(alpha: p.dark ? .5 : .7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: present ? p.border : p.danger.withValues(alpha: .35)),
      ),
      child: Row(children: [
        Avatar(s.name, size: 40, index: index, photo: s.photo),
        const SizedBox(width: 10),
        Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
        _PA(label: 'P', on: present, color: p.success, onTap: () => onChanged(true)),
        const SizedBox(width: 6),
        _PA(label: 'A', on: !present, color: p.danger, onTap: () => onChanged(false)),
      ]),
    );
  }
}

class _PA extends StatelessWidget {
  const _PA({required this.label, required this.on, required this.color, required this.onTap});
  final String label;
  final bool on;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: on ? 1.06 : 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 40,
          decoration: BoxDecoration(color: on ? color : p.cardAlt, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: on ? Colors.white : p.muted)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Student / parent: own attendance
// ---------------------------------------------------------------------------

class MyAttendancePage extends StatelessWidget {
  const MyAttendancePage({super.key, required this.m, required this.studentUid, required this.studentName, this.back = false});
  final Membership m;
  final String studentUid, studentName;
  final bool back;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: m.role == Role.parent ? '${tr('attendance')} · ${firstName(studentName)}' : tr('my_attendance'), showBack: back),
      body: Loader<(List<AttendanceDay>, List<Batch>)>(
        load: () async {
          final b = context.appRead.backend;
          return (await b.attendanceForStudent(m.instituteId, studentUid), await b.batches(m.instituteId));
        },
        builder: (context, d, reload) {
          final days = d.$1;
          final batches = {for (final b in d.$2) b.id: b};
          final c = attendanceCount(studentUid, days);
          final v = pct(c.present, c.total);
          final col = c.total == 0 ? p.muted : (v >= 75 ? p.success : (v >= 50 ? p.warn : p.danger));
          final now = DateTime.now();
          final thisMonth = days.where((x) => x.dateKey.startsWith(dateKey(now).substring(0, 6))).toList();
          final cm = attendanceCount(studentUid, thisMonth);
          final byBatch = <String, List<AttendanceDay>>{};
          for (final x in days) {
            (byBatch[x.batchId] ??= []).add(x);
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
            children: [
              FadeIn(
                child: AppCard(
                  child: Row(children: [
                    Ring(
                      value: c.total == 0 ? 0 : c.present / c.total,
                      size: 110,
                      stroke: 12,
                      color: col,
                      track: p.cardAlt,
                      center: Column(mainAxisSize: MainAxisSize.min, children: [
                        c.total == 0 ? Text('—', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.muted)) : CountUp(v, suffix: '%', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: col)),
                        Text(tr('overall'), style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _kv(p, tr('present'), '${c.present}', p.success),
                        _kv(p, tr('absent'), '${c.total - c.present}', p.danger),
                        _kv(p, tr('this_month'), cm.total == 0 ? '—' : '${pct(cm.present, cm.total)}%', p.brand),
                        if (c.total > 0 && v < 75)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(tr('att_low_warn'), style: TextStyle(color: p.danger, fontSize: 12, fontWeight: FontWeight.w700, height: 1.3)),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              FadeIn(delay: stagger(1), child: SectionTitle(tr('calendar'))),
              const SizedBox(height: 8),
              FadeIn(delay: stagger(2), child: AppCard(child: _Calendar(uid: studentUid, days: days))),
              const SizedBox(height: 14),
              if (byBatch.isNotEmpty) ...[
                SectionTitle(tr('by_batch')),
                const SizedBox(height: 8),
                for (final e in byBatch.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Builder(builder: (context) {
                      final bc = attendanceCount(studentUid, e.value);
                      final bb = batches[e.key];
                      return AppCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(bb?.title ?? tr('batch'), style: const TextStyle(fontWeight: FontWeight.w800))),
                            Text('${pct(bc.present, bc.total)}%', style: TextStyle(fontWeight: FontWeight.w800, color: p.brand)),
                          ]),
                          const SizedBox(height: 8),
                          GrowBar(value: bc.total == 0 ? 0 : bc.present / bc.total, color: p.brand, track: p.brandTint),
                        ]),
                      );
                    }),
                  ),
              ],
              if (days.isEmpty) EmptyState(icon: Icons.event_busy_rounded, text: tr('no_att_yet')),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(Palette p, String k, String v, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(k, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      );
}

/// 30 small squares, one per day: green present, red absent, grey no class.
class _Calendar extends StatefulWidget {
  const _Calendar({required this.uid, required this.days});
  final String uid;
  final List<AttendanceDay> days;
  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final byDate = <String, bool>{};
    for (final d in widget.days) {
      if (!d.marked.contains(widget.uid)) continue;
      byDate[d.dateKey] = (byDate[d.dateKey] ?? false) || d.present.contains(widget.uid);
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = _month;
    final daysIn = DateTime(first.year, first.month + 1, 0).day;
    final lead = first.weekday - 1;
    final isThis = first.year == now.year && first.month == now.month;
    return Column(children: [
      Row(children: [
        Expanded(child: Text(monthLabel(monthKey(first)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _month = DateTime(first.year, first.month - 1)), icon: Icon(Icons.chevron_left_rounded, color: p.muted)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: isThis ? null : () => setState(() => _month = DateTime(first.year, first.month + 1)),
          icon: Icon(Icons.chevron_right_rounded, color: isThis ? p.border : p.muted),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        for (var k = 1; k <= 7; k++)
          Expanded(child: Center(child: Text(dayShort(k).substring(0, 1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.muted)))),
      ]),
      const SizedBox(height: 6),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: GridView.count(
          key: ValueKey(first),
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= daysIn; d++)
              Builder(builder: (context) {
                final date = DateTime(first.year, first.month, d);
                final st = byDate[dateKey(date)];
                final isToday = date == today;
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 250 + d * 15),
                  curve: Curves.easeOutBack,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: Container(
                    decoration: BoxDecoration(
                      color: st == null ? Colors.transparent : (st ? p.successTint : p.danger),
                      borderRadius: BorderRadius.circular(11),
                      border: isToday ? Border.all(color: p.brand, width: 2) : null,
                    ),
                    alignment: Alignment.center,
                    child: Text('$d',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: st == null ? (date.isAfter(today) ? p.border : p.muted) : (st ? p.success : Colors.white),
                        )),
                  ),
                );
              }),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        LegendDot(p.success, tr('present')),
        const SizedBox(width: 14),
        LegendDot(p.danger, tr('absent')),
        const SizedBox(width: 14),
        LegendDot(p.border, tr('no_class')),
      ]),
    ]);
  }
}
