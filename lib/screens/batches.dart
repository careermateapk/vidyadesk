import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'attendance.dart';
import 'auth.dart';
import 'common.dart';
import 'join.dart';
import 'people.dart';
import 'schedule.dart';

String batchShareText(Batch b, String instituteName) => trf('share_batch_code', {
      'inst': instituteName,
      'batch': b.title,
      'days': daysCode(b.days),
      'time': '${timeLabel(b.startMin)}–${timeLabel(b.endMin)}',
      'code': b.code,
    });

class BatchesPage extends StatefulWidget {
  const BatchesPage({super.key, required this.m});
  final Membership m;
  @override
  State<BatchesPage> createState() => _BatchesPageState();
}

class _BatchesPageState extends State<BatchesPage> {
  int _filter = 0; // all, mine, today, then subjects
  int _v = 0;

  Future<(List<Batch>, List<Membership>)> _load() async {
    final b = context.appRead.backend;
    return (await b.batches(widget.m.instituteId), await b.members(widget.m.instituteId));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return Loader<(List<Batch>, List<Membership>)>(
      key: ValueKey(_v),
      load: _load,
      builder: (context, d, reload) {
        final all = myBatches(m, d.$1);
        final subjects = {for (final b in all) b.subject}.toList()..sort();
        final filters = [tr('all'), if (m.role == Role.admin && m.teaches) tr('mine'), tr('today'), ...subjects];
        final f = _filter.clamp(0, filters.length - 1);
        final now = DateTime.now();
        final label = filters[f];
        final list = all.where((b) {
          if (f == 0) return true;
          if (label == tr('mine')) return b.teacherUid == m.uid;
          if (label == tr('today')) return b.runsOn(now);
          return b.subject == label;
        }).toList();
        Future<void> add() async {
          await push(context, CreateBatchScreen(m: m, members: d.$2));
          setState(() => _v++);
        }

        return Column(children: [
          InnerBar(
            title: tr('nav_batches'),
            subtitle: trf('n_active_batches', {'n': '${all.length}'}),
            showBack: false,
            trailing: IconBtn(icon: Icons.add_rounded, filled: true, tooltip: tr('new_batch'), onTap: add),
          ),
          const SizedBox(height: 6),
          PillBar(items: filters, index: f, onChanged: (v) => setState(() => _filter = v)),
          Expanded(
            child: RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                children: [
                  if (all.isEmpty)
                    AppCard(
                      child: Column(children: [
                        EmptyState(icon: Icons.layers_outlined, text: tr('no_batches_yet')),
                        PrimaryButton(label: tr('new_batch'), icon: Icons.add_rounded, arrow: false, onPressed: add),
                      ]),
                    )
                  else if (list.isEmpty)
                    EmptyState(icon: Icons.filter_alt_off_outlined, text: tr('nothing_here_filter')),
                  for (var i = 0; i < list.length; i++)
                    FadeIn(
                      delay: stagger(i),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: BatchCard(
                          b: list[i],
                          colorIndex: all.indexOf(list[i]),
                          instituteName: m.instituteName,
                          count: approvedStudents(d.$2, batchId: list[i].id).length,
                          mine: list[i].teacherUid == m.uid,
                          onTap: () async {
                            await push(context, BatchDetailScreen(m: m, batch: list[i]));
                            reload();
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class BatchCard extends StatelessWidget {
  const BatchCard({super.key, required this.b, required this.count, required this.mine, required this.onTap, this.colorIndex = 0, this.instituteName = ''});
  final Batch b;
  final int count, colorIndex;
  final bool mine;
  final String instituteName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = batchColors(p, colorIndex);
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBox(Icons.menu_book_outlined, fg: c.$1, bg: c.$2, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.subject, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -.2)),
              Text('${b.className} · ${mine ? tr('you') : b.teacherName}', style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
          Tag(daysCode(b.days), fg: c.$1, bg: c.$2),
        ]),
        const SizedBox(height: 14),
        _WeekStrip(days: b.days, color: c.$1, tint: c.$2),
        const SizedBox(height: 14),
        const Line(),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.schedule_rounded, size: 16, color: p.muted),
          const SizedBox(width: 5),
          Text('${timeLabel(b.startMin)} – ${timeLabel(b.endMin)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.ink2)),
          const SizedBox(width: 14),
          Icon(Icons.groups_outlined, size: 17, color: p.muted),
          const SizedBox(width: 5),
          Text('$count', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.ink2)),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(color: p.cardAlt, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Text(tr('code'), style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Expanded(child: Text(b.code, style: TextStyle(color: p.brand, fontWeight: FontWeight.w800, fontSize: 13.5, letterSpacing: .6))),
            IconButton(visualDensity: VisualDensity.compact, onPressed: () => copyText(context, b.code), icon: Icon(Icons.copy_rounded, size: 17, color: p.muted), tooltip: tr('copy')),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => SharePlus.instance.share(ShareParams(text: batchShareText(b, instituteName))),
              icon: Icon(Icons.share_outlined, size: 17, color: p.muted),
              tooltip: tr('share'),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days, required this.color, required this.tint});
  final List<int> days;
  final Color color, tint;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final today = DateTime.now().weekday;
    return Row(
      children: List.generate(7, (i) {
        final d = i + 1;
        final on = days.contains(d);
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: on ? (d == today ? color : tint) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: d == today && !on ? Border.all(color: p.border) : null,
            ),
            alignment: Alignment.center,
            child: Text(dayShort(d).substring(0, 1),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: on ? (d == today ? Colors.white : color) : p.muted.withValues(alpha: .55))),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Batch details
// ---------------------------------------------------------------------------

class BatchDetailScreen extends StatelessWidget {
  const BatchDetailScreen({super.key, required this.m, required this.batch});
  final Membership m;
  final Batch batch;

  Future<(List<Membership>, List<AttendanceDay>)> _load(BuildContext context) async {
    final b = context.appRead.backend;
    return (await b.members(m.instituteId), await b.attendanceForBatch(m.instituteId, batch.id));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final b = batch;
    return Scaffold(
      appBar: InnerBar(title: b.title),
      body: Loader<(List<Membership>, List<AttendanceDay>)>(
        load: () => _load(context),
        builder: (context, d, reload) {
          final studs = approvedStudents(d.$1, batchId: b.id);
          final days = d.$2;
          var tp = 0, tt = 0;
          for (final a in days) {
            tp += a.present.length;
            tt += a.marked.length;
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
            children: [
              FadeIn(
                child: AppCard(
                  gradient: p.hero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(b.subject, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                          Text('${b.className} · ${b.teacherName}', style: const TextStyle(color: Color(0xCCFFFFFF), fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      Ring(
                        value: tt == 0 ? 0 : tp / tt,
                        size: 70,
                        stroke: 8,
                        color: Colors.white,
                        track: const Color(0x33FFFFFF),
                        center: Text(tt == 0 ? '—' : '${pct(tp, tt)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      Tag(daysCode(b.days), fg: Colors.white, bg: const Color(0x33FFFFFF)),
                      Tag('${timeLabel(b.startMin)} – ${timeLabel(b.endMin)}', fg: Colors.white, bg: const Color(0x33FFFFFF)),
                      Tag('${studs.length} ${tr('students_short')}', fg: Colors.white, bg: const Color(0x33FFFFFF)),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              FadeIn(
                delay: stagger(1),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(tr('batch_code'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(tr('batch_code_sub'), style: TextStyle(color: p.muted, fontSize: 12.5)),
                    const SizedBox(height: 10),
                    CodeBox(code: b.code, big: false),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: SoftButton(label: tr('copy'), icon: Icons.copy_rounded, onPressed: () => copyText(context, b.code))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SoftButton(
                          label: tr('share'),
                          icon: Icons.share_rounded,
                          color: p.successTint,
                          textColor: p.success,
                          onPressed: () => SharePlus.instance.share(ShareParams(text: batchShareText(b, m.instituteName))),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              FadeIn(
                delay: stagger(2),
                child: PrimaryButton(
                  label: tr('mark_attendance'),
                  icon: Icons.fact_check_rounded,
                  onPressed: () async {
                    await push(context, MarkAttendanceScreen(m: m, batch: b));
                    reload();
                  },
                ),
              ),
              const SizedBox(height: 18),
              SectionTitle('${tr('students')} (${studs.length})'),
              const SizedBox(height: 8),
              if (studs.isEmpty) EmptyState(icon: Icons.group_add_rounded, text: tr('no_students_batch')),
              for (var i = 0; i < studs.length; i++)
                FadeIn(
                  delay: stagger(i + 3, stepMs: 40),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _StudentAttRow(s: studs[i], index: i, count: attendanceCount(studs[i].uid, days), onTap: () => push(context, PersonScreen(m: m, person: studs[i]))),
                  ),
                ),
              if (days.isNotEmpty) ...[
                const SizedBox(height: 14),
                SectionTitle(tr('recent_days')),
                const SizedBox(height: 8),
                for (final a in days.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      onTap: () async {
                        await push(context, MarkAttendanceScreen(m: m, batch: b, date: dateFromKey(a.dateKey)));
                        reload();
                      },
                      child: Row(children: [
                        Text(prettyDay(dateFromKey(a.dateKey)), style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('${a.present.length}/${a.marked.length}', style: TextStyle(fontWeight: FontWeight.w800, color: p.success)),
                        const SizedBox(width: 8),
                        SizedBox(width: 60, child: GrowBar(value: a.marked.isEmpty ? 0 : a.present.length / a.marked.length, color: p.success, track: p.successTint)),
                      ]),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StudentAttRow extends StatelessWidget {
  const _StudentAttRow({required this.s, required this.index, required this.count, required this.onTap});
  final Membership s;
  final int index;
  final ({int present, int total}) count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final v = pct(count.present, count.total);
    final c = count.total == 0 ? p.muted : (v >= 75 ? p.success : (v >= 50 ? p.warn : p.danger));
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Avatar(s.name, size: 40, index: index, photo: s.photo),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(s.studentCode, style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        Text(count.total == 0 ? '—' : '$v%', style: TextStyle(fontWeight: FontWeight.w800, color: c)),
        if (count.total > 0 && v < 60) ...[const SizedBox(width: 6), Icon(Icons.warning_amber_rounded, color: p.danger, size: 18)],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Create batch
// ---------------------------------------------------------------------------

class CreateBatchScreen extends StatefulWidget {
  const CreateBatchScreen({super.key, required this.m, required this.members});
  final Membership m;
  final List<Membership> members;
  @override
  State<CreateBatchScreen> createState() => _CreateBatchScreenState();
}

class _CreateBatchScreenState extends State<CreateBatchScreen> {
  late final _subject = TextEditingController(text: widget.m.subjects.isNotEmpty ? widget.m.subjects.first : '');
  final _class = TextEditingController();
  List<int> _days = [2, 4, 6];
  String _preset = 'TTS';
  TimeOfDay _start = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 18, minute: 0);
  late String _teacherUid = widget.m.canTeach ? widget.m.uid : '';
  bool _busy = false;
  String? _error;

  static const _presets = {
    'MWF': [1, 3, 5],
    'TTS': [2, 4, 6],
    'Mon–Sat': [1, 2, 3, 4, 5, 6],
    'Daily': [1, 2, 3, 4, 5, 6, 7],
  };

  List<Membership> get _teachers {
    final list = widget.members.where((x) => x.approved && x.canTeach).toList();
    if (widget.m.role != Role.admin) return list.where((x) => x.uid == widget.m.uid).toList();
    return list;
  }

  @override
  void dispose() {
    _subject.dispose();
    _class.dispose();
    super.dispose();
  }

  int _min(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickTime(bool start) async {
    final t = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (t == null) return;
    setState(() {
      if (start) {
        _start = t;
        if (_min(_end) <= _min(t)) _end = TimeOfDay(hour: (t.hour + 1) % 24, minute: t.minute);
      } else {
        _end = t;
      }
    });
  }

  Future<void> _create() async {
    final app = context.appRead;
    if (_subject.text.trim().isEmpty) return _err(tr('err_subject'));
    if (_class.text.trim().isEmpty) return _err(tr('err_class'));
    if (_days.isEmpty) return _err(tr('err_days'));
    if (_min(_end) <= _min(_start)) return _err(tr('err_time'));
    final teacher = _teachers.where((t) => t.uid == _teacherUid).firstOrNull ?? (widget.m.canTeach ? widget.m : null);
    if (teacher == null) return _err(tr('err_pick_teacher'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final b = await app.backend.createBatch(
        instituteId: widget.m.instituteId,
        instituteName: widget.m.instituteName,
        subject: _subject.text.trim(),
        className: _class.text.trim(),
        days: _days,
        startMin: _min(_start),
        endMin: _min(_end),
        teacherUid: teacher.uid,
        teacherName: teacher.name,
      );
      if (!mounted) return;
      await showCodeSheet(context, title: tr('batch_ready'), sub: tr('batch_ready_sub'), code: b.code, shareText: batchShareText(b, widget.m.instituteName));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _err(errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _err(String s) => setState(() => _error = s);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    var i = 0;
    Widget item(Widget w) => FadeIn(delay: stagger(i++, stepMs: 45), child: Padding(padding: const EdgeInsets.only(bottom: 16), child: w));
    final teachers = _teachers;
    return Scaffold(
      appBar: InnerBar(title: tr('new_batch')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
        children: [
          item(Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FieldLabel(tr('subject')),
                TextField(controller: _subject, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Economics')),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FieldLabel(tr('class')),
                TextField(controller: _class, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Class 12')),
              ]),
            ),
          ])),
          if (widget.m.subjects.length > 1)
            item(Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in widget.m.subjects) ActionChip(label: Text(s), onPressed: () => setState(() => _subject.text = s)),
            ])),
          item(AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconBox(Icons.calendar_month_rounded, fg: p.indigo, bg: p.indigoTint),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('class_days'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Tag(_days.isEmpty ? '—' : daysCode(_days), key: ValueKey(daysCode(_days)), fg: p.indigo, bg: p.indigoTint),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in _presets.entries)
                  ChoicePill(
                    label: e.key,
                    sub: tr('preset_${e.key == 'Mon–Sat' ? 'monsat' : e.key.toLowerCase()}'),
                    selected: _preset == e.key,
                    onTap: () => setState(() {
                      _preset = e.key;
                      _days = [...e.value];
                    }),
                  ),
                ChoicePill(label: tr('custom'), sub: tr('preset_custom'), selected: _preset == 'custom', onTap: () => setState(() => _preset = 'custom')),
              ]),
              const SizedBox(height: 14),
              DayPicker(
                selected: _days,
                onChanged: (v) => setState(() {
                  _days = v;
                  _preset = _presets.entries.where((e) => e.value.join(',') == v.join(',')).map((e) => e.key).firstOrNull ?? 'custom';
                }),
              ),
            ]),
          )),
          item(Row(children: [
            Expanded(child: _TimeBox(label: tr('starts'), value: timeLabel(_min(_start)), onTap: () => _pickTime(true))),
            const SizedBox(width: 10),
            Expanded(child: _TimeBox(label: tr('ends'), value: timeLabel(_min(_end)), onTap: () => _pickTime(false))),
          ])),
          if (widget.m.role == Role.admin)
            item(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel(tr('who_teaches')),
              if (teachers.isEmpty)
                Text(tr('no_teachers_yet'), style: TextStyle(color: p.muted, fontSize: 13))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in teachers)
                    ChoicePill(label: t.uid == widget.m.uid ? '${t.name} (${tr('you')})' : t.name, selected: _teacherUid == t.uid, onTap: () => setState(() => _teacherUid = t.uid)),
                ]),
            ])),
          item(AppCard(
            color: p.cardAlt,
            child: Row(children: [
              Icon(Icons.key_rounded, color: p.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(tr('batch_code_auto'), style: TextStyle(color: p.muted, fontSize: 13, height: 1.35))),
            ]),
          )),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: p.danger, fontWeight: FontWeight.w700))),
          PrimaryButton(label: tr('create_batch'), busy: _busy, onPressed: _create),
        ],
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.label, required this.value, required this.onTap});
  final String label, value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldLabel(label),
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
          child: Row(children: [
            Icon(Icons.schedule_rounded, color: p.brand, size: 20),
            const SizedBox(width: 8),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
        ),
      ),
    ]);
  }
}
