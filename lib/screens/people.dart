import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'join.dart';
import 'onboarding.dart';

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
                    child: _RequestCard(r: list[i], index: i, batches: batches, onDone: reload),
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
  const _RequestCard({required this.r, required this.index, required this.batches, required this.onDone});
  final Membership r;
  final int index;
  final Map<String, Batch> batches;
  final Future<void> Function() onDone;
  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;
  bool? _result;

  Future<void> _decide(bool ok) async {
    setState(() => _busy = true);
    try {
      await context.appRead.backend.decide(widget.r, ok);
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
            Avatar(r.name, size: 46, index: widget.index),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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
          const SizedBox(height: 12),
          if (_result != null)
            Row(children: [
              Icon(_result! ? Icons.check_circle_rounded : Icons.cancel_rounded, color: _result! ? p.success : p.danger),
              const SizedBox(width: 6),
              Text(_result! ? tr('approved') : tr('rejected'), style: TextStyle(fontWeight: FontWeight.w900, color: _result! ? p.success : p.danger)),
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
                      Avatar(shown[i].name, size: 42, index: i),
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
                    Avatar(x.name, size: 76),
                    const SizedBox(height: 10),
                    Text(x.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
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
                        Text(c.total == 0 ? '—' : '${pct(c.present, c.total)}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: p.brand)),
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
                          Text(rupees(cur?.amount ?? x.monthlyFee), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: cur?.paid == true ? p.success : p.danger)),
                          Text(cur?.paid == true ? tr('paid') : tr('due'), style: TextStyle(color: p.muted, fontSize: 12)),
                        ]),
                      ),
                    ),
                  ],
                ]),
              ],
            ],
          );
        },
      ),
    );
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
      body: Loader<Institute?>(
        key: ValueKey(_v),
        load: () => context.appRead.backend.institute(widget.m.instituteId),
        builder: (context, inst, reload) {
          if (inst == null) return EmptyState(icon: Icons.error_outline_rounded, text: tr('err_load'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
            children: [
              FadeIn(
                child: AppCard(
                  child: Column(children: [
                    Text(inst.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
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
                  Text(tr('which_code_who'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  _line(p, Icons.co_present_rounded, tr('codes_teacher')),
                  _line(p, Icons.school_rounded, tr('codes_student')),
                  _line(p, Icons.family_restroom_rounded, tr('codes_parent')),
                ]),
              ),
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
