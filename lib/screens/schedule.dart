import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'attendance.dart';
import 'common.dart';

/// Colour pair for a batch, stable by its position.
(Color, Color) batchColors(Palette p, int i) => [
      (p.brand, p.brandTint),
      (p.success, p.successTint),
      (p.indigo, p.indigoTint),
      (p.warn, p.warnTint),
      (p.danger, p.dangerTint),
    ][i % 5];

/// Weekly timetable built from the batches' days and times.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.m, this.tab = false});
  final Membership m;
  final bool tab; // shown as a bottom tab (no back button)
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late DateTime _monday;
  late int _day; // 1..7

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    _day = now.weekday;
  }

  Future<(List<Batch>, Map<String, AttendanceDay?>)> _load() async {
    final b = context.appRead.backend;
    final m = widget.m;
    final all = await b.batches(m.instituteId);
    List<Batch> mine;
    if (m.isStaff) {
      mine = myBatches(m, all);
    } else if (m.role == Role.student) {
      mine = all.where((x) => m.batchIds.contains(x.id)).toList();
    } else {
      final ids = <String>{};
      for (final c in m.childUids) {
        ids.addAll((await b.attendanceForStudent(m.instituteId, c)).map((a) => a.batchId));
      }
      mine = all.where((x) => ids.contains(x.id)).toList();
    }
    mine.sort((a, c) => a.startMin.compareTo(c.startMin));
    final att = <String, AttendanceDay?>{};
    if (m.isStaff) {
      final d = _monday.add(Duration(days: _day - 1));
      for (final x in mine.where((x) => x.runsOn(d))) {
        att[x.id] = await b.attendance(m.instituteId, x.id, dateKey(d));
      }
    }
    return (mine, att);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = _monday.add(Duration(days: _day - 1));
    return AppScaffold(
      title: tr('nav_schedule'),
      subtitle: '${tr('m${selected.month}')} ${selected.year}',
      back: !widget.tab,
      actions: [
        IconBtn(icon: Icons.chevron_left_rounded, box: 40, onTap: () => setState(() => _monday = _monday.subtract(const Duration(days: 7)))),
        IconBtn(icon: Icons.chevron_right_rounded, box: 40, onTap: () => setState(() => _monday = _monday.add(const Duration(days: 7)))),
      ],
      body: Loader<(List<Batch>, Map<String, AttendanceDay?>)>(
        key: ValueKey('${dateKey(_monday)}-$_day'),
        load: _load,
        builder: (context, d, reload) {
          final batches = d.$1;
          final colorOf = {for (var i = 0; i < batches.length; i++) batches[i].id: batchColors(p, i)};
          final dayList = batches.where((b) => b.days.contains(_day)).toList();
          final isToday = selected == today;
          final nowMin = now.hour * 60 + now.minute;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
            children: [
              Row(
                children: List.generate(7, (i) {
                  final date = _monday.add(Duration(days: i));
                  final on = i + 1 == _day;
                  final has = batches.where((b) => b.days.contains(i + 1)).take(3).toList();
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _day = i + 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: on ? p.brand : p.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: on ? p.brand : (date == today ? p.brand.withValues(alpha: .5) : p.border)),
                          boxShadow: on ? p.glow(p.brand) : null,
                        ),
                        child: Column(children: [
                          Text(dayShort(i + 1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? Colors.white70 : p.muted)),
                          const SizedBox(height: 2),
                          Text('${date.day}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: on ? Colors.white : p.ink)),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 5,
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              for (final b in has)
                                Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: on ? Colors.white : colorOf[b.id]!.$1),
                                ),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 18),
              SectionTitle(
                '${tr('d$_day')}, ${selected.day} ${tr('m${selected.month}')}',
                trailing: Text(trf('n_classes', {'n': '${dayList.length}'}), style: TextStyle(color: p.brand, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
              const SizedBox(height: 10),
              if (dayList.isEmpty) AppCard(child: EmptyState(icon: Icons.free_breakfast_outlined, text: tr('no_class_this_day'))),
              for (var i = 0; i < dayList.length; i++) ...[
                if (isToday && nowMin < dayList[i].startMin && (i == 0 || nowMin >= dayList[i - 1].endMin)) _NowLine(p: p),
                FadeIn(
                  delay: stagger(i),
                  child: _ClassSlot(
                    b: dayList[i],
                    colors: colorOf[dayList[i].id]!,
                    me: widget.m,
                    live: isToday && nowMin >= dayList[i].startMin && nowMin <= dayList[i].endMin,
                    done: isToday && nowMin > dayList[i].endMin,
                    att: d.$2[dayList[i].id],
                    onMark: widget.m.isStaff
                        ? () async {
                            await push(context, MarkAttendanceScreen(m: widget.m, batch: dayList[i], date: selected));
                            reload();
                          }
                        : null,
                  ),
                ),
              ],
              if (isToday && dayList.isNotEmpty && nowMin > dayList.last.endMin) _NowLine(p: p),
            ],
          );
        },
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine({required this.p});
  final Palette p;
  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(width: 56, child: Text(timeLabel(now.hour * 60 + now.minute), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.danger))),
        Container(width: 10, height: 10, decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle)),
        Expanded(child: Container(height: 2, color: p.danger)),
      ]),
    );
  }
}

class _ClassSlot extends StatelessWidget {
  const _ClassSlot({required this.b, required this.colors, required this.me, required this.live, required this.done, this.att, this.onMark});
  final Batch b;
  final (Color, Color) colors;
  final Membership me;
  final bool live, done;
  final AttendanceDay? att;
  final VoidCallback? onMark;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mins = b.endMin - b.startMin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 56,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(timeLabel(b.startMin).split(' ').first, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text(timeLabel(b.startMin).split(' ').last, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.muted)),
            ]),
          ),
        ),
        Expanded(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: done && att == null && onMark == null ? .6 : 1,
            child: Container(
              constraints: BoxConstraints(minHeight: (60 + mins * .35).clamp(80, 140).toDouble()),
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              decoration: BoxDecoration(
                color: colors.$2,
                borderRadius: BorderRadius.circular(18),
                border: Border(left: BorderSide(color: colors.$1, width: 4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(b.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  if (live) PulseDot(color: p.success),
                ]),
                const SizedBox(height: 3),
                Text('${timeLabel(b.startMin)} – ${timeLabel(b.endMin)} · ${b.teacherUid == me.uid ? tr('you') : b.teacherName}',
                    style: TextStyle(color: p.ink2, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (live) Tag(tr('class_on_now'), fg: Colors.white, bg: p.success),
                  if (att != null)
                    Tag('✓ ${att!.present.length}/${att!.marked.length} ${tr('present')}', fg: p.success, bg: p.card)
                  else if (onMark != null)
                    GestureDetector(onTap: onMark, child: Tag(tr('mark_attendance'), fg: Colors.white, bg: colors.$1, leading: const Icon(Icons.fact_check_outlined, size: 13, color: Colors.white))),
                  Tag(daysCode(b.days), fg: colors.$1, bg: p.card),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
