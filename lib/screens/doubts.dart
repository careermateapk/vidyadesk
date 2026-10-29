import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../services/push.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'notices.dart' show ago;
import 'resources.dart' show learnerUid;
import 'viewers.dart';

(String, Color, Color) doubtStatus(Palette p, Doubt d) {
  if (d.solved) return (tr('solved'), p.success, p.successTint);
  if (d.answered) return (tr('answered'), p.indigo, p.indigoTint);
  return (tr('open'), p.warn, p.warnTint);
}

class DoubtsPage extends StatefulWidget {
  const DoubtsPage({super.key, required this.m});
  final Membership m;
  @override
  State<DoubtsPage> createState() => _DoubtsPageState();
}

class _DoubtsPageState extends State<DoubtsPage> {
  int _tab = 0;
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = widget.m;
    final staff = m.isStaff;
    final student = m.role == Role.student;
    final uid = learnerUid(context, m);
    return AppScaffold(
      title: tr('doubt_box'),
      subtitle: staff ? tr('doubt_box_staff_sub') : tr('doubt_box_sub'),
      body: Loader<(List<Doubt>, List<Batch>)>(
        key: ValueKey(_v),
        load: () async {
          final b = context.appRead.backend;
          return (await b.doubts(m.instituteId, studentUid: staff ? null : uid), await b.batches(m.instituteId));
        },
        builder: (context, d, reload) {
          var list = d.$1;
          if (m.role == Role.teacher) {
            final mine = myBatches(m, d.$2).map((b) => b.id).toSet();
            list = list.where((x) => mine.contains(x.batchId)).toList();
          }
          final open = list.where((x) => !x.solved && !x.answered).toList();
          final answered = list.where((x) => !x.solved && x.answered).toList();
          final solved = list.where((x) => x.solved).toList();
          final shown = staff ? [open, answered, solved][_tab] : list;
          final batches = {for (final b in d.$2) b.id: b};
          return Column(children: [
            if (staff)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
                child: Segmented(
                  items: ['${tr('open')} (${open.length})', '${tr('answered')} (${answered.length})', '${tr('solved')} (${solved.length})'],
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
                children: [
                  if (shown.isEmpty) EmptyState(icon: Icons.forum_outlined, text: staff ? tr('no_doubts_staff') : (student ? tr('no_doubts') : tr('no_doubts_child'))),
                  for (var i = 0; i < shown.length; i++)
                    FadeIn(
                      delay: stagger(i),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Builder(builder: (context) {
                          final x = shown[i];
                          final st = doubtStatus(p, x);
                          return AppCard(
                            onTap: () async {
                              await push(context, DoubtThreadScreen(m: m, doubt: x, batch: batches[x.batchId]));
                              setState(() => _v++);
                            },
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                if (staff) ...[Avatar(x.studentName, size: 34), const SizedBox(width: 10)],
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(staff ? x.studentName : x.subject, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    Text('${staff ? '${x.subject} · ' : ''}${ago(x.lastAt)}', style: TextStyle(color: p.muted, fontSize: 12)),
                                  ]),
                                ),
                                Tag(st.$1, fg: st.$2, bg: st.$3),
                              ]),
                              const SizedBox(height: 8),
                              Text(x.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink2, height: 1.4)),
                              if (x.replies.isNotEmpty || x.image.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(children: [
                                  if (x.image.isNotEmpty) ...[Icon(Icons.image_outlined, size: 15, color: p.muted), const SizedBox(width: 10)],
                                  if (x.replies.isNotEmpty) ...[
                                    Icon(Icons.chat_bubble_outline_rounded, size: 15, color: p.muted),
                                    const SizedBox(width: 4),
                                    Text('${x.replies.length}', style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ]),
                              ],
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
      bottom: student
          ? Builder(
              builder: (context) => PrimaryButton(
                label: tr('ask_doubt'),
                icon: Icons.add_comment_rounded,
                arrow: false,
                onPressed: () async {
                  final ok = await push<bool>(context, AskDoubtScreen(m: m));
                  if (ok == true) setState(() => _v++);
                },
              ),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Ask
// ---------------------------------------------------------------------------

class AskDoubtScreen extends StatefulWidget {
  const AskDoubtScreen({super.key, required this.m});
  final Membership m;
  @override
  State<AskDoubtScreen> createState() => _AskDoubtScreenState();
}

class _AskDoubtScreenState extends State<AskDoubtScreen> {
  final _text = TextEditingController();
  String _batch = '';
  String _photo = '';
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(List<Batch> batches) async {
    final app = context.appRead;
    final text = _text.text.trim();
    final b = batches.where((x) => x.id == _batch).firstOrNull ?? batches.firstOrNull;
    if (b == null) {
      toast(context, tr('no_batch_joined'));
      return;
    }
    if (text.length < 3 && _photo.isEmpty) {
      toast(context, tr('err_doubt_empty'));
      return;
    }
    setState(() => _busy = true);
    try {
      await app.backend.saveDoubt(
        widget.m.instituteId,
        Doubt(
          id: newId(),
          batchId: b.id,
          subject: b.subject,
          studentUid: widget.m.uid,
          studentName: app.profile?.name ?? widget.m.name,
          text: text,
          image: _photo,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      Push.send(inst: widget.m.instituteId, kind: 'doubt', title: '❓ ${trf('new_doubt_from', {'name': app.profile?.name ?? widget.m.name})}', body: '${b.subject}: $text', topics: [Push.staff(widget.m.instituteId)]);
      if (!mounted) return;
      toast(context, tr('doubt_sent'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = widget.m;
    return AppScaffold(
      title: tr('ask_doubt'),
      body: Loader<List<Batch>>(
        load: () async => (await context.appRead.backend.batches(m.instituteId)).where((b) => m.batchIds.contains(b.id)).toList(),
        builder: (context, batches, _) {
          if (_batch.isEmpty && batches.isNotEmpty) _batch = batches.first.id;
          return ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
            FieldLabel(tr('which_subject')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in batches) ChoicePill(label: b.subject, sub: b.teacherName, selected: _batch == b.id, onTap: () => setState(() => _batch = b.id)),
            ]),
            const SizedBox(height: 14),
            FieldLabel(tr('your_doubt')),
            TextField(controller: _text, minLines: 4, maxLines: 10, maxLength: 1000, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: tr('doubt_hint'))),
            FieldLabel(tr('add_photo_question')),
            Row(children: [
              if (_photo.isNotEmpty)
                PhotoThumb(_photo, size: 90, onRemove: () => setState(() => _photo = ''))
              else
                GestureDetector(
                  onTap: () async {
                    final got = await pickPhotos(context, max: 1);
                    if (got.isNotEmpty) setState(() => _photo = got.first);
                  },
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(color: p.brandTint, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.brand.withValues(alpha: .35))),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_a_photo_outlined, color: p.brand),
                      const SizedBox(height: 4),
                      Text(tr('photo'), style: TextStyle(color: p.brand, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(child: Text(tr('photo_question_tip'), style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4))),
            ]),
            const SizedBox(height: 24),
            PrimaryButton(label: tr('send_doubt'), icon: Icons.send_rounded, arrow: false, busy: _busy, onPressed: () => _send(batches)),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thread
// ---------------------------------------------------------------------------

class DoubtThreadScreen extends StatefulWidget {
  const DoubtThreadScreen({super.key, required this.m, required this.doubt, this.batch});
  final Membership m;
  final Doubt doubt;
  final Batch? batch;
  @override
  State<DoubtThreadScreen> createState() => _DoubtThreadScreenState();
}

class _DoubtThreadScreenState extends State<DoubtThreadScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  String _photo = '';
  bool _busy = false;

  Doubt get d => widget.doubt;
  bool get _canWrite => widget.m.isStaff || (widget.m.role == Role.student && d.studentUid == widget.m.uid);

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.appRead.backend.saveDoubt(widget.m.instituteId, d);
  }

  Future<void> _reply() async {
    final text = _text.text.trim();
    if (text.isEmpty && _photo.isEmpty) return;
    final app = context.appRead;
    setState(() => _busy = true);
    final r = DoubtReply(
      byUid: widget.m.uid,
      byName: app.profile?.name ?? widget.m.name,
      text: text,
      at: DateTime.now().millisecondsSinceEpoch,
      staff: widget.m.isStaff,
      image: _photo,
    );
    try {
      d.replies.add(r);
      if (!widget.m.isStaff) d.solved = false;
      await _save();
      final i = widget.m.instituteId;
      Push.send(
        inst: i,
        kind: widget.m.isStaff ? 'doubt_reply' : 'doubt',
        title: widget.m.isStaff ? '💬 ${trf('teacher_replied', {'name': r.byName})}' : '❓ ${trf('new_doubt_from', {'name': r.byName})}',
        body: text.isEmpty ? d.subject : text,
        topics: [widget.m.isStaff ? Push.person(i, d.studentUid) : Push.staff(i)],
      );
      _text.clear();
      _photo = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      });
    } catch (e) {
      d.replies.remove(r);
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleSolved() async {
    setState(() => d.solved = !d.solved);
    try {
      await _save();
      if (mounted) toast(context, d.solved ? tr('marked_solved') : tr('reopened'));
    } catch (e) {
      setState(() => d.solved = !d.solved);
      if (mounted) toast(context, errorMessage(e));
    }
  }

  Widget _bubble(Palette p, {required bool mine, required bool staff, required String name, required String text, required String image, required int at}) {
    final bg = mine ? p.brand : p.card;
    final fg = mine ? Colors.white : p.ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
            boxShadow: mine ? null : p.shadow,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: mine ? Colors.white70 : p.brand))),
              if (staff) ...[const SizedBox(width: 4), Icon(Icons.verified_rounded, size: 14, color: mine ? Colors.white70 : p.brand)],
            ]),
            if (image.isNotEmpty) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => push(context, PhotoViewerScreen(images: [image])),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Builder(builder: (_) {
                    final b = Avatar.bytesOf(image);
                    return b == null ? const SizedBox(height: 60) : Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
                  }),
                ),
              ),
            ],
            if (text.isNotEmpty) ...[const SizedBox(height: 4), SelectableText(text, style: TextStyle(color: fg, height: 1.4, fontSize: 14.5))],
            const SizedBox(height: 4),
            Text(ago(at), style: TextStyle(color: mine ? Colors.white60 : p.muted, fontSize: 10.5)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final me = widget.m.uid;
    final st = doubtStatus(p, d);
    final canSolve = widget.m.isStaff || d.studentUid == me;
    return AppScaffold(
      title: d.subject,
      subtitle: '${d.studentName}${widget.batch == null ? '' : ' · ${widget.batch!.title}'}',
      actions: [Tag(st.$1, fg: st.$2, bg: st.$3)],
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        children: [
          _bubble(p, mine: d.studentUid == me, staff: false, name: d.studentName, text: d.text, image: d.image, at: d.createdAt),
          for (final r in d.replies) _bubble(p, mine: r.byUid == me, staff: r.staff, name: r.byName, text: r.text, image: r.image, at: r.at),
          if (d.replies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(widget.m.isStaff ? tr('reply_first') : tr('waiting_teacher'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
            ),
          if (canSolve && (d.answered || d.solved)) ...[
            const SizedBox(height: 6),
            SoftButton(
              label: d.solved ? tr('reopen_doubt') : tr('mark_solved'),
              icon: d.solved ? Icons.replay_rounded : Icons.check_circle_outline_rounded,
              color: d.solved ? p.cardAlt : p.successTint,
              textColor: d.solved ? p.ink2 : p.success,
              onPressed: _toggleSolved,
            ),
          ],
        ],
      ),
      bottom: !_canWrite
          ? null
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_photo.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: PhotoThumb(_photo, size: 60, onRemove: () => setState(() => _photo = ''))),
              Row(children: [
                IconBtn(
                  icon: Icons.add_a_photo_outlined,
                  tooltip: tr('photo'),
                  onTap: () async {
                    final got = await pickPhotos(context, max: 1);
                    if (got.isNotEmpty) setState(() => _photo = got.first);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: widget.m.isStaff ? tr('write_answer') : tr('write_message'), isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _busy ? null : _reply,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(gradient: p.button, shape: BoxShape.circle, boxShadow: p.glow(p.brand)),
                    child: _busy
                        ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 21),
                  ),
                ),
              ]),
            ]),
    );
  }
}
