import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'auth.dart';
import 'common.dart';
import 'help.dart';
import 'payments.dart';
import 'photo.dart';
import 'learner_home.dart';
import 'onboarding.dart';
import 'people.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.m});
  final Membership m;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final u = app.profile;
    final name = u?.name ?? m.name;
    var i = 0;
    Widget item(Widget w) => FadeIn(delay: stagger(i++, stepMs: 50), child: Padding(padding: const EdgeInsets.only(bottom: 12), child: w));
    final others = app.memberships.where((x) => x.status != MemberStatus.rejected).toList();
    final langName = switch (app.lang) { 'hi' => 'हिन्दी', 'hn' => 'Hinglish', _ => 'English' };

    return Scaffold(
      appBar: InnerBar(title: tr('nav_more'), showBack: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
        children: [
          item(AppCard(
            gradient: p.hero,
            child: Row(children: [
              GestureDetector(
                onTap: () => changeProfilePhoto(context),
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x66FFFFFF), width: 2)),
                    child: ClipOval(child: Avatar(name, size: 60, photo: u?.photo ?? '')),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: p.shadow),
                      child: Icon(Icons.photo_camera_rounded, size: 15, color: p.brandDeep),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                  Text(u?.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    Tag(roleName(m.role), fg: const Color(0xFF4B3FC4), bg: Colors.white),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(9)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.apartment_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(m.instituteName,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ]),
              ),
              if (u != null)
                IconButton(
                  tooltip: tr('edit_profile'),
                  onPressed: () => push(context, ProfileFormScreen(withEmail: false, existing: u)),
                  icon: const Icon(Icons.edit_rounded, color: Colors.white),
                ),
            ]),
          )),
          item(const DemoBanner()),

          // ----- roles -----
          item(SectionTitle(tr('my_roles'), trailing: Text(trf('n_roles', {'n': '${others.length}'}), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)))),
          for (final x in others)
            item(AppCard(
              padding: const EdgeInsets.all(12),
              border: x.id == m.id ? p.brand : null,
              onTap: x.id == m.id ? null : () => app.switchTo(x),
              child: Row(children: [
                IconBox(roleIcon(x.role), fg: p.brand, bg: p.brandTint),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(roleName(x.role), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(x.instituteName, style: TextStyle(color: p.muted, fontSize: 12.5)),
                  ]),
                ),
                if (x.id == m.id)
                  Tag(tr('active'), fg: p.success, bg: p.successTint)
                else if (!x.approved)
                  Tag(tr('pending'), fg: p.warn, bg: p.warnTint)
                else
                  Tag(tr('switch'), fg: p.brand, bg: p.brandTint),
                const SizedBox(width: 8),
                Material(
                  color: p.dangerTint,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => showRemoveRoleSheet(context, x),
                    child: SizedBox(width: 40, height: 40, child: Icon(Icons.delete_rounded, color: p.danger, size: 21, semanticLabel: tr('remove'))),
                  ),
                ),
              ]),
            )),
          item(SoftButton(label: tr('add_role'), icon: Icons.add_rounded, onPressed: () => _addRole(context))),

          // ----- institute tools -----
          if (m.isStaff) ...[
            item(SectionTitle(tr('institute'))),
            item(AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                if (m.role == Role.admin) ...[
                  _Tile(icon: Icons.storefront_outlined, color: p.brand, label: tr('institute_details'), onTap: () => push(context, InstituteSettingsScreen(m: m))),
                  _Tile(icon: Icons.qr_code_2_rounded, color: p.success, label: tr('institute_code'), onTap: () => push(context, InstituteCodeScreen(m: m))),
                  _Tile(icon: Icons.currency_rupee_rounded, color: p.warn, label: tr('payments_confirm'), onTap: () => push(context, ConfirmPaymentsScreen(m: m))),
                ],
                _Tile(icon: Icons.how_to_reg_rounded, color: p.danger, label: tr('requests'), onTap: () => push(context, RequestsScreen(m: m))),
                _Tile(
                  icon: Icons.groups_rounded,
                  color: p.brand,
                  label: tr('people'),
                  onTap: () => push(context, Scaffold(appBar: InnerBar(title: tr('people')), body: PeoplePage(m: m, embedded: true))),
                ),
              ]),
            )),
          ],
          if (m.role == Role.student)
            item(AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _Tile(icon: Icons.badge_rounded, color: p.indigo, label: tr('id_card'), onTap: () async {
                final batches = await app.backend.batches(m.instituteId);
                if (context.mounted) push(context, IdCardScreen(m: m, batches: batches.where((b) => m.batchIds.contains(b.id)).toList()));
              }),
            )),

          // ----- app settings -----
          item(SectionTitle(tr('app_settings'))),
          item(AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const ThemeSwitch(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('theme'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(app.themeMode == ThemeMode.dark ? tr('dark_mode') : (app.themeMode == ThemeMode.system ? tr('system_mode') : tr('light_mode')),
                        style: TextStyle(color: p.muted, fontSize: 12.5)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Segmented(
                items: [tr('light'), tr('dark'), tr('auto')],
                index: switch (app.themeMode) { ThemeMode.dark => 1, ThemeMode.system => 2, _ => 0 },
                onChanged: (v) => app.setTheme([ThemeMode.light, ThemeMode.dark, ThemeMode.system][v]),
              ),
            ]),
          )),
          item(AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _Tile(icon: Icons.translate_rounded, color: p.indigo, label: tr('language'), value: langName, onTap: () => push(context, const LanguageScreen())),
          )),
          item(SectionTitle(tr('help_legal'))),
          item(AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              _Tile(icon: Icons.help_outline_rounded, color: p.brand, label: tr('help_faq'), onTap: () => push(context, const FaqScreen())),
              _Tile(icon: Icons.description_outlined, color: p.indigo, label: tr('terms'), onTap: () => push(context, const LegalScreen())),
              _Tile(icon: Icons.verified_user_outlined, color: p.success, label: tr('privacy'), onTap: () => push(context, const LegalScreen(privacy: true))),
              _Tile(icon: Icons.mail_outline_rounded, color: p.warn, label: tr('contact_us'), onTap: () => contactSupport(context)),
            ]),
          )),
          item(AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              _Tile(icon: Icons.info_outline_rounded, color: p.muted, label: tr('about'), value: 'v1.0', onTap: () => _about(context)),
              _Tile(icon: Icons.logout_rounded, color: p.danger, label: tr('logout'), onTap: () => _logout(context)),
            ]),
          )),
        ],
      ),
    );
  }

  Future<void> _addRole(BuildContext context) async {
    final p = context.pal;
    final r = await showModalBottomSheet<Role>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('add_role'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('add_role_sub'), style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 12),
            for (final r in Role.values)
              ListTile(
                leading: IconBox(roleIcon(r), fg: p.brand, bg: p.brandTint),
                title: Text(roleName(r), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(tr('role_${r.name}_sub'), maxLines: 2),
                onTap: () => Navigator.pop(c, r),
              ),
          ]),
        ),
      ),
    );
    if (r != null && context.mounted) context.appRead.startNewJoin(r);
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('logout_q')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('logout'))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final app = context.appRead;
      await app.signOut();
      await app.chooseRole(null);
    }
  }

  void _about(BuildContext context) {
    final app = context.appRead;
    showAboutDialog(
      context: context,
      applicationName: 'VidyaDesk',
      applicationVersion: '1.0.0',
      applicationIcon: const AppLogo(size: 48),
      children: [Text(tr('about_text')), const SizedBox(height: 8), Text(app.isDemo ? tr('mode_demo') : tr('mode_live'))],
    );
  }
}

/// Asks before leaving a role, or (owner) deleting the whole institute.
Future<void> showRemoveRoleSheet(BuildContext context, Membership x) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RemoveRoleSheet(x: x),
  );
}

class _RemoveRoleSheet extends StatefulWidget {
  const _RemoveRoleSheet({required this.x});
  final Membership x;
  @override
  State<_RemoveRoleSheet> createState() => _RemoveRoleSheetState();
}

class _RemoveRoleSheetState extends State<_RemoveRoleSheet> {
  final _name = TextEditingController();
  bool _busy = false;
  late final bool _owner = widget.x.role == Role.admin && widget.x.approved;
  late final Future<List<Membership>> _members = _owner ? context.appRead.backend.members(widget.x.instituteId) : Future.value(<Membership>[]);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().toLowerCase() == widget.x.instituteName.trim().toLowerCase();

  Future<void> _go() async {
    final app = context.appRead;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await app.removeRole(widget.x, deleteInstitute: _owner);
      nav.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(content: Text(_owner ? tr('inst_deleted') : tr('role_removed'))));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, errorMessage(e));
      }
    }
  }

  Widget _line(String mark, String text, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mark, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w600, height: 1.35))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final x = widget.x;
    final pending = !x.approved;
    final color = _owner ? p.danger : p.warn;
    final tint = _owner ? p.dangerTint : p.warnTint;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.elasticOut,
              builder: (context, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(_owner ? Icons.warning_rounded : Icons.logout_rounded, color: color, size: 38),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _owner ? trf('delete_inst_q', {'name': x.instituteName}) : (pending ? tr('cancel_request_q') : trf('leave_q', {'name': x.instituteName})),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: _owner ? p.danger : p.ink),
          ),
          const SizedBox(height: 6),
          Text(
            _owner ? tr('delete_inst_sub') : trf('leave_sub', {'role': roleName(x.role), 'name': x.instituteName}),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _owner ? p.dangerTint : p.cardAlt, borderRadius: BorderRadius.circular(16)),
            child: _owner
                ? FutureBuilder<List<Membership>>(
                    future: _members,
                    builder: (context, s) {
                      final list = s.data ?? const <Membership>[];
                      final st = list.where((m) => m.role == Role.student).length;
                      final te = list.where((m) => m.role == Role.teacher).length;
                      return Column(children: [
                        _line('✕', tr('delete_inst_l1'), p.danger),
                        _line('✕', trf('delete_inst_l2', {'s': '$st', 't': '$te'}), p.danger),
                        _line('✕', tr('delete_inst_l3'), p.danger),
                      ]);
                    },
                  )
                : Column(children: [
                    _line('✓', tr('leave_l1'), p.success),
                    _line('✓', tr('leave_l2'), p.success),
                  ]),
          ),
          if (_owner) ...[
            const SizedBox(height: 14),
            FieldLabel(tr('type_inst_name')),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: x.instituteName,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.danger.withValues(alpha: .5), width: 1.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.danger, width: 2)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: SoftButton(label: tr('cancel'), color: p.cardAlt, textColor: p.ink, height: 54, onPressed: _busy ? null : () => Navigator.pop(context))),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: !_owner || _nameOk ? 1 : .45,
                child: Material(
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _busy || (_owner && !_nameOk) ? null : _go,
                    child: SizedBox(
                      height: 54,
                      child: Center(
                        child: _busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : Text(_owner ? tr('delete_forever') : (pending ? tr('yes_cancel') : tr('yes_leave')),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.color, required this.label, required this.onTap, this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String? value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (value != null) Text(value!, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
        Icon(Icons.chevron_right_rounded, color: p.muted),
      ]),
    );
  }
}

/// Sun / moon switch: the knob slides, the sky changes colour, stars fade in.
class ThemeSwitch extends StatelessWidget {
  const ThemeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => app.setTheme(dark ? ThemeMode.light : ThemeMode.dark),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
        width: 76,
        height: 40,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: dark ? const [Color(0xFF1E1B4B), Color(0xFF312E81)] : const [Color(0xFF7DD3FC), Color(0xFF38BDF8)]),
        ),
        child: Stack(children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 400),
            opacity: dark ? 1 : 0,
            child: const Padding(
              padding: EdgeInsets.only(left: 6, top: 4),
              child: Text('✦ ·', style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
          AnimatedAlign(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutBack,
            alignment: dark ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0xFFE2E8F0) : const Color(0xFFFFD43B),
                boxShadow: [BoxShadow(color: (dark ? Colors.white : const Color(0xFFFFB300)).withValues(alpha: .5), blurRadius: 10)],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (c, a) => RotationTransition(turns: Tween(begin: .5, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
                child: Icon(dark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                    key: ValueKey(dark), size: 19, color: dark ? const Color(0xFF312E81) : const Color(0xFFB45309)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
