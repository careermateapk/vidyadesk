import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'resources.dart' show learnerUid, learnerName;

String fmtMarks(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

Color gradeColor(Palette p, int percent) => percent >= 75 ? p.success : (percent >= 50 ? p.warn : p.danger);

// ---------------------------------------------------------------------------
// Entry point: staff see tests to manage, learners see results
// ---------------------------------------------------------------------------

class TestsPage extends StatelessWidget {
  const TestsPage({super.key, required this.m});
  final Membership m;
  @override
  Widget build(BuildContext context) => m.isStaff ? _StaffTests(m: m) : _Results(m: m);
}

class _StaffTests extends StatefulWidget {
  const _StaffTests({required this.m});
  final Membership m;
  @override
  State<_StaffTests> createState() => _StaffTestsState();
}

class _StaffTestsState extends State<_StaffTests> {
  String _batch = '';
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = widget.m;
    return AppScaffold(
      title: tr('tests_results'),
      subtitle: m.instituteName,
      body: Loader<(List<TestPaper>, List<Batch>, List<Membership>)>(
        key: ValueKey(_v),
        load: () async {
          final b = context.appRead.backend;
          return (await b.tests(m.instituteId), await b.batches(m.instituteId), await b.members(m.instituteId));
        },
        builder: (context, d, reload) {
          final mine = myBatches(m, d.$2);
          final ids = mine.map((b) => b.id).toSet();
          var list = d.$1.where((t) => ids.contains(t.batchId)).toList()..sort((a, b) => b.date.compareTo(a.date));
          if (_batch.isNotEmpty) list = list.where((t) => t.batchId == _batch).toList();
          final batches = {for (final b in d.$2) b.id: b};
          return Column(children: [
            if (mine.length > 1)
              PillBar(
                items: [tr('all'), ...mine.map((b) => b.title)],
                index: _batch.isEmpty ? 0 : mine.indexWhere((b) => b.id == _batch) + 1,
                onChanged: (i) => setState(() => _batch = i == 0 ? '' : mine[i - 1].id),
              ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                children: [
                  if (list.isEmpty) EmptyState(icon: Icons.quiz_outlined, text: tr('no_tests_staff')),
                  for (var i = 0; i < list.length; i++)
                    FadeIn(
                      delay: stagger(i),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Builder(builder: (context) {
                          final t = list[i];
                          final total = approvedStudents(d.$3, batchId: t.batchId).length;
                          final avg = t.average;
                          final avgPct = avg == null ? null : (avg * 100 / t.maxMarks).round();
                          return AppCard(
                            onTap: () async {
                              final ok = await push<bool>(context, MarksEntryScreen(m: m, test: t, batch: batches[t.batchId]));
                              if (ok == true) setState(() => _v++);
                            },
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                IconBox(Icons.quiz_rounded, fg: p.brand, bg: p.brandTint),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                    Text('${batches[t.batchId]?.title ?? ''} · ${prettyDate(DateTime.fromMillisecondsSinceEpoch(t.date))}',
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
                                  ]),
                                ),
                                Tag(t.published ? tr('published') : tr('draft'), fg: t.published ? p.success : p.warn, bg: t.published ? p.successTint : p.warnTint),
                              ]),
                              const SizedBox(height: 12),
                              Row(children: [
                                _mini(p, tr('marks_entered'), '${t.marks.length}/$total'),
                                _mini(p, tr('class_avg'), avgPct == null ? '—' : '$avgPct%'),
                                _mini(p, tr('highest'), t.highest == null ? '—' : '${fmtMarks(t.highest!)}/${t.maxMarks}'),
                              ]),
                            ]),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ]);
        },
      ),
      bottom: Builder(
        builder: (context) => PrimaryButton(
          label: tr('new_test'),
          icon: Icons.add_rounded,
          arrow: false,
          onPressed: () async {
            final b = context.appRead.backend;
            final batches = myBatches(m, await b.batches(m.instituteId));
            if (!context.mounted) return;
            if (batches.isEmpty) {
              toast(context, tr('need_batch_first'));
              return;
            }
            final t = await showModalBottomSheet<TestPaper>(context: context, isScrollControlled: true, builder: (_) => _NewTestSheet(m: m, batches: batches));
            if (t == null || !context.mounted) return;
            await push<bool>(context, MarksEntryScreen(m: m, test: t, batch: batches.where((x) => x.id == t.batchId).firstOrNull));
            setState(() => _v++);
          },
        ),
      ),
    );
  }

  Widget _mini(Palette p, String label, String value) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(color: p.cardAlt, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _NewTestSheet extends StatefulWidget {
  const _NewTestSheet({required this.m, required this.batches});
  final Membership m;
  final List<Batch> batches;
  @override
  State<_NewTestSheet> createState() => _NewTestSheetState();
}

class _NewTestSheetState extends State<_NewTestSheet> {
  final _title = TextEditingController();
  final _max = TextEditingController(text: '100');
  late String _batch = widget.batches.first.id;
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    final max = int.tryParse(_max.text.trim()) ?? 0;
    if (title.length < 2) {
      toast(context, tr('err_title'));
      return;
    }
    if (max <= 0 || max > 1000) {
      toast(context, tr('err_max_marks'));
      return;
    }
    setState(() => _busy = true);
    try {
      final app = context.appRead;
      final b = widget.batches.firstWhere((x) => x.id == _batch);
      final t = TestPaper(
        id: newId(),
        batchId: _batch,
        title: title,
        subject: b.subject,
        maxMarks: max,
        date: DateTime(_date.year, _date.month, _date.day).millisecondsSinceEpoch,
        byName: app.profile?.name ?? widget.m.name,
      );
      await app.backend.saveTest(widget.m.instituteId, t);
      if (mounted) Navigator.of(context).pop(t);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('new_test'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FieldLabel(tr('test_name')),
          TextField(controller: _title, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: tr('test_name_hint'))),
          const SizedBox(height: 12),
          FieldLabel(tr('batch')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in widget.batches) ChoicePill(label: b.title, selected: _batch == b.id, onTap: () => setState(() => _batch = b.id)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FieldLabel(tr('max_marks')),
                TextField(controller: _max, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FieldLabel(tr('test_date')),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 365)), lastDate: now.add(const Duration(days: 60)), initialDate: _date);
                    if (d != null) setState(() => _date = d);
                  },
                  child: Row(children: [
                    Icon(Icons.event_rounded, size: 18, color: p.brand),
                    const SizedBox(width: 6),
                    Expanded(child: Text(prettyDate(_date), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          PrimaryButton(label: tr('next_enter_marks'), busy: _busy, onPressed: _create),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marks entry
// ---------------------------------------------------------------------------

class MarksEntryScreen extends StatefulWidget {
  const MarksEntryScreen({super.key, required this.m, required this.test, this.batch});
  final Membership m;
  final TestPaper test;
  final Batch? batch;
  @override
  State<MarksEntryScreen> createState() => _MarksEntryScreenState();
}

class _MarksEntryScreenState extends State<MarksEntryScreen> {
  final Map<String, TextEditingController> _c = {};
  List<Membership>? _students;
  late bool _published = widget.test.published;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final members = await context.appRead.backend.members(widget.m.instituteId);
      final s = approvedStudents(members, batchId: widget.test.batchId);
      for (final x in s) {
        final v = widget.test.marks[x.uid];
        _c[x.uid] = TextEditingController(text: v == null ? '' : fmtMarks(v));
      }
      if (mounted) setState(() => _students = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool? publish}) async {
    final t = widget.test;
    final marks = <String, double>{};
    for (final e in _c.entries) {
      final txt = e.value.text.trim();
      if (txt.isEmpty) continue;
      final v = double.tryParse(txt);
      if (v == null || v < 0 || v > t.maxMarks) {
        final name = _students?.where((s) => s.uid == e.key).firstOrNull?.name ?? '';
        toast(context, trf('err_marks_for', {'name': name, 'max': '${t.maxMarks}'}));
        return;
      }
      marks[e.key] = v;
    }
    setState(() => _busy = true);
    try {
      t.marks
        ..clear()
        ..addAll(marks);
      if (publish != null) t.published = publish;
      await context.appRead.backend.saveTest(widget.m.instituteId, t);
      if (!mounted) return;
      setState(() => _published = t.published);
      toast(context, publish == true ? tr('results_published') : tr('saved'));
      if (publish == true) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final p = context.pal;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('delete_test_q')),
        content: Text(widget.test.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('delete'), style: TextStyle(color: p.danger))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await context.appRead.backend.deleteTest(widget.m.instituteId, widget.test.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final t = widget.test;
    final s = _students;
    return AppScaffold(
      title: t.title,
      subtitle: '${widget.batch?.title ?? ''} · ${tr('out_of')} ${t.maxMarks}',
      actions: [IconBtn(icon: Icons.delete_outline_rounded, color: p.danger, tooltip: tr('delete'), onTap: _delete)],
      body: _error != null
          ? ErrorView(error: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          : s == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
                  AppCard(
                    color: _published ? p.successTint : p.warnTint,
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(_published ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: _published ? p.success : p.warn),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_published ? tr('published_note') : tr('draft_note'), style: TextStyle(fontWeight: FontWeight.w700, color: _published ? p.success : p.warn, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (s.isEmpty) EmptyState(icon: Icons.groups_outlined, text: tr('no_students_batch')),
                  for (var i = 0; i < s.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Row(children: [
                          Avatar(s[i].name, size: 38, photo: s[i].photo),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                          SizedBox(
                            width: 84,
                            child: TextField(
                              controller: _c[s[i].uid],
                              textAlign: TextAlign.center,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textInputAction: i == s.length - 1 ? TextInputAction.done : TextInputAction.next,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                              decoration: InputDecoration(hintText: '—', suffixText: '/${t.maxMarks}', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                ]),
      bottom: s == null
          ? null
          : Row(children: [
              Expanded(child: SoftButton(label: tr('save_draft'), onPressed: _busy ? null : () => _save())),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  label: _published ? tr('update') : tr('publish'),
                  icon: Icons.campaign_rounded,
                  arrow: false,
                  busy: _busy,
                  onPressed: () => _save(publish: true),
                ),
              ),
            ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Learner results
// ---------------------------------------------------------------------------

class _Results extends StatelessWidget {
  const _Results({required this.m});
  final Membership m;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final uid = learnerUid(context, m);
    final name = learnerName(context, m);
    return AppScaffold(
      title: m.role == Role.parent ? '${tr('results')} · ${firstName(name)}' : tr('my_results'),
      subtitle: m.instituteName,
      body: Loader<(List<TestPaper>, List<Batch>)>(
        load: () async {
          final b = context.appRead.backend;
          return (await b.tests(m.instituteId, publishedOnly: true), await b.batches(m.instituteId));
        },
        builder: (context, d, reload) {
          final mine = d.$1.where((t) => t.marks.containsKey(uid)).toList()..sort((a, b) => b.date.compareTo(a.date));
          final batches = {for (final b in d.$2) b.id: b};
          if (mine.isEmpty) {
            return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [EmptyState(icon: Icons.emoji_events_outlined, text: tr('no_results'))]);
          }
          final pcts = [for (final t in mine) (t.marks[uid]! * 100 / t.maxMarks).round()];
          final avg = (pcts.reduce((a, b) => a + b) / pcts.length).round();
          final best = pcts.reduce((a, b) => a > b ? a : b);
          final chart = mine.take(6).toList().reversed.toList();
          final chartVals = [for (final t in chart) (t.marks[uid]! * 100 / t.maxMarks).round()];
          final trend = chartVals.length >= 2 ? chartVals.last - chartVals[chartVals.length - 2] : 0;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
            children: [
              FadeIn(
                child: FeatureCard(
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('overall_score').toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .5)),
                        const SizedBox(height: 4),
                        CountUp(avg, suffix: '%', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          GlassChip(trf('n_tests', {'n': '${mine.length}'}), icon: Icons.quiz_outlined),
                          GlassChip('${tr('best')} $best%', icon: Icons.emoji_events_outlined),
                          if (trend != 0) GlassChip('${trend > 0 ? '+' : ''}$trend%', icon: trend > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded),
                        ]),
                      ]),
                    ),
                    Ring(
                      value: avg / 100,
                      size: 74,
                      stroke: 8,
                      color: Colors.white,
                      track: Colors.white24,
                      center: const Icon(Icons.school_rounded, color: Colors.white),
                    ),
                  ]),
                ),
              ),
              if (chart.length >= 2) ...[
                const SizedBox(height: 14),
                FadeIn(
                  delay: stagger(1),
                  child: AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('progress'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 10),
                      BarChart(values: chartVals, labels: [for (var i = 0; i < chart.length; i++) 'T${mine.length - chart.length + i + 1}'], highlight: chart.length - 1),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SectionTitle(tr('all_tests')),
              const SizedBox(height: 6),
              for (var i = 0; i < mine.length; i++)
                FadeIn(
                  delay: stagger(i + 2),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Builder(builder: (context) {
                      final t = mine[i];
                      final my = t.marks[uid]!;
                      final pc = pcts[i];
                      final col = gradeColor(p, pc);
                      final rank = t.rankOf(uid);
                      final avgT = t.average;
                      return AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Ring(
                              value: pc / 100,
                              size: 54,
                              stroke: 6,
                              color: col,
                              track: col.withValues(alpha: .15),
                              center: Text('$pc%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: col)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                Text('${batches[t.batchId]?.subject ?? t.subject} · ${prettyDate(DateTime.fromMillisecondsSinceEpoch(t.date))}',
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
                              ]),
                            ),
                            Text('${fmtMarks(my)}/${t.maxMarks}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: col)),
                          ]),
                          const SizedBox(height: 10),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            if (rank > 0) Tag(trf('rank_of', {'r': '$rank', 'n': '${t.marks.length}'}), fg: p.brand, bg: p.brandTint, leading: Icon(Icons.emoji_events_rounded, size: 13, color: p.brand)),
                            if (avgT != null) Tag('${tr('class_avg')} ${fmtMarks(avgT)}', fg: p.indigo, bg: p.indigoTint),
                            if (t.highest != null) Tag('${tr('highest')} ${fmtMarks(t.highest!)}', fg: p.success, bg: p.successTint),
                          ]),
                        ]),
                      );
                    }),
                  ),
                ),
              const SizedBox(height: 6),
              SoftButton(
                label: tr('share_results'),
                icon: Icons.share_rounded,
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: '📊 ${m.instituteName} — $name\n${[for (var i = 0; i < mine.length; i++) '• ${mine[i].title}: ${fmtMarks(mine[i].marks[uid]!)}/${mine[i].maxMarks} (${pcts[i]}%)'].join('\n')}\n${tr('overall_score')}: $avg%',
                )),
              ),
            ],
          );
        },
      ),
    );
  }
}
