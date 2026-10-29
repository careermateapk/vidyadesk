import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// Chapters of a batch: staff tick them off, students and parents see progress.
class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key, required this.m, this.batchIds});
  final Membership m;

  /// For parents: the child's batches.
  final List<String>? batchIds;
  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  String? _batch;
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return AppScaffold(
      title: tr('syllabus_tracker'),
      subtitle: m.instituteName,
      body: Loader<List<Batch>>(
        load: () async {
          final all = await context.appRead.backend.batches(m.instituteId);
          return switch (m.role) {
            Role.admin => all,
            Role.teacher => myBatches(m, all),
            Role.student => all.where((b) => m.batchIds.contains(b.id)).toList(),
            Role.parent => widget.batchIds == null ? all : all.where((b) => widget.batchIds!.contains(b.id)).toList(),
          };
        },
        builder: (context, batches, _) {
          if (batches.isEmpty) return ListView(children: [EmptyState(icon: Icons.menu_book_outlined, text: tr('no_batch_joined'))]);
          final id = batches.any((b) => b.id == _batch) ? _batch! : batches.first.id;
          final batch = batches.firstWhere((b) => b.id == id);
          return Column(children: [
            if (batches.length > 1)
              PillBar(items: batches.map((b) => b.title).toList(), index: batches.indexOf(batch), onChanged: (i) => setState(() => _batch = batches[i].id)),
            Expanded(child: _BatchSyllabus(key: ValueKey('$id-$_v'), m: m, batch: batch, onChanged: () => setState(() => _v++))),
          ]);
        },
      ),
    );
  }
}

class _BatchSyllabus extends StatelessWidget {
  const _BatchSyllabus({super.key, required this.m, required this.batch, required this.onChanged});
  final Membership m;
  final Batch batch;
  final VoidCallback onChanged;

  bool get _canEdit => m.role == Role.admin || batch.teacherUid == m.uid;

  Future<void> _save(BuildContext context, Syllabus s) async {
    s.updatedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      await context.appRead.backend.saveSyllabus(m.instituteId, s);
    } catch (e) {
      if (context.mounted) toast(context, errorMessage(e));
    }
    onChanged();
  }

  Future<void> _addChapters(BuildContext context, Syllabus s) async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('add_chapters')),
        content: TextField(controller: c, autofocus: true, minLines: 3, maxLines: 8, decoration: InputDecoration(hintText: tr('chapters_hint'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, c.text), child: Text(tr('add'))),
        ],
      ),
    );
    c.dispose();
    final names = (text ?? '').split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    if (names.isEmpty || !context.mounted) return;
    s.chapters.addAll(names.map((n) => Chapter(name: n)));
    await _save(context, s);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Loader<Syllabus?>(
      load: () => context.appRead.backend.syllabus(m.instituteId, batch.id),
      builder: (context, data, reload) {
        final s = data ?? Syllabus(batchId: batch.id);
        final done = s.done, total = s.chapters.length;
        final next = s.chapters.where((c) => !c.done).firstOrNull;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            FadeIn(
              child: FeatureCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                 Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(batch.title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .4)),
                      const SizedBox(height: 4),
                      Text(total == 0 ? tr('no_chapters') : trf('n_of_m_chapters', {'n': '$done', 'm': '$total'}), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Ring(
                    value: s.progress,
                    size: 76,
                    stroke: 8,
                    color: Colors.white,
                    track: Colors.white24,
                    center: Text('${(s.progress * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                 ]),
                 if (next != null) ...[
                   const SizedBox(height: 14),
                   Container(
                     padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                     decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
                     child: Row(children: [
                       Container(
                         width: 32,
                         height: 32,
                         decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                         child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF4B3FC4), size: 20),
                       ),
                       const SizedBox(width: 10),
                       Expanded(
                         child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                           Text(tr('now_teaching').toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800)),
                           Text(next.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, height: 1.25)),
                         ]),
                       ),
                     ]),
                   ),
                 ],
                ]),
              ),
            ),
            const SizedBox(height: 14),
            if (total == 0) EmptyState(icon: Icons.checklist_rounded, text: _canEdit ? tr('add_chapters_tip') : tr('syllabus_soon')),
            for (var i = 0; i < s.chapters.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
                  child: Row(children: [
                    Checkbox(
                      value: s.chapters[i].done,
                      activeColor: p.success,
                      onChanged: !_canEdit
                          ? null
                          : (v) {
                              s.chapters[i]
                                ..done = v == true
                                ..doneAt = v == true ? DateTime.now().millisecondsSinceEpoch : 0;
                              _save(context, s);
                            },
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.chapters[i].name,
                            style: TextStyle(fontWeight: FontWeight.w700, color: s.chapters[i].done ? p.muted : p.ink, decoration: s.chapters[i].done ? TextDecoration.lineThrough : null)),
                        if (s.chapters[i].done && s.chapters[i].doneAt > 0)
                          Text('${tr('finished_on')} ${prettyDate(DateTime.fromMillisecondsSinceEpoch(s.chapters[i].doneAt))}', style: TextStyle(color: p.success, fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    if (_canEdit)
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded, color: p.muted, size: 20),
                        onSelected: (v) {
                          if (v == 'up' && i > 0) {
                            final c = s.chapters.removeAt(i);
                            s.chapters.insert(i - 1, c);
                          } else if (v == 'del') {
                            s.chapters.removeAt(i);
                          }
                          _save(context, s);
                        },
                        itemBuilder: (_) => [
                          if (i > 0) PopupMenuItem(value: 'up', child: Text(tr('move_up'))),
                          PopupMenuItem(value: 'del', child: Text(tr('delete'), style: TextStyle(color: p.danger))),
                        ],
                      ),
                  ]),
                ),
              ),
            if (_canEdit) ...[
              const SizedBox(height: 8),
              SoftButton(label: tr('add_chapters'), icon: Icons.add_rounded, onPressed: () => _addChapters(context, s)),
            ],
          ],
        );
      },
    );
  }
}
