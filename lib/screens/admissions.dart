import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/backend.dart' show newId;
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'money.dart' show confirmDelete;
import 'notices.dart' show ago;

const leadStages = ['new', 'contacted', 'demo', 'joined', 'lost'];
const leadSources = ['walkin', 'call', 'friend', 'poster', 'social', 'other'];

Color stageColor(Palette p, String s) => switch (s) {
      'new' => p.brand,
      'contacted' => p.indigo,
      'demo' => p.warn,
      'joined' => p.success,
      _ => p.muted,
    };

/// Admission enquiries: add, follow up, move through stages.
class AdmissionsScreen extends StatefulWidget {
  const AdmissionsScreen({super.key, required this.m});
  final Membership m;
  @override
  State<AdmissionsScreen> createState() => _AdmissionsScreenState();
}

class _AdmissionsScreenState extends State<AdmissionsScreen> {
  String _stage = 'open';
  int _v = 0;

  Future<void> _edit([Lead? l]) async {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _LeadSheet(m: widget.m, lead: l));
    if (ok == true) setState(() => _v++);
  }

  Future<void> _shareAd() async {
    final b = context.appRead.backend;
    final inst = await b.institute(widget.m.instituteId);
    final batches = await b.batches(widget.m.instituteId);
    final lines = batches.map((x) => '• ${x.title} — ${daysCode(x.days)} ${timeLabel(x.startMin)}').join('\n');
    await SharePlus.instance.share(ShareParams(
      text: trf('admission_ad', {
        'inst': widget.m.instituteName,
        'city': inst?.city ?? '',
        'batches': lines,
        'phone': (inst?.phone ?? '').isEmpty ? widget.m.phone : inst!.phone,
      }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppScaffold(
      title: tr('admissions'),
      subtitle: tr('admissions_sub'),
      actions: [IconBtn(icon: Icons.share_rounded, tooltip: tr('share_admission_ad'), onTap: _shareAd)],
      body: Loader<List<Lead>>(
        key: ValueKey(_v),
        load: () => context.appRead.backend.leads(widget.m.instituteId),
        builder: (context, all, reload) {
          int count(String s) => all.where((l) => l.status == s).length;
          final open = all.where((l) => l.status != 'joined' && l.status != 'lost').toList();
          final shown = _stage == 'open' ? open : all.where((l) => l.status == _stage).toList();
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
          final followToday = open.where((l) => l.followUp > 0 && l.followUp < today).toList();
          final conv = all.isEmpty ? 0 : pct(count('joined'), all.length);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Row(children: [
                for (final s in ['new', 'contacted', 'demo', 'joined']) ...[
                  if (s != 'new') const SizedBox(width: 8),
                  Expanded(
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      radius: 16,
                      onTap: () => setState(() => _stage = s),
                      child: Column(children: [
                        Text('${count(s)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: stageColor(p, s))),
                        Text(tr('lead_$s'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.muted)),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
            PillBar(
              items: [tr('open_leads'), ...leadStages.map((s) => tr('lead_$s'))],
              index: _stage == 'open' ? 0 : leadStages.indexOf(_stage) + 1,
              onChanged: (i) => setState(() => _stage = i == 0 ? 'open' : leadStages[i - 1]),
            ),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
                children: [
                  if (_stage == 'open' && followToday.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: p.warnTint, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Icon(Icons.alarm_rounded, color: p.warn),
                        const SizedBox(width: 10),
                        Expanded(child: Text(trf('n_followups_today', {'n': '${followToday.length}'}), style: TextStyle(color: p.warn, fontWeight: FontWeight.w800))),
                      ]),
                    ),
                  if (all.isNotEmpty && _stage == 'open')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(trf('conversion', {'n': '$conv'}), style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                  if (shown.isEmpty) EmptyState(icon: Icons.person_search_rounded, text: tr('no_leads')),
                  for (var i = 0; i < shown.length; i++)
                    FadeIn(
                      delay: stagger(i, stepMs: 40),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LeadTile(
                          l: shown[i],
                          due: shown[i].followUp > 0 && shown[i].followUp < today && shown[i].status != 'joined' && shown[i].status != 'lost',
                          onTap: () => _edit(shown[i]),
                          onStage: (s) async {
                            shown[i].status = s;
                            try {
                              await context.appRead.backend.saveLead(widget.m.instituteId, shown[i]);
                            } catch (e) {
                              if (context.mounted) toast(context, errorMessage(e));
                            }
                            setState(() => _v++);
                          },
                          inst: widget.m.instituteName,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]);
        },
      ),
      bottom: PrimaryButton(label: tr('add_enquiry'), icon: Icons.person_add_alt_1_rounded, arrow: false, onPressed: () => _edit()),
    );
  }
}

class _LeadTile extends StatelessWidget {
  const _LeadTile({required this.l, required this.due, required this.onTap, required this.onStage, required this.inst});
  final Lead l;
  final bool due;
  final VoidCallback onTap;
  final ValueChanged<String> onStage;
  final String inst;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = stageColor(p, l.status);
    final next = switch (l.status) { 'new' => 'contacted', 'contacted' => 'demo', 'demo' => 'joined', _ => null };
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(l.name, size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text([l.className, l.subject, if (l.source.isNotEmpty) tr('src_${l.source}')].where((x) => x.isNotEmpty).join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
            ]),
          ),
          Tag(tr('lead_${l.status}'), fg: c, bg: c.withValues(alpha: .12)),
        ]),
        if (l.note.isNotEmpty) ...[const SizedBox(height: 8), Text(l.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink2, fontSize: 13))],
        const SizedBox(height: 8),
        Row(children: [
          Icon(due ? Icons.alarm_rounded : Icons.schedule_rounded, size: 15, color: due ? p.warn : p.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              l.followUp > 0 ? '${tr('follow_up')} ${prettyDay(DateTime.fromMillisecondsSinceEpoch(l.followUp))}' : ago(l.createdAt),
              style: TextStyle(color: due ? p.warn : p.muted, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          if (l.phone.isNotEmpty) ...[
            _mini(p, Icons.call_rounded, p.indigo, () => callPhone(context, l.phone)),
            const SizedBox(width: 6),
            _mini(p, Icons.chat_rounded, p.success, () => openWhatsApp(context, l.phone, trf('lead_msg', {'name': l.name, 'inst': inst}))),
          ],
          if (next != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => onStage(next),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: stageColor(p, next).withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                child: Text('→ ${tr('lead_$next')}', style: TextStyle(color: stageColor(p, next), fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _mini(Palette p, IconData i, Color c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
          child: Icon(i, size: 18, color: c),
        ),
      );
}

class _LeadSheet extends StatefulWidget {
  const _LeadSheet({required this.m, this.lead});
  final Membership m;
  final Lead? lead;
  @override
  State<_LeadSheet> createState() => _LeadSheetState();
}

class _LeadSheetState extends State<_LeadSheet> {
  late final _name = TextEditingController(text: widget.lead?.name ?? '');
  late final _phone = TextEditingController(text: widget.lead?.phone ?? '');
  late final _cls = TextEditingController(text: widget.lead?.className ?? '');
  late final _sub = TextEditingController(text: widget.lead?.subject ?? '');
  late final _note = TextEditingController(text: widget.lead?.note ?? '');
  late String _source = widget.lead?.source ?? 'walkin';
  late String _status = widget.lead?.status ?? 'new';
  late DateTime? _follow = (widget.lead?.followUp ?? 0) > 0 ? DateTime.fromMillisecondsSinceEpoch(widget.lead!.followUp) : null;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _cls, _sub, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      toast(context, tr('err_name'));
      return;
    }
    setState(() => _busy = true);
    try {
      final app = context.appRead;
      final l = widget.lead ?? Lead(id: newId(), name: '', createdAt: DateTime.now().millisecondsSinceEpoch, byName: app.profile?.name ?? widget.m.name);
      l
        ..name = _name.text.trim()
        ..phone = _phone.text.trim()
        ..className = _cls.text.trim()
        ..subject = _sub.text.trim()
        ..note = _note.text.trim()
        ..source = _source
        ..status = _status
        ..followUp = _follow == null ? 0 : DateTime(_follow!.year, _follow!.month, _follow!.day, 10).millisecondsSinceEpoch;
      await app.backend.saveLead(widget.m.instituteId, l);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final l = widget.lead;
    if (l == null || !await confirmDelete(context, l.name) || !mounted) return;
    try {
      await context.appRead.backend.deleteLead(widget.m.instituteId, l.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget f(String label, TextEditingController c, {TextInputType? type, IconData? icon, String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c,
            keyboardType: type,
            textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
            decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: icon == null ? null : Icon(icon)),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(widget.lead == null ? tr('add_enquiry') : tr('enquiry'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            if (widget.lead != null) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline_rounded, color: p.danger)),
          ]),
          const SizedBox(height: 10),
          f(tr('student_name'), _name, icon: Icons.person_outline_rounded),
          f(tr('mobile'), _phone, type: TextInputType.phone, icon: Icons.call_outlined),
          Row(children: [
            Expanded(child: f(tr('class_label'), _cls, hint: 'Class 12')),
            const SizedBox(width: 10),
            Expanded(child: f(tr('subject'), _sub, hint: 'Economics')),
          ]),
          FieldLabel(tr('how_found')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in leadSources) ChoicePill(label: tr('src_$s'), selected: _source == s, onTap: () => setState(() => _source = s)),
          ]),
          const SizedBox(height: 12),
          FieldLabel(tr('stage')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in leadStages) ChoicePill(label: tr('lead_$s'), selected: _status == s, onTap: () => setState(() => _status = s)),
          ]),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(12),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 90)), initialDate: _follow ?? now.add(const Duration(days: 1)));
              if (d != null) setState(() => _follow = d);
            },
            child: Row(children: [
              Icon(Icons.alarm_rounded, color: p.warn),
              const SizedBox(width: 10),
              Expanded(child: Text(_follow == null ? tr('set_follow_up') : '${tr('follow_up')} ${prettyDate(_follow!)}', style: const TextStyle(fontWeight: FontWeight.w700))),
              if (_follow != null) GestureDetector(onTap: () => setState(() => _follow = null), child: Icon(Icons.close_rounded, color: p.muted)),
            ]),
          ),
          const SizedBox(height: 10),
          TextField(controller: _note, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: tr('lead_note_hint'))),
          const SizedBox(height: 16),
          PrimaryButton(label: tr('save'), arrow: false, busy: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}
