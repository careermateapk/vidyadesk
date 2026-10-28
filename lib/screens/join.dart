import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/backend.dart';
import '../data/demo_backend.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import '../ui/mascot.dart';
import 'auth.dart';
import 'onboarding.dart';

const subjectSuggestions = ['Maths', 'Science', 'Physics', 'Chemistry', 'Biology', 'English', 'Hindi', 'Economics', 'Accounts', 'Business Studies', 'Computer', 'SST', 'Sanskrit', 'Reasoning', 'GK'];

/// Shown after signup (or from Settings) until the person has a place in an institute.
class JoinFlow extends StatelessWidget {
  const JoinFlow({super.key, required this.role});
  final Role role;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.pal;
    final canClose = app.memberships.isNotEmpty;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconBtn(
                    icon: canClose ? Icons.close_rounded : Icons.chevron_left_rounded,
                    size: canClose ? 21 : 26,
                    tooltip: canClose ? tr('cancel') : tr('change_role'),
                    onTap: () => canClose ? app.cancelJoin() : app.chooseRole(null),
                  ),
                  const Spacer(),
                  Builder(builder: (context) {
                    final c = roleColors(p, role);
                    return Tag(roleName(role), fg: c.$1, bg: c.$2, leading: Icon(roleIcon(role), size: 14, color: c.$1));
                  }),
                  if (!canClose) ...[
                    const SizedBox(width: 10),
                    IconBtn(icon: Icons.logout_rounded, tooltip: tr('logout'), onTap: () => app.signOut()),
                  ],
                ]),
                const SizedBox(height: 18),
                FadeIn(child: Text(tr('join_title_${role.name}'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.8))),
                const SizedBox(height: 4),
                FadeIn(delay: stagger(1), child: Text(tr('join_sub_${role.name}'), style: TextStyle(color: p.muted, fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w500))),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const DemoBanner(),
              if (role == Role.admin) const _CreateInstitute() else _JoinWithCode(role: role),
              if (role == Role.teacher) ...[
                const SizedBox(height: 18),
                AppCard(
                  color: p.cardAlt,
                  onTap: () => app.chooseRole(Role.admin),
                  child: Row(children: [
                    IconBox(Icons.storefront_rounded, fg: p.accent, bg: p.warnTint),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('own_coaching_q'), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(tr('own_coaching_sub'), style: TextStyle(color: p.muted, fontSize: 12.5)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: p.muted),
                  ]),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: const Color(0x26FFFFFF),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 24))),
        ),
      );
}

// ---------------------------------------------------------------------------
// Admin: create institute
// ---------------------------------------------------------------------------

class _CreateInstitute extends StatefulWidget {
  const _CreateInstitute();
  @override
  State<_CreateInstitute> createState() => _CreateInstituteState();
}

class _CreateInstituteState extends State<_CreateInstitute> {
  final _name = TextEditingController();
  late final _city = TextEditingController(text: context.appRead.profile?.address.city ?? '');
  bool? _teaches;
  final List<String> _subjects = [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final app = context.appRead;
    if (_name.text.trim().length < 3) return setState(() => _error = tr('err_inst_name'));
    if (_city.text.trim().isEmpty) return setState(() => _error = tr('err_city'));
    if (_teaches == null) return setState(() => _error = tr('err_teach_q'));
    if (_teaches! && _subjects.isEmpty) return setState(() => _error = tr('err_subjects'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final m = await app.backend.createInstitute(owner: app.profile!, name: _name.text.trim(), city: _city.text.trim(), teaches: _teaches!, subjects: _subjects);
      final inst = await app.backend.institute(m.instituteId);
      if (!mounted) return;
      await showCodeSheet(context, title: tr('inst_ready'), sub: tr('inst_code_share_sub'), code: inst?.code ?? '', shareText: instituteShareText(m.instituteName, inst?.code ?? ''));
      await app.chooseRole(Role.admin);
      await app.refreshAndShow(m);
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    var i = 0;
    Widget item(Widget w) => FadeIn(delay: stagger(i++), child: Padding(padding: const EdgeInsets.only(bottom: 14), child: w));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      item(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FieldLabel(tr('inst_name')),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: 'Sharma Classes', prefixIcon: Icon(Icons.apartment_rounded, color: p.muted))),
      ])),
      item(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FieldLabel(tr('city')),
        TextField(controller: _city, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: 'Darbhanga', prefixIcon: Icon(Icons.location_city_rounded, color: p.muted))),
      ])),
      item(AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconBox(Icons.co_present_rounded, fg: p.indigo, bg: p.indigoTint),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('do_you_teach'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
          const SizedBox(height: 6),
          Text(tr('do_you_teach_sub'), style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ChoicePill(label: tr('yes_i_teach'), sub: tr('yes_i_teach_sub'), selected: _teaches == true, onTap: () => setState(() => _teaches = true))),
            const SizedBox(width: 10),
            Expanded(child: ChoicePill(label: tr('no_only_manage'), sub: tr('no_only_manage_sub'), selected: _teaches == false, onTap: () => setState(() => _teaches = false))),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: _teaches == true
                ? Padding(padding: const EdgeInsets.only(top: 14), child: SubjectPicker(selected: _subjects, onChanged: () => setState(() {})))
                : const SizedBox(width: double.infinity),
          ),
        ]),
      )),
      if (_error != null) item(Text(_error!, style: TextStyle(color: p.danger, fontWeight: FontWeight.w700))),
      item(PrimaryButton(label: tr('create_institute'), busy: _busy, onPressed: _create)),
    ]);
  }
}

/// Tap-to-pick subject chips plus a box to type a new one.
class SubjectPicker extends StatefulWidget {
  const SubjectPicker({super.key, required this.selected, required this.onChanged});
  final List<String> selected;
  final VoidCallback onChanged;
  @override
  State<SubjectPicker> createState() => _SubjectPickerState();
}

class _SubjectPickerState extends State<SubjectPicker> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _add() {
    final v = _c.text.trim();
    if (v.isEmpty) return;
    if (!widget.selected.any((s) => s.toLowerCase() == v.toLowerCase())) widget.selected.add(v);
    _c.clear();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final all = {...subjectSuggestions, ...widget.selected}.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldLabel(tr('your_subjects')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in all)
          FilterChip(
            label: Text(s),
            selected: widget.selected.contains(s),
            showCheckmark: true,
            selectedColor: p.brandTint,
            checkmarkColor: p.brand,
            side: BorderSide(color: widget.selected.contains(s) ? p.brand : p.border),
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: widget.selected.contains(s) ? p.brand : p.ink),
            onSelected: (on) {
              on ? widget.selected.add(s) : widget.selected.remove(s);
              widget.onChanged();
            },
          ),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _c,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _add(),
        decoration: InputDecoration(hintText: tr('add_subject'), suffixIcon: IconButton(onPressed: _add, icon: Icon(Icons.add_circle_rounded, color: p.brand))),
      ),
    ]);
  }
}

String instituteShareText(String name, String code) => trf('share_inst_code', {'name': name, 'code': code});

/// Bottom sheet with a big code, copy and share buttons.
Future<void> showCodeSheet(BuildContext context, {required String title, required String sub, required String code, required String shareText}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final p = context.pal;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (context, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: p.successTint, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, color: p.success, size: 42),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(sub, textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.35)),
            const SizedBox(height: 16),
            CodeBox(code: code),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: SoftButton(label: tr('copy'), icon: Icons.copy_rounded, onPressed: () => copyText(context, code))),
              const SizedBox(width: 10),
              Expanded(
                child: SoftButton(
                  label: tr('share'),
                  icon: Icons.share_rounded,
                  color: p.successTint,
                  textColor: p.success,
                  onPressed: () => SharePlus.instance.share(ShareParams(text: shareText)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            PrimaryButton(label: tr('done'), arrow: false, onPressed: () => Navigator.of(context).pop()),
          ]),
        ),
      );
    },
  );
}

/// Big dashed box that shows a code; tap to copy.
class CodeBox extends StatelessWidget {
  const CodeBox({super.key, required this.code, this.big = true});
  final String code;
  final bool big;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => copyText(context, code),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: big ? 18 : 12, horizontal: 12),
        decoration: BoxDecoration(color: p.brandTint, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.brand.withValues(alpha: .5), width: 1.5)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(code, style: TextStyle(fontSize: big ? 30 : 22, fontWeight: FontWeight.w800, letterSpacing: 2, color: p.brand)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teacher / student / parent: join with a code
// ---------------------------------------------------------------------------

class _JoinWithCode extends StatefulWidget {
  const _JoinWithCode({required this.role});
  final Role role;
  @override
  State<_JoinWithCode> createState() => _JoinWithCodeState();
}

class _JoinWithCodeState extends State<_JoinWithCode> {
  final _code = TextEditingController();
  final List<String> _subjects = [];
  String _relation = 'father';
  JoinCode? _found;
  bool _busy = false;
  String? _error;

  CodeType get _want => switch (widget.role) { Role.teacher => CodeType.institute, Role.parent => CodeType.student, _ => CodeType.batch };

  String get _demoCode => switch (widget.role) {
        Role.teacher => DemoBackend.demoInstituteCode,
        Role.parent => DemoBackend.demoStudentCode,
        _ => DemoBackend.demoBatchCode,
      };

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final app = context.appRead;
    final code = normaliseCode(_code.text);
    if (code.length < 5) return setState(() => _error = tr('err_code_short'));
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _found = null;
    });
    try {
      final c = await app.backend.lookupCode(code);
      if (c == null) {
        setState(() => _error = tr('err_code_not_found'));
        HapticFeedback.mediumImpact();
      } else if (c.type != _want) {
        setState(() => _error = trf('err_code_wrong_type', {'type': tr('codetype_${c.type.name}')}));
        HapticFeedback.mediumImpact();
      } else {
        setState(() => _found = c);
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final app = context.appRead;
    final c = _found!;
    if (widget.role == Role.teacher && _subjects.isEmpty) return setState(() => _error = tr('err_subjects'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final m = await app.backend.requestJoin(user: app.profile!, code: c, relation: widget.role == Role.parent ? _relation : '', subjects: _subjects);
      await app.refreshAndShow(m);
    } catch (e) {
      setState(() => _error = e is BackendError && e.code == 'permission' ? tr('err_permission') : errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FadeIn(
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconBox(Icons.key_rounded, fg: p.accent, bg: p.warnTint),
              const SizedBox(width: 10),
              Expanded(child: Text(tr('code_label_${widget.role.name}'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            ]),
            const SizedBox(height: 6),
            Text(tr('code_help_${widget.role.name}'), style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35)),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.5),
              onChanged: (_) {
                if (_found != null || _error != null) {
                  setState(() {
                    _found = null;
                    _error = null;
                  });
                }
              },
              onSubmitted: (_) => _check(),
              decoration: InputDecoration(
                hintText: _demoCode.replaceAll(RegExp(r'[0-9]'), '0'),
                hintStyle: TextStyle(color: p.muted.withValues(alpha: .5), letterSpacing: 1.5, fontWeight: FontWeight.w700),
                suffixIcon: IconButton(
                  tooltip: tr('paste'),
                  icon: Icon(Icons.content_paste_rounded, color: p.brand),
                  onPressed: () async {
                    final d = await Clipboard.getData('text/plain');
                    if (d?.text != null) _code.text = normaliseCode(d!.text!);
                  },
                ),
              ),
            ),
            if (app.isDemo) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: Icon(Icons.science_rounded, size: 16, color: p.warn),
                  label: Text('${tr('demo_code')}: $_demoCode'),
                  onPressed: () {
                    _code.text = _demoCode;
                    _check();
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_found == null) SoftButton(label: tr('check_code'), icon: Icons.search_rounded, onPressed: _busy ? null : _check),
          ]),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        child: _found == null ? const SizedBox(width: double.infinity) : Padding(padding: const EdgeInsets.only(top: 14), child: _foundCard(p, _found!)),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            Icon(Icons.error_rounded, color: p.danger, size: 20),
            const SizedBox(width: 6),
            Expanded(child: Text(_error!, style: TextStyle(color: p.danger, fontWeight: FontWeight.w700))),
          ]),
        ),
      if (_busy && _found == null) const Padding(padding: EdgeInsets.only(top: 16), child: LoadingView()),
    ]);
  }

  Widget _foundCard(Palette p, JoinCode c) {
    final lines = <(IconData, String, String)>[
      (Icons.apartment_rounded, tr('institute'), c.instituteName),
      if (c.type == CodeType.batch) (Icons.class_rounded, tr('batch'), c.batchTitle),
      if (c.type == CodeType.batch && c.teacherName.isNotEmpty) (Icons.person_rounded, tr('teacher'), c.teacherName),
      if (c.type == CodeType.student) (Icons.school_rounded, tr('student'), c.studentName),
    ];
    return FadeIn(
      child: AppCard(
        border: p.success,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.verified_rounded, color: p.success),
            const SizedBox(width: 8),
            Text(tr('code_found'), style: TextStyle(color: p.success, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(l.$1, size: 18, color: p.muted),
                const SizedBox(width: 8),
                Text('${l.$2}: ', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
                Expanded(child: Text(l.$3, style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ),
          if (widget.role == Role.teacher) ...[
            const SizedBox(height: 6),
            SubjectPicker(selected: _subjects, onChanged: () => setState(() {})),
          ],
          if (widget.role == Role.parent) ...[
            const SizedBox(height: 6),
            FieldLabel(tr('relation')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in ['father', 'mother', 'guardian'])
                ChoicePill(label: tr('rel_$r'), selected: _relation == r, onTap: () => setState(() => _relation = r)),
            ]),
          ],
          const SizedBox(height: 14),
          PrimaryButton(label: tr('send_request'), busy: _busy, onPressed: _send),
          const SizedBox(height: 6),
          Text(tr('approval_note'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Waiting for approval
// ---------------------------------------------------------------------------

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key, required this.m});
  final Membership m;
  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  bool _busy = false;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final app = context.appRead;
    try {
      await app.refreshMemberships();
      if (mounted && app.active?.approved != true) toast(context, tr('still_pending'));
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demoApprove() async {
    final app = context.appRead;
    final b = app.backend;
    if (b is DemoBackend) {
      setState(() => _busy = true);
      await b.demoApprove(widget.m);
      await app.refreshMemberships();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final m = widget.m;
    final rejected = m.status == MemberStatus.rejected;
    final others = app.memberships.where((x) => x.id != m.id && x.status != MemberStatus.rejected).toList();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          children: [
            Row(children: [
              const AppLogo(size: 34),
              const SizedBox(width: 9),
              const Expanded(child: Text('VidyaDesk', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -.3))),
              IconBtn(icon: Icons.logout_rounded, tooltip: tr('logout'), onTap: () => app.signOut()),
            ]),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: Stack(alignment: Alignment.center, children: [
                  RotationTransition(
                    turns: _spin,
                    child: Container(
                      width: 232,
                      height: 232,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(colors: [(rejected ? p.danger : p.brand).withValues(alpha: 0), (rejected ? p.danger : p.brand).withValues(alpha: .35)]),
                      ),
                    ),
                  ),
                  Container(width: 222, height: 222, decoration: BoxDecoration(shape: BoxShape.circle, color: p.bg)),
                  const Floaty(child: Mascot(size: 200, book: false)),
                  Positioned(
                    right: 18,
                    top: 18,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: p.card, shape: BoxShape.circle, boxShadow: p.shadow),
                      child: Icon(rejected ? Icons.block_rounded : Icons.schedule_rounded, color: rejected ? p.danger : p.warn, size: 24),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 22),
            FadeIn(
              child: Text(rejected ? tr('request_rejected') : tr('request_sent'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.8)),
            ),
            const SizedBox(height: 6),
            FadeIn(
              delay: stagger(1),
              child: Text(
                rejected ? tr('request_rejected_sub') : trf('request_sent_sub', {'who': m.role == Role.teacher ? tr('the_admin') : tr('the_teacher')}),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 14.5, height: 1.5, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 20),
            if (!rejected)
              FadeIn(
                delay: stagger(2),
                child: AppCard(
                  child: Column(children: [
                    _step(p, tr('step_sent'), tr('step_sent_sub'), 2, true),
                    _step(p, tr('step_review'), tr('step_review_sub'), 1, true),
                    _step(p, tr('step_in'), tr('step_in_sub'), 0, false),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
            FadeIn(
              delay: stagger(2),
              child: AppCard(
                child: Column(children: [
                  _row(p, Icons.apartment_rounded, tr('institute'), m.instituteName),
                  _row(p, roleIcon(m.role), tr('role'), roleName(m.role)),
                  if (m.childNames.isNotEmpty) _row(p, Icons.school_rounded, tr('student'), m.childNames.join(', ')),
                  if (m.joinedVia.isNotEmpty) _row(p, Icons.key_rounded, tr('code'), m.joinedVia),
                  _row(p, Icons.schedule_rounded, tr('status'), rejected ? tr('rejected') : tr('pending')),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            if (rejected)
              PrimaryButton(label: tr('try_other_code'), onPressed: () => app.startNewJoin(m.role))
            else
              PrimaryButton(label: tr('check_status'), icon: Icons.refresh_rounded, arrow: false, busy: _busy, onPressed: _refresh),
            if (app.isDemo && !rejected) ...[
              const SizedBox(height: 10),
              SoftButton(label: tr('demo_approve'), icon: Icons.science_rounded, color: p.warnTint, textColor: p.warn, onPressed: _busy ? null : _demoApprove),
            ],
            if (others.isNotEmpty) ...[
              const SizedBox(height: 24),
              SectionTitle(tr('your_other_roles')),
              const SizedBox(height: 8),
              for (final o in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    onTap: () => app.switchTo(o),
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      IconBox(roleIcon(o.role), fg: p.brand, bg: p.brandTint),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${roleName(o.role)} · ${o.instituteName}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      Icon(Icons.chevron_right_rounded, color: p.muted),
                    ]),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _step(Palette p, String title, String sub, int state, bool line) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state == 2 ? p.success : (state == 1 ? p.warnTint : p.cardAlt),
              border: state == 0 ? Border.all(color: p.border, width: 1.5) : null,
            ),
            alignment: Alignment.center,
            child: state == 2
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : (state == 1 ? PulseDot(color: p.warn, size: 9) : null),
          ),
          if (line) Container(width: 2, height: 24, color: p.border),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              Text(sub, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]);

  Widget _row(Palette p, IconData icon, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: p.muted),
          const SizedBox(width: 8),
          Text(k, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
      );
}
