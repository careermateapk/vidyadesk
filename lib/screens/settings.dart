import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'auth.dart';
import 'common.dart';
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
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x66FFFFFF), width: 2)),
                child: ClipOval(child: Avatar(name, size: 58)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                  Text(u?.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Tag('${roleName(m.role)} · ${m.instituteName}', fg: const Color(0xFF073B3F), bg: const Color(0xFFFFD27A)),
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
          item(SectionTitle(tr('my_roles'))),
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
                  Text(tr('switch'), style: TextStyle(color: p.brand, fontWeight: FontWeight.w800)),
              ]),
            )),
          item(SoftButton(label: tr('add_role'), icon: Icons.add_rounded, onPressed: () => _addRole(context))),

          // ----- institute tools -----
          if (m.isStaff) ...[
            item(SectionTitle(tr('institute'))),
            item(AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                if (m.role == Role.admin)
                  _Tile(icon: Icons.qr_code_2_rounded, color: p.success, label: tr('institute_code'), onTap: () => push(context, InstituteCodeScreen(m: m))),
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
            Text(tr('add_role'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
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
