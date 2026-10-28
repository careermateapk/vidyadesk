import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'notices.dart' show ago;
import 'syllabus.dart';
import 'viewers.dart';

// ---------------------------------------------------------------------------
// Kinds
// ---------------------------------------------------------------------------

const resourceKinds = ['videos', 'notes', 'homework', 'papers', 'board', 'important', 'syllabus', 'links'];

class KindStyle {
  const KindStyle(this.icon, this.color);
  final IconData icon;
  final Color color;
  Color tint(Palette p) => color.withValues(alpha: p.dark ? .2 : .12);
}

KindStyle kindStyle(String k) => switch (k) {
      'videos' => const KindStyle(Icons.play_circle_rounded, Color(0xFFEF4444)),
      'notes' => const KindStyle(Icons.description_rounded, Color(0xFF6C5CE7)),
      'homework' => const KindStyle(Icons.edit_note_rounded, Color(0xFFE8930C)),
      'papers' => const KindStyle(Icons.history_edu_rounded, Color(0xFF3B9EF5)),
      'board' => const KindStyle(Icons.photo_camera_back_rounded, Color(0xFF12B886)),
      'important' => const KindStyle(Icons.star_rounded, Color(0xFFF0466E)),
      'syllabus' => const KindStyle(Icons.checklist_rounded, Color(0xFF0EA5B7)),
      _ => const KindStyle(Icons.link_rounded, Color(0xFF8B5CF6)),
    };

/// Which resources this person may see.
List<Resource> visibleResources(Membership m, List<Resource> all, List<Batch> batches) {
  switch (m.role) {
    case Role.admin:
    case Role.parent:
      return all;
    case Role.teacher:
      final mine = myBatches(m, batches).map((b) => b.id).toSet();
      return all.where((r) => r.batchId.isEmpty || mine.contains(r.batchId) || r.byUid == m.uid).toList();
    case Role.student:
      return all.where((r) => r.batchId.isEmpty || m.batchIds.contains(r.batchId)).toList();
  }
}

/// The child a parent is looking at right now (or the student themself).
String learnerUid(BuildContext context, Membership m) {
  if (m.role != Role.parent) return m.uid;
  if (m.childUids.isEmpty) return '';
  final i = context.appRead.childIndex.clamp(0, m.childUids.length - 1);
  return m.childUids[i];
}

String learnerName(BuildContext context, Membership m) {
  if (m.role != Role.parent) return m.name;
  if (m.childNames.isEmpty) return '';
  final i = context.appRead.childIndex.clamp(0, m.childNames.length - 1);
  return m.childNames[i];
}

// ---------------------------------------------------------------------------
// Hub
// ---------------------------------------------------------------------------

class ResourcesPage extends StatefulWidget {
  const ResourcesPage({super.key, required this.m, this.back = false});
  final Membership m;
  final bool back;
  @override
  State<ResourcesPage> createState() => _ResourcesPageState();
}

class _ResourcesPageState extends State<ResourcesPage> {
  String _batch = '';
  String _q = '';

  Future<(List<Resource>, List<Batch>)> _load() async {
    final b = context.appRead.backend;
    final id = widget.m.instituteId;
    return (await b.resources(id), await b.batches(id));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = widget.m;
    return AppScaffold(
      title: tr('nav_resources'),
      subtitle: m.instituteName,
      back: widget.back,
      body: Loader<(List<Resource>, List<Batch>)>(
        load: _load,
        builder: (context, d, reload) {
          final all = visibleResources(m, d.$1, d.$2);
          final batchList = switch (m.role) {
            Role.student => d.$2.where((b) => m.batchIds.contains(b.id)).toList(),
            Role.teacher => myBatches(m, d.$2),
            _ => d.$2,
          };
          final byBatch = _batch.isEmpty ? all : all.where((r) => r.batchId == _batch || r.batchId.isEmpty).toList();
          final q = _q.toLowerCase();
          final found = q.isEmpty ? <Resource>[] : byBatch.where((r) => '${r.title} ${r.chapter} ${r.desc}'.toLowerCase().contains(q)).toList();
          final recent = [...byBatch]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final batches = {for (final b in d.$2) b.id: b};

          Future<void> add([String? kind]) async {
            final ok = await push<bool>(context, AddResourceScreen(m: m, batches: myBatches(m, d.$2), kind: kind));
            if (ok == true) reload();
          }

          var i = 0;
          Widget item(Widget w) => FadeIn(delay: stagger(i++), child: w);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(18, 4, 18, widget.back ? 30 : 120),
            children: [
              item(TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(hintText: tr('search_resources'), prefixIcon: Icon(Icons.search_rounded, color: p.muted)),
              )),
              if (batchList.length > 1) ...[
                const SizedBox(height: 10),
                item(SizedBox(
                  height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    FilterPill(label: tr('all'), selected: _batch.isEmpty, onTap: () => setState(() => _batch = '')),
                    for (final b in batchList) ...[const SizedBox(width: 8), FilterPill(label: b.title, selected: _batch == b.id, onTap: () => setState(() => _batch = b.id))],
                  ]),
                )),
              ],
              const SizedBox(height: 12),
              if (q.isEmpty)
                item(Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    onTap: () => push(context, SyllabusScreen(m: m)),
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      IconBox(Icons.checklist_rounded, fg: const Color(0xFF0EA5B7), bg: const Color(0xFF0EA5B7).withValues(alpha: .13)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('syllabus_tracker'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                          Text(tr('syllabus_tracker_sub'), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: p.muted),
                    ]),
                  ),
                )),
              if (q.isNotEmpty) ...[
                if (found.isEmpty) EmptyState(icon: Icons.search_off_rounded, text: tr('nothing_found')),
                for (final r in found) Padding(padding: const EdgeInsets.only(bottom: 10), child: ResourceTile(m: m, r: r, batch: batches[r.batchId], batches: d.$2, onChanged: reload)),
              ] else ...[
                item(GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: .6,
                  children: [
                    for (final k in resourceKinds)
                      _KindTile(
                        kind: k,
                        count: byBatch.where((r) => r.kind == k).length,
                        onTap: () async {
                          await push(context, ResourceListScreen(m: m, kind: k, batchId: _batch));
                          reload();
                        },
                      ),
                  ],
                )),
                if (m.isStaff) ...[
                  const SizedBox(height: 14),
                  item(PrimaryButton(label: tr('add_resource'), icon: Icons.add_rounded, arrow: false, onPressed: () => add())),
                ],
                const SizedBox(height: 18),
                item(SectionTitle(tr('recently_added'))),
                const SizedBox(height: 6),
                if (recent.isEmpty) item(AppCard(child: EmptyState(icon: Icons.folder_open_rounded, text: m.isStaff ? tr('no_resources_staff') : tr('no_resources')))),
                for (final r in recent.take(12))
                  item(Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ResourceTile(m: m, r: r, batch: batches[r.batchId], batches: d.$2, onChanged: reload),
                  )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind, required this.count, required this.onTap});
  final String kind;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = kindStyle(kind);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
      radius: 18,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: s.tint(p), borderRadius: BorderRadius.circular(14)),
          child: Icon(s.icon, color: s.color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(tr('rk_$kind'), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, height: 1.15)),
        const SizedBox(height: 2),
        Text('$count', style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// One kind (e.g. all videos)
// ---------------------------------------------------------------------------

class ResourceListScreen extends StatefulWidget {
  const ResourceListScreen({super.key, required this.m, required this.kind, this.batchId = ''});
  final Membership m;
  final String kind, batchId;
  @override
  State<ResourceListScreen> createState() => _ResourceListScreenState();
}

class _ResourceListScreenState extends State<ResourceListScreen> {
  String _chapter = '';
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final s = kindStyle(widget.kind);
    return AppScaffold(
      title: tr('rk_${widget.kind}'),
      subtitle: tr('rk_${widget.kind}_sub'),
      body: Loader<(List<Resource>, List<Batch>)>(
        key: ValueKey(_v),
        load: () async {
          final b = context.appRead.backend;
          return (await b.resources(m.instituteId), await b.batches(m.instituteId));
        },
        builder: (context, d, reload) {
          var list = visibleResources(m, d.$1, d.$2).where((r) => r.kind == widget.kind).toList();
          if (widget.batchId.isNotEmpty) list = list.where((r) => r.batchId == widget.batchId || r.batchId.isEmpty).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final chapters = list.map((r) => r.chapter.trim()).where((c) => c.isNotEmpty).toSet().toList()..sort();
          final shown = _chapter.isEmpty ? list : list.where((r) => r.chapter.trim() == _chapter).toList();
          final batches = {for (final b in d.$2) b.id: b};
          return Column(children: [
            if (chapters.length > 1)
              PillBar(
                items: [tr('all'), ...chapters],
                index: _chapter.isEmpty ? 0 : chapters.indexOf(_chapter) + 1,
                onChanged: (i) => setState(() => _chapter = i == 0 ? '' : chapters[i - 1]),
              ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                children: [
                  if (shown.isEmpty) EmptyState(icon: s.icon, text: m.isStaff ? tr('no_resources_staff') : tr('no_resources')),
                  for (var i = 0; i < shown.length; i++)
                    FadeIn(
                      delay: stagger(i),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ResourceTile(m: m, r: shown[i], batch: batches[shown[i].batchId], batches: d.$2, onChanged: reload),
                      ),
                    ),
                ],
              ),
            ),
          ]);
        },
      ),
      bottom: m.isStaff
          ? Builder(
              builder: (context) => PrimaryButton(
                label: trf('add_kind', {'kind': tr('rk_${widget.kind}')}),
                icon: Icons.add_rounded,
                arrow: false,
                onPressed: () async {
                  final b = context.appRead.backend;
                  final batches = await b.batches(m.instituteId);
                  if (!context.mounted) return;
                  final ok = await push<bool>(context, AddResourceScreen(m: m, batches: myBatches(m, batches), kind: widget.kind));
                  if (ok == true) setState(() => _v++);
                },
              ),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

class ResourceTile extends StatelessWidget {
  const ResourceTile({super.key, required this.m, required this.r, required this.batch, required this.batches, required this.onChanged});
  final Membership m;
  final Resource r;
  final Batch? batch;
  final List<Batch> batches;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = kindStyle(r.kind);
    final vid = r.kind == 'videos' ? youtubeId(r.url) : null;
    final canEdit = m.role == Role.admin || r.byUid == m.uid;
    final overdue = r.kind == 'homework' && r.dueAt > 0 && DateTime.now().millisecondsSinceEpoch > r.dueAt + 86400000;
    Widget lead;
    if (vid != null) {
      lead = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(alignment: Alignment.center, children: [
          Image.network(youtubeThumb(vid), width: 96, height: 56, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(width: 96, height: 56, color: s.tint(p))),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
          ),
        ]),
      );
    } else if (r.images.isNotEmpty) {
      lead = PhotoThumb(r.images.first, size: 56);
    } else {
      lead = Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: s.tint(p), borderRadius: BorderRadius.circular(14)),
        child: Icon(s.icon, color: s.color, size: 26),
      );
    }
    final meta = [if (r.chapter.isNotEmpty) r.chapter, batch?.title ?? tr('everyone')].join(' · ');
    return AppCard(
      onTap: () => openResource(context, m, r, batches, onChanged),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        lead,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Row(children: [
              Tag(tr('rk_${r.kind}'), fg: s.color, bg: s.tint(p)),
              const SizedBox(width: 6),
              if (r.kind == 'homework' && r.dueAt > 0)
                Flexible(
                  child: Tag(
                    '${tr('due_on')} ${prettyDay(DateTime.fromMillisecondsSinceEpoch(r.dueAt))}',
                    fg: overdue ? p.danger : p.warn,
                    bg: overdue ? p.dangerTint : p.warnTint,
                  ),
                )
              else
                Flexible(child: Text(ago(r.createdAt), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 11.5))),
            ]),
          ]),
        ),
        if (canEdit)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: p.muted),
            onSelected: (v) async {
              if (v == 'share') {
                SharePlus.instance.share(ShareParams(text: '📚 ${r.title}${r.url.isEmpty ? '' : '\n${r.url}'}\n— ${m.instituteName}'));
                return;
              }
              final yes = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(tr('delete_resource_q')),
                  content: Text(r.title),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('delete'), style: TextStyle(color: p.danger))),
                  ],
                ),
              );
              if (yes != true || !context.mounted) return;
              try {
                await context.appRead.backend.deleteResource(m.instituteId, r.id);
                if (context.mounted) toast(context, tr('deleted'));
                await onChanged();
              } catch (e) {
                if (context.mounted) toast(context, errorMessage(e));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'share', child: Text(tr('share'))),
              PopupMenuItem(value: 'delete', child: Text(tr('delete'), style: TextStyle(color: p.danger))),
            ],
          )
        else
          Icon(Icons.chevron_right_rounded, color: p.muted),
      ]),
    );
  }
}

/// Open a resource the right way: video → player, link → in-app browser,
/// homework → homework screen, everything else → detail page.
Future<void> openResource(BuildContext context, Membership m, Resource r, List<Batch> batches, [Future<void> Function()? onChanged]) async {
  final batch = batches.where((b) => b.id == r.batchId).firstOrNull;
  final sub = [if (r.chapter.isNotEmpty) r.chapter, batch?.title ?? ''].where((x) => x.isNotEmpty).join(' · ');
  if (r.kind == 'homework') {
    await push(context, HomeworkScreen(m: m, r: r, batch: batch));
    await onChanged?.call();
    return;
  }
  final vid = youtubeId(r.url);
  if (vid != null) {
    await push(context, VideoPlayerScreen(videoId: vid, title: r.title, subtitle: sub, desc: r.desc));
    return;
  }
  if (r.url.isNotEmpty && r.images.isEmpty && r.desc.isEmpty) {
    await push(context, WebPageScreen(url: r.url, title: r.title));
    return;
  }
  await push(context, ResourceDetailScreen(r: r, subtitle: sub));
}

/// Notes / papers / board photos: text, photos and a link.
class ResourceDetailScreen extends StatelessWidget {
  const ResourceDetailScreen({super.key, required this.r, this.subtitle = ''});
  final Resource r;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = kindStyle(r.kind);
    return AppScaffold(
      title: tr('rk_${r.kind}'),
      subtitle: subtitle.isEmpty ? null : subtitle,
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBox(s.icon, fg: s.color, bg: s.tint(p)),
              const SizedBox(width: 10),
              Expanded(child: Text(r.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            Text('${r.byName} · ${ago(r.createdAt)}', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            if (r.desc.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(r.desc, style: TextStyle(fontSize: 15, height: 1.5, color: p.ink)),
            ],
          ]),
        ),
        if (r.images.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionTitle(trf('n_photos', {'n': '${r.images.length}'})),
          const SizedBox(height: 8),
          for (var i = 0; i < r.images.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => push(context, PhotoViewerScreen(images: r.images, start: i, title: r.title)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Builder(builder: (_) {
                    final b = Avatar.bytesOf(r.images[i]);
                    return b == null ? const SizedBox(height: 120) : Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
                  }),
                ),
              ),
            ),
        ],
        if (r.url.isNotEmpty) ...[
          const SizedBox(height: 14),
          PrimaryButton(label: tr('open_link'), icon: Icons.open_in_new_rounded, arrow: false, onPressed: () => push(context, WebPageScreen(url: r.url, title: r.title))),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Add resource (staff)
// ---------------------------------------------------------------------------

class AddResourceScreen extends StatefulWidget {
  const AddResourceScreen({super.key, required this.m, required this.batches, this.kind});
  final Membership m;
  final List<Batch> batches;
  final String? kind;
  @override
  State<AddResourceScreen> createState() => _AddResourceScreenState();
}

class _AddResourceScreenState extends State<AddResourceScreen> {
  late String _kind = widget.kind ?? 'notes';
  String _batch = '';
  final _title = TextEditingController();
  final _chapter = TextEditingController();
  final _url = TextEditingController();
  final _desc = TextEditingController();
  final List<String> _photos = [];
  DateTime? _due;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.batches.length == 1) _batch = widget.batches.first.id;
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _chapter.dispose();
    _url.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _needsUrl => _kind == 'videos' || _kind == 'links';
  bool get _photosFirst => _kind == 'board';

  Future<void> _save() async {
    final app = context.appRead;
    final title = _title.text.trim();
    final url = _url.text.trim();
    final desc = _desc.text.trim();
    String? err;
    if (title.length < 2) err = tr('err_title');
    if (_kind == 'videos' && youtubeId(url) == null) err = tr('err_youtube');
    if (_kind == 'links' && url.length < 5) err = tr('err_link');
    if (_kind == 'board' && _photos.isEmpty) err = tr('err_need_photo');
    if (!_needsUrl && _kind != 'board' && url.isEmpty && desc.isEmpty && _photos.isEmpty) err = tr('err_need_content');
    if (err != null) {
      toast(context, err);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = Resource(
        id: newId(),
        kind: _kind,
        title: title,
        desc: desc,
        batchId: _batch,
        chapter: _chapter.text.trim(),
        url: url,
        images: List.of(_photos),
        dueAt: _kind == 'homework' && _due != null ? DateTime(_due!.year, _due!.month, _due!.day).millisecondsSinceEpoch : 0,
        byUid: widget.m.uid,
        byName: app.profile?.name ?? widget.m.name,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await app.backend.saveResource(widget.m.instituteId, r);
      if (!mounted) return;
      toast(context, tr('resource_added'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhotos() async {
    final left = 4 - _photos.length;
    if (left <= 0) {
      toast(context, tr('max_photos'));
      return;
    }
    final got = await pickPhotos(context, max: left);
    if (got.isNotEmpty) setState(() => _photos.addAll(got));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final vid = _kind == 'videos' ? youtubeId(_url.text) : null;
    final photos = Wrap(spacing: 10, runSpacing: 10, children: [
      for (var i = 0; i < _photos.length; i++) PhotoThumb(_photos[i], onRemove: () => setState(() => _photos.removeAt(i))),
      if (_photos.length < 4)
        GestureDetector(
          onTap: _addPhotos,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: p.brandTint, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.brand.withValues(alpha: .35))),
            child: Icon(Icons.add_a_photo_outlined, color: p.brand),
          ),
        ),
    ]);
    return AppScaffold(
      title: tr('add_resource'),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
        FieldLabel(tr('type')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in resourceKinds)
            Builder(builder: (context) {
              final s = kindStyle(k);
              final on = _kind == k;
              return ChoiceChip(
                avatar: Icon(s.icon, size: 18, color: on ? s.color : p.muted),
                label: Text(tr('rk_$k')),
                selected: on,
                selectedColor: s.tint(p),
                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: on ? s.color : p.ink),
                side: BorderSide(color: on ? s.color : p.border),
                showCheckmark: false,
                onSelected: (_) => setState(() => _kind = k),
              );
            }),
        ]),
        const SizedBox(height: 16),
        if (_needsUrl) ...[
          FieldLabel(_kind == 'videos' ? tr('youtube_link') : tr('link')),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(hintText: _kind == 'videos' ? 'https://youtu.be/…' : 'https://drive.google.com/…', prefixIcon: Icon(_kind == 'videos' ? Icons.smart_display_outlined : Icons.link_rounded, color: p.muted)),
          ),
          if (vid != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(youtubeThumb(vid), fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: p.cardAlt)),
              ),
            ),
          ],
          const SizedBox(height: 14),
        ],
        if (_photosFirst) ...[
          FieldLabel(tr('board_photos')),
          photos,
          const SizedBox(height: 14),
        ],
        FieldLabel(_kind == 'homework' ? tr('homework_title') : tr('title')),
        TextField(controller: _title, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: tr('title_hint_${_kind == 'homework' ? 'hw' : 'res'}'))),
        const SizedBox(height: 14),
        FieldLabel(tr('chapter_optional')),
        TextField(controller: _chapter, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: tr('chapter_hint'))),
        const SizedBox(height: 14),
        FieldLabel(tr('send_to')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (widget.m.role == Role.admin) ChoicePill(label: tr('everyone'), selected: _batch.isEmpty, onTap: () => setState(() => _batch = '')),
          for (final b in widget.batches) ChoicePill(label: b.title, sub: daysCode(b.days), selected: _batch == b.id, onTap: () => setState(() => _batch = b.id)),
        ]),
        if (_kind == 'homework') ...[
          const SizedBox(height: 14),
          FieldLabel(tr('due_date')),
          AppCard(
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 120)), initialDate: _due ?? now.add(const Duration(days: 1)));
              if (d != null) setState(() => _due = d);
            },
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              IconBox(Icons.event_rounded, fg: p.warn, bg: p.warnTint),
              const SizedBox(width: 10),
              Expanded(child: Text(_due == null ? tr('pick_date') : prettyDate(_due!), style: const TextStyle(fontWeight: FontWeight.w700))),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        FieldLabel(_kind == 'homework' ? tr('hw_questions') : tr('description_optional')),
        TextField(controller: _desc, minLines: 3, maxLines: 8, maxLength: 1500, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: tr(_kind == 'homework' ? 'hw_hint' : 'desc_hint'))),
        if (!_needsUrl) ...[
          const SizedBox(height: 4),
          FieldLabel(tr('link_optional')),
          TextField(controller: _url, keyboardType: TextInputType.url, decoration: InputDecoration(hintText: tr('drive_hint'), prefixIcon: Icon(Icons.link_rounded, color: p.muted))),
        ],
        if (!_photosFirst) ...[
          const SizedBox(height: 14),
          FieldLabel(tr('photos_optional')),
          photos,
        ],
        const SizedBox(height: 22),
        PrimaryButton(label: tr('save_share'), icon: Icons.check_rounded, arrow: false, busy: _busy, onPressed: _save),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Homework
// ---------------------------------------------------------------------------

class HomeworkScreen extends StatelessWidget {
  const HomeworkScreen({super.key, required this.m, required this.r, this.batch});
  final Membership m;
  final Resource r;
  final Batch? batch;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = kindStyle('homework');
    final due = r.dueAt == 0 ? null : DateTime.fromMillisecondsSinceEpoch(r.dueAt);
    final head = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBox(s.icon, fg: s.color, bg: s.tint(p)),
          const SizedBox(width: 10),
          Expanded(child: Text(r.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (due != null) Tag('${tr('due_on')} ${prettyDay(due)}', fg: p.warn, bg: p.warnTint),
          Tag(batch?.title ?? tr('everyone'), fg: p.indigo, bg: p.indigoTint),
          if (r.chapter.isNotEmpty) Tag(r.chapter, fg: p.brand, bg: p.brandTint),
        ]),
        if (r.desc.isNotEmpty) ...[
          const SizedBox(height: 12),
          SelectableText(r.desc, style: TextStyle(fontSize: 15, height: 1.5, color: p.ink)),
        ],
        if (r.images.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < r.images.length; i++) PhotoThumb(r.images[i], size: 76, onTap: () => push(context, PhotoViewerScreen(images: r.images, start: i, title: r.title))),
          ]),
        ],
        if (r.url.isNotEmpty) ...[
          const SizedBox(height: 12),
          SoftButton(label: tr('open_link'), icon: Icons.open_in_new_rounded, onPressed: () => push(context, WebPageScreen(url: r.url, title: r.title))),
        ],
        const SizedBox(height: 6),
        Text('${r.byName} · ${ago(r.createdAt)}', style: TextStyle(color: p.muted, fontSize: 12)),
      ]),
    );
    return AppScaffold(
      title: tr('rk_homework'),
      subtitle: batch?.title,
      body: m.isStaff ? _StaffHomework(m: m, r: r, head: head) : _LearnerHomework(m: m, r: r, head: head),
    );
  }
}

class _LearnerHomework extends StatefulWidget {
  const _LearnerHomework({required this.m, required this.r, required this.head});
  final Membership m;
  final Resource r;
  final Widget head;
  @override
  State<_LearnerHomework> createState() => _LearnerHomeworkState();
}

class _LearnerHomeworkState extends State<_LearnerHomework> {
  final _text = TextEditingController();
  final List<String> _photos = [];
  bool _busy = false;
  bool _editing = false;
  int _v = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit(String uid) async {
    final app = context.appRead;
    if (_text.text.trim().isEmpty && _photos.isEmpty) {
      toast(context, tr('err_need_answer'));
      return;
    }
    setState(() => _busy = true);
    try {
      await app.backend.saveSubmission(
        widget.m.instituteId,
        Submission(
          resourceId: widget.r.id,
          studentUid: uid,
          studentName: app.profile?.name ?? widget.m.name,
          text: _text.text.trim(),
          images: List.of(_photos),
          submittedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      toast(context, tr('hw_submitted'));
      setState(() {
        _editing = false;
        _v++;
      });
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final parent = widget.m.role == Role.parent;
    final uid = learnerUid(context, widget.m);
    return Loader<Submission?>(
      key: ValueKey('sub-$_v'),
      load: () => context.appRead.backend.mySubmission(widget.m.instituteId, widget.r.id, uid),
      builder: (context, sub, reload) {
        final showForm = !parent && (sub == null || (_editing && !sub.checked));
        return ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
          widget.head,
          const SizedBox(height: 16),
          if (sub != null && !showForm) ...[
            SectionTitle(parent ? tr('childs_answer') : tr('my_answer')),
            const SizedBox(height: 6),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Tag(sub.checked ? tr('hw_checked') : tr('hw_submitted_tag'), fg: sub.checked ? p.success : p.brand, bg: sub.checked ? p.successTint : p.brandTint),
                  const Spacer(),
                  Text(ago(sub.submittedAt), style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
                if (sub.text.isNotEmpty) ...[const SizedBox(height: 10), Text(sub.text, style: const TextStyle(height: 1.45))],
                if (sub.images.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = 0; i < sub.images.length; i++) PhotoThumb(sub.images[i], onTap: () => push(context, PhotoViewerScreen(images: sub.images, start: i))),
                  ]),
                ],
                if (sub.checked && (sub.marks.isNotEmpty || sub.remark.isNotEmpty)) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: p.successTint, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Icon(Icons.rate_review_rounded, color: p.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          [if (sub.marks.isNotEmpty) '${tr('marks')}: ${sub.marks}', if (sub.remark.isNotEmpty) sub.remark].join('\n'),
                          style: TextStyle(color: p.success, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
            if (!parent && !sub.checked) ...[
              const SizedBox(height: 12),
              SoftButton(
                label: tr('edit_answer'),
                icon: Icons.edit_rounded,
                onPressed: () => setState(() {
                  _editing = true;
                  _v++;
                  _text.text = sub.text;
                  _photos
                    ..clear()
                    ..addAll(sub.images);
                }),
              ),
            ],
          ] else if (parent) ...[
            AppCard(child: EmptyState(icon: Icons.hourglass_empty_rounded, text: tr('hw_not_submitted_child'))),
          ] else ...[
            SectionTitle(tr('submit_answer')),
            const SizedBox(height: 6),
            TextField(controller: _text, minLines: 3, maxLines: 8, maxLength: 1500, decoration: InputDecoration(hintText: tr('answer_hint'))),
            FieldLabel(tr('answer_photos')),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (var i = 0; i < _photos.length; i++) PhotoThumb(_photos[i], onRemove: () => setState(() => _photos.removeAt(i))),
              if (_photos.length < 3)
                GestureDetector(
                  onTap: () async {
                    final got = await pickPhotos(context, max: 3 - _photos.length);
                    if (got.isNotEmpty) setState(() => _photos.addAll(got));
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: p.brandTint, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.brand.withValues(alpha: .35))),
                    child: Icon(Icons.add_a_photo_outlined, color: p.brand),
                  ),
                ),
            ]),
            const SizedBox(height: 20),
            PrimaryButton(label: tr('submit_hw'), icon: Icons.send_rounded, arrow: false, busy: _busy, onPressed: () => _submit(uid)),
          ],
        ]);
      },
    );
  }
}

class _StaffHomework extends StatelessWidget {
  const _StaffHomework({required this.m, required this.r, required this.head});
  final Membership m;
  final Resource r;
  final Widget head;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Loader<(List<Submission>, List<Membership>)>(
      load: () async {
        final b = context.appRead.backend;
        return (await b.submissionsFor(m.instituteId, r.id), await b.members(m.instituteId));
      },
      builder: (context, d, reload) {
        final students = approvedStudents(d.$2, batchId: r.batchId.isEmpty ? null : r.batchId);
        final subs = {for (final s in d.$1) s.studentUid: s};
        final done = students.where((s) => subs.containsKey(s.uid)).length;
        return ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
          head,
          const SizedBox(height: 14),
          AppCard(
            child: Row(children: [
              Ring(
                value: students.isEmpty ? 0 : done / students.length,
                size: 56,
                stroke: 7,
                color: p.success,
                track: p.successTint,
                center: Text('$done', style: TextStyle(fontWeight: FontWeight.w800, color: p.success)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trf('n_of_m_submitted', {'n': '$done', 'm': '${students.length}'}), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(tr('tap_to_check'), style: TextStyle(color: p.muted, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          for (final s in students)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Builder(builder: (context) {
                final sub = subs[s.uid];
                return AppCard(
                  padding: const EdgeInsets.all(12),
                  onTap: sub == null
                      ? null
                      : () async {
                          final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _CheckSheet(m: m, sub: sub));
                          if (ok == true) reload();
                        },
                  child: Row(children: [
                    Avatar(s.name, size: 40, photo: s.photo),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(sub == null ? tr('not_submitted') : ago(sub.submittedAt), style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                    ),
                    if (sub == null)
                      Tag(tr('pending'), fg: p.danger, bg: p.dangerTint)
                    else if (sub.checked)
                      Tag(sub.marks.isEmpty ? tr('hw_checked') : sub.marks, fg: p.success, bg: p.successTint)
                    else
                      Tag(tr('to_check'), fg: p.brand, bg: p.brandTint),
                  ]),
                );
              }),
            ),
        ]);
      },
    );
  }
}

class _CheckSheet extends StatefulWidget {
  const _CheckSheet({required this.m, required this.sub});
  final Membership m;
  final Submission sub;
  @override
  State<_CheckSheet> createState() => _CheckSheetState();
}

class _CheckSheetState extends State<_CheckSheet> {
  late final _marks = TextEditingController(text: widget.sub.marks);
  late final _remark = TextEditingController(text: widget.sub.remark);
  bool _busy = false;

  @override
  void dispose() {
    _marks.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final s = widget.sub
        ..checked = true
        ..marks = _marks.text.trim()
        ..remark = _remark.text.trim();
      await context.appRead.backend.saveSubmission(widget.m.instituteId, s);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sub;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.studentName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (s.text.isNotEmpty) Text(s.text, style: const TextStyle(height: 1.45)),
          if (s.images.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < s.images.length; i++) PhotoThumb(s.images[i], size: 80, onTap: () => push(context, PhotoViewerScreen(images: s.images, start: i, title: s.studentName))),
            ]),
          ],
          const SizedBox(height: 14),
          FieldLabel(tr('marks_optional')),
          TextField(controller: _marks, decoration: const InputDecoration(hintText: '8/10')),
          const SizedBox(height: 10),
          FieldLabel(tr('remark_optional')),
          TextField(controller: _remark, decoration: InputDecoration(hintText: tr('remark_hint'))),
          const SizedBox(height: 16),
          PrimaryButton(label: tr('mark_checked'), icon: Icons.done_all_rounded, arrow: false, busy: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}
