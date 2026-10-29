import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/push.dart';
import '../ui/widgets.dart';
import 'batches.dart' show batchShareText;
import 'common.dart';
import 'join.dart';
import 'onboarding.dart';
import 'subscription.dart';

// ---------------------------------------------------------------------------
// Join requests
// ---------------------------------------------------------------------------

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key, required this.m});
  final Membership m;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: InnerBar(title: tr('requests')),
      body: Loader<(List<Membership>, List<Batch>)>(
        load: () async {
          final b = context.appRead.backend;
          return (await b.members(m.instituteId), await b.batches(m.instituteId));
        },
        builder: (context, d, reload) {
          final list = pendingFor(m, d.$1, d.$2);
          final batches = {for (final b in d.$2) b.id: b};
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
            children: [
              if (list.isEmpty) EmptyState(icon: Icons.inbox_rounded, text: tr('no_requests')),
              for (var i = 0; i < list.length; i++)
                FadeIn(
                  delay: stagger(i),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RequestCard(r: list[i], index: i, batches: batches, pickable: [for (final b in d.$2) if (m.role == Role.admin || b.teacherUid == m.uid) b], onDone: reload),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.r, required this.index, required this.batches, required this.pickable, required this.onDone});
  final Membership r;
  final int index;
  final Map<String, Batch> batches;
  final List<Batch> pickable;
  final Future<void> Function() onDone;
  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;
  bool? _result;
  late final Set<String> _picked = {...widget.r.batchIds};

  bool get _student => widget.r.role == Role.student;

  Future<void> _decide(bool ok) async {
    if (ok && _student && _picked.isEmpty) {
      toast(context, tr('pick_batch_first'));
      HapticFeedback.mediumImpact();
      return;
    }
    if (ok && !await checkPlanLimit(context, widget.r)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final changed = _student && (_picked.length != widget.r.batchIds.length || !_picked.containsAll(widget.r.batchIds));
      await context.appRead.backend.decide(widget.r, ok, batchIds: ok && changed ? _picked.toList() : null);

      if (ok) {
        final names = [for (final id in (_student ? _picked : <String>{})) widget.batches[id]?.title ?? ''].where((e) => e.isNotEmpty).join(', ');
        Push.send(
          inst: widget.r.instituteId,
          kind: 'approved',
          title: '🎉 ${tr('push_approved')}',
          body: names.isEmpty ? widget.r.instituteName : '${widget.r.instituteName} · $names',
          topics: [Push.person(widget.r.instituteId, widget.r.uid)],
        );
        if (_student) context.appRead.backend.syncRoster(widget.r.instituteId);
        if (mounted) toast(context, trf('approved_toast', {'name': widget.r.name}));
      }
      HapticFeedback.mediumImpact();
      setState(() => _result = ok);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await widget.onDone();
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = widget.r;
    final detail = switch (r.role) {
      Role.student => r.batchIds.map((id) => widget.batches[id]?.title ?? id).join(', '),
      Role.parent => '${tr('rel_${r.relation.isEmpty ? 'guardian' : r.relation}')} · ${r.childNames.join(', ')}',
      Role.teacher => r.subjects.join(', '),
      Role.admin => '',
    };
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: _result == null ? 1 : .55,
      child: AppCard(
        border: _result == null ? null : (_result! ? p.success : p.danger),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(r.name, size: 46, index: widget.index, photo: r.photo),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(r.phone, style: TextStyle(color: p.muted, fontSize: 12.5)),
              ]),
            ),
            Tag(roleName(r.role), fg: p.indigo, bg: p.indigoTint, leading: Icon(roleIcon(r.role), size: 13, color: p.indigo)),
          ]),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.cardAlt, borderRadius: BorderRadius.circular(12)),
              child: Text(detail, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ],
          if (r.joinedVia.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${tr('via_code')} ${r.joinedVia}', style: TextStyle(color: p.muted, fontSize: 12)),
          ],
          if (_student && _result == null && widget.pickable.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(r.batchIds.isEmpty ? tr('pick_batch_join') : tr('batches'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: r.batchIds.isEmpty && _picked.isEmpty ? p.warn : p.ink)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in widget.pickable)
                ChoicePill(
                  label: b.title,
                  selected: _picked.contains(b.id),
                  onTap: () => setState(() => _picked.contains(b.id) ? _picked.remove(b.id) : _picked.add(b.id)),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          if (_result != null)
            Row(children: [
              Icon(_result! ? Icons.check_circle_rounded : Icons.cancel_rounded, color: _result! ? p.success : p.danger),
              const SizedBox(width: 6),
              Text(_result! ? tr('approved') : tr('rejected'), style: TextStyle(fontWeight: FontWeight.w800, color: _result! ? p.success : p.danger)),
            ])
          else
            Row(children: [
              Expanded(child: SoftButton(label: tr('reject'), icon: Icons.close_rounded, color: p.dangerTint, textColor: p.danger, onPressed: _busy ? null : () => _decide(false))),
              const SizedBox(width: 10),
              Expanded(child: SoftButton(label: tr('approve'), icon: Icons.check_rounded, color: p.successTint, textColor: p.success, onPressed: _busy ? null : () => _decide(true))),
            ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// People (students / teachers / parents)
// ---------------------------------------------------------------------------

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key, required this.m, this.embedded = false});
  final Membership m;
  final bool embedded;
  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  int _tab = 0;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = widget.m;
    final admin = m.role == Role.admin;
    final body = Loader<(List<Membership>, List<Batch>)>(
      load: () async {
        final b = context.appRead.backend;
        return (await b.members(m.instituteId), await b.batches(m.instituteId));
      },
      builder: (context, d, reload) {
        final mine = myBatches(m, d.$2).map((b) => b.id).toSet();
        final approved = d.$1.where((x) => x.approved).toList();
        var students = approvedStudents(approved);
        if (!admin) students = students.where((s) => s.batchIds.any(mine.contains)).toList();
        final teachers = approved.where((x) => x.canTeach).toList();
        final parents = approved.where((x) => x.role == Role.parent).toList();
        final lists = [students, if (admin) teachers, parents];
        final labels = [tr('students'), if (admin) tr('teachers'), tr('parents')];
        final tab = _tab.clamp(0, lists.length - 1);
        final shown = lists[tab].where((x) => _q.isEmpty || x.name.toLowerCase().contains(_q.toLowerCase()) || x.phone.contains(_q)).toList();
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
          children: [
            Segmented(items: [for (var i = 0; i < labels.length; i++) '${labels[i]} ${lists[i].length}'], index: tab, onChanged: (v) => setState(() => _tab = v)),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(hintText: tr('search_name_phone'), prefixIcon: Icon(Icons.search_rounded, color: p.muted)),
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty) EmptyState(icon: Icons.person_search_rounded, text: tr('nobody_here')),
            for (var i = 0; i < shown.length; i++)
              FadeIn(
                delay: stagger(i, stepMs: 30),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(10),
                    onTap: () async {
                      await push(context, PersonScreen(m: m, person: shown[i]));
                      reload();
                    },
                    child: Row(children: [
                      Avatar(shown[i].name, size: 42, index: i, photo: shown[i].photo),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(shown[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(_sub(shown[i], d.$2), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ]),
                      ),
                      if (shown[i].phone.isNotEmpty)
                        IconButton(onPressed: () => callPhone(context, shown[i].phone), icon: Icon(Icons.call_rounded, color: p.brand), tooltip: tr('call')),
                    ]),
                  ),
                ),
              ),
          ],
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(appBar: InnerBar(title: tr('nav_students'), showBack: false), body: body);
  }

  String _sub(Membership x, List<Batch> batches) {
    if (x.role == Role.student) {
      final names = x.batchIds.map((id) => batches.where((b) => b.id == id).firstOrNull?.subject).whereType<String>().join(', ');
      return [x.studentCode, names].where((s) => s.isNotEmpty).join(' · ');
    }
    if (x.role == Role.parent) return '${tr('rel_${x.relation.isEmpty ? 'guardian' : x.relation}')} · ${x.childNames.join(', ')}';
    return x.subjects.join(', ');
  }
}

class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.m, required this.person});
  final Membership m;
  final Membership person;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final x = person;
    final isStudent = x.role == Role.student;
    return Scaffold(
      appBar: InnerBar(title: x.name),
      body: Loader<(List<AttendanceDay>, List<FeeRecord>)>(
        load: () async {
          if (!isStudent) return (<AttendanceDay>[], <FeeRecord>[]);
          final b = context.appRead.backend;
          return (
            await b.attendanceForStudent(m.instituteId, x.uid),
            m.role == Role.admin ? await b.feesForStudent(m.instituteId, x.uid) : <FeeRecord>[],
          );
        },
        builder: (context, d, reload) {
          final c = attendanceCount(x.uid, d.$1);
          final cur = d.$2.where((f) => f.month == monthKey(DateTime.now())).firstOrNull;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
            children: [
              FadeIn(
                child: AppCard(
                  child: Column(children: [
                    Avatar(x.name, size: 76, photo: x.photo),
                    const SizedBox(height: 10),
                    Text(x.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Tag(roleName(x.role), fg: p.indigo, bg: p.indigoTint),
                    if (isStudent && x.studentCode.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () => copyText(context, x.studentCode),
                        child: Text('${tr('student_code')}: ${x.studentCode}', style: TextStyle(color: p.brand, fontWeight: FontWeight.w800)),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: SoftButton(label: tr('call'), icon: Icons.call_rounded, onPressed: x.phone.isEmpty ? null : () => callPhone(context, x.phone))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SoftButton(
                          label: 'WhatsApp',
                          icon: Icons.chat_rounded,
                          color: p.successTint,
                          textColor: p.success,
                          onPressed: x.phone.isEmpty ? null : () => openWhatsApp(context, x.phone, trf('hello_msg', {'n': x.name})),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(children: [
                  _kv(p, Icons.call_rounded, tr('mobile'), x.phone),
                  if (x.email.isNotEmpty) _kv(p, Icons.mail_rounded, tr('email'), x.email),
                  if (x.city.isNotEmpty) _kv(p, Icons.location_on_rounded, tr('city'), x.city),
                  if (x.subjects.isNotEmpty) _kv(p, Icons.menu_book_rounded, tr('subjects'), x.subjects.join(', ')),
                  if (x.childNames.isNotEmpty) _kv(p, Icons.school_rounded, tr('child'), x.childNames.join(', ')),
                ]),
              ),
              if (isStudent) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('attendance'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 12.5)),
                        const SizedBox(height: 4),
                        Text(c.total == 0 ? '—' : '${pct(c.present, c.total)}%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24, color: p.brand)),
                        Text('${c.present}/${c.total} ${tr('days')}', style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                    ),
                  ),
                  if (m.role == Role.admin) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('this_month_fee'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 12.5)),
                          const SizedBox(height: 4),
                          Text(rupees(cur?.amount ?? x.monthlyFee), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24, color: cur?.paid == true ? p.success : p.danger)),
                          Text(cur?.paid == true ? tr('paid') : tr('due'), style: TextStyle(color: p.muted, fontSize: 12)),
                        ]),
                      ),
                    ),
                  ],
                ]),
              ],
              if (m.role == Role.admin && x.role != Role.admin && x.uid != m.uid) ...[
                const SizedBox(height: 20),
                SoftButton(
                  label: trf('remove_person', {'name': x.name.split(' ').first}),
                  icon: Icons.person_remove_rounded,
                  color: p.dangerTint,
                  textColor: p.danger,
                  onPressed: () => _remove(context),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _remove(BuildContext context) async {
    final x = person;
    var delFees = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) {
        final p = c.pal;
        final first = x.name.split(' ').first;
        return StatefulBuilder(
          builder: (c, set) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: IconBox(Icons.delete_outline_rounded, fg: p.danger, bg: p.dangerTint, size: 60)),
                const SizedBox(height: 12),
                Text(trf('remove_q', {'name': first}), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(trf('remove_sub', {'name': first, 'inst': x.instituteName}), textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.45)),
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Column(children: [
                    CheckboxListTile(dense: true, value: true, onChanged: null, title: Text(tr('remove_profile_items'), style: const TextStyle(fontWeight: FontWeight.w600))),
                    if (x.role == Role.student) ...[
                      CheckboxListTile(dense: true, value: true, onChanged: null, title: Text(tr('remove_parent_link'), style: const TextStyle(fontWeight: FontWeight.w600))),
                      CheckboxListTile(
                        dense: true,
                        value: delFees,
                        activeColor: p.danger,
                        onChanged: (v) => set(() => delFees = v ?? false),
                        title: Text(tr('remove_fees_too'), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(tr('remove_fees_keep_hint')),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.notifications_active_outlined, size: 18, color: p.brand),
                  const SizedBox(width: 8),
                  Expanded(child: Text(trf('remove_notify', {'name': first}), style: TextStyle(fontWeight: FontWeight.w700, color: p.ink2, fontSize: 13))),
                ]),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: p.danger, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(tr('yes_remove'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
              ]),
            ),
          ),
        );
      },
    );
    if (ok != true || !context.mounted) return;
    final app = context.appRead;
    try {
      await Push.send(
        inst: x.instituteId,
        kind: 'removed',
        title: trf('push_removed', {'inst': x.instituteName}),
        body: tr('push_removed_body'),
        topics: [Push.person(x.instituteId, x.uid)],
      );
      await app.backend.removeMember(x, deleteFees: delFees);
      if (!context.mounted) return;
      toast(context, trf('removed_done', {'name': x.name}));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (context.mounted) toast(context, errorMessage(e));
    }
  }

  Widget _kv(Palette p, IconData i, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 18, color: p.muted),
          const SizedBox(width: 10),
          SizedBox(width: 80, child: Text(k, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Institute code
// ---------------------------------------------------------------------------

class InstituteCodeScreen extends StatefulWidget {
  const InstituteCodeScreen({super.key, required this.m});
  final Membership m;
  @override
  State<InstituteCodeScreen> createState() => _InstituteCodeScreenState();
}

class _InstituteCodeScreenState extends State<InstituteCodeScreen> {
  int _v = 0;

  Future<void> _regenerate(Institute inst) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('new_code_q')),
        content: Text(tr('new_code_warn')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('yes_change'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.appRead.backend.newInstituteCode(inst);
      setState(() => _v++);
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: InnerBar(title: tr('institute_code')),
      body: Loader<(Institute?, List<Batch>)>(
        key: ValueKey(_v),
        load: () async {
          final b = context.appRead.backend;
          b.syncRoster(widget.m.instituteId);
          return (await b.institute(widget.m.instituteId), await b.batches(widget.m.instituteId));
        },
        builder: (context, d, reload) {
          final inst = d.$1;
          final batches = d.$2;
          if (inst == null) return EmptyState(icon: Icons.error_outline_rounded, text: tr('err_load'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
            children: [
              FadeIn(
                child: AppCard(
                  child: Column(children: [
                    Text(inst.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text(inst.city, style: TextStyle(color: p.muted)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                      child: QrImageView(data: 'VIDYADESK:${inst.code}', size: 190, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF073B3F)), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF073B3F))),
                    ),
                    const SizedBox(height: 16),
                    CodeBox(code: inst.code),
                    const SizedBox(height: 8),
                    Text(tr('inst_code_for_teachers'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 13, height: 1.35)),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: SoftButton(label: tr('copy'), icon: Icons.copy_rounded, onPressed: () => copyText(context, inst.code))),
                const SizedBox(width: 10),
                Expanded(
                  child: SoftButton(
                    label: tr('share'),
                    icon: Icons.share_rounded,
                    color: p.successTint,
                    textColor: p.success,
                    onPressed: () => SharePlus.instance.share(ShareParams(text: instituteShareText(inst.name, inst.code))),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              if (widget.m.role == Role.admin)
                TextButton.icon(onPressed: () => _regenerate(inst), icon: Icon(Icons.autorenew_rounded, color: p.danger), label: Text(tr('make_new_code'), style: TextStyle(color: p.danger))),
              const SizedBox(height: 10),
              AppCard(
                color: p.cardAlt,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('which_code_who'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _line(p, Icons.co_present_rounded, tr('codes_teacher')),
                  _line(p, Icons.school_rounded, tr('codes_student')),
                  _line(p, Icons.family_restroom_rounded, tr('codes_parent')),
                ]),
              ),
              if (batches.isNotEmpty) ...[
                const SizedBox(height: 18),
                SectionTitle(tr('batch_codes')),
                const SizedBox(height: 4),
                for (final b in batches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      child: Row(children: [
                        IconBox(Icons.class_rounded, fg: p.indigo, bg: p.indigoTint),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            SelectableText(b.code, style: TextStyle(color: p.brand, fontWeight: FontWeight.w800, letterSpacing: .5)),
                          ]),
                        ),
                        IconBtn(icon: Icons.copy_rounded, tooltip: tr('copy'), onTap: () => copyText(context, b.code)),
                        const SizedBox(width: 6),
                        IconBtn(icon: Icons.share_rounded, tooltip: tr('share'), onTap: () => SharePlus.instance.share(ShareParams(text: batchShareText(b, inst.name)))),
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

  Widget _line(Palette p, IconData i, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 18, color: p.brand),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: TextStyle(color: p.muted, fontSize: 13, height: 1.35))),
        ]),
      );
}
