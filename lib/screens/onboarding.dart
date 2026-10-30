
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/mascot.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'grand_splash.dart';

// ---------------------------------------------------------------------------
// Splash
// ---------------------------------------------------------------------------

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    // No timer: the app moves on only when "Get started" is tapped.
    return GrandSplash(ready: app.ready && app.signedIn == null, onStart: () => context.appRead.finishSplash());
  }
}

// ---------------------------------------------------------------------------
// Language
// ---------------------------------------------------------------------------

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key, this.firstTime = false});
  final bool firstTime;
  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  late String _sel = context.appRead.lang;

  static const _opts = [
    ('en', 'English', 'Hello! Welcome', 'Aa'),
    ('hi', 'हिन्दी', 'नमस्ते! स्वागत है', 'अ'),
    ('hn', 'Hinglish', 'Namaste! Swagat hai', 'Hi'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppScaffold(
      title: widget.firstTime ? null : tr('language'),
      bottom: widget.firstTime ? PrimaryButton(label: 'Continue', onPressed: () => app.setLanguage(_sel)) : null,
      body: ListView(
        padding: EdgeInsets.fromLTRB(18, widget.firstTime ? MediaQuery.of(context).padding.top + 24 : 8, 18, 24),
        children: [
          if (widget.firstTime) ...[
            FadeIn(child: Align(alignment: Alignment.centerLeft, child: IconBox(Icons.translate_rounded, fg: p.brand, bg: p.brandTint, size: 52))),
            const SizedBox(height: 18),
            FadeIn(delay: stagger(1), child: const Text('Choose your language', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.8))),
            const SizedBox(height: 6),
            FadeIn(delay: stagger(2), child: Text('अपनी भाषा चुनें · Apni bhasha chunein', style: TextStyle(color: p.muted, fontSize: 14.5, fontFamily: 'NotoDeva'))),
            const SizedBox(height: 24),
          ],
          for (var i = 0; i < _opts.length; i++)
            FadeIn(
              delay: stagger(i + 3),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _LangCard(
                  title: _opts[i].$2,
                  sample: _opts[i].$3,
                  glyph: _opts[i].$4,
                  deva: _opts[i].$1 == 'hi',
                  selected: _sel == _opts[i].$1,
                  isDefault: i == 0,
                  onTap: () {
                    setState(() => _sel = _opts[i].$1);
                    if (!widget.firstTime) app.setLanguage(_opts[i].$1);
                  },
                ),
              ),
            ),
          FadeIn(
            delay: stagger(7),
            child: AppCard(
              color: p.cardAlt,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(children: [
                Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: p.brand, size: 21),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('dark_mode'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
                Switch(value: dark, activeThumbColor: Colors.white, activeTrackColor: p.brand, onChanged: (v) => app.setTheme(v ? ThemeMode.dark : ThemeMode.light)),
              ]),
            ),
          ),
          if (!widget.firstTime) ...[
            const SizedBox(height: 14),
            Text(tr('lang_change_note'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _LangCard extends StatelessWidget {
  const _LangCard({required this.title, required this.sample, required this.glyph, required this.deva, required this.selected, required this.isDefault, required this.onTap});
  final String title, sample, glyph;
  final bool deva, selected, isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(Gap.rCard),
          border: Border.all(color: selected ? p.brand : p.border, width: selected ? 2 : 1),
          boxShadow: selected ? [...p.shadow, BoxShadow(color: p.brandTint, spreadRadius: 4)] : p.shadow,
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: selected ? p.brand : p.cardAlt, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: Text(glyph, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: selected ? Colors.white : p.brand, fontFamily: deva ? 'NotoDeva' : null)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: deva ? 'NotoDeva' : null)),
                if (isDefault) ...[const SizedBox(width: 8), Tag('Default', fg: p.warn, bg: p.warnTint)],
              ]),
              const SizedBox(height: 2),
              Text(sample, style: TextStyle(color: p.muted, fontSize: 13.5, fontWeight: FontWeight.w600, fontFamily: deva ? 'NotoDeva' : null)),
            ]),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 24,
            height: 24,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? p.brand : p.border, width: 2)),
            alignment: Alignment.center,
            child: AnimatedScale(
              scale: selected ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: Container(width: 12, height: 12, decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Role picker
// ---------------------------------------------------------------------------

IconData roleIcon(Role r) => switch (r) {
      Role.admin => Icons.apartment_rounded,
      Role.teacher => Icons.co_present_outlined,
      Role.student => Icons.school_outlined,
      Role.parent => Icons.verified_user_outlined,
    };

String roleName(Role r) => tr('role_${r.name}');

(Color, Color) roleColors(Palette p, Role r) => switch (r) {
      Role.admin => (p.brand, p.brandTint),
      Role.teacher => (p.indigo, p.indigoTint),
      Role.student => (p.warn, p.warnTint),
      Role.parent => (p.success, p.successTint),
    };

class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key});
  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  Role _sel = Role.admin;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    return AppScaffold(
      topBar: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
          child: Row(children: [
            const AppLogo(size: 34),
            const SizedBox(width: 9),
            const Expanded(child: Text('VidyaDesk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.3))),
            if (app.signedIn != null)
              IconBtn(icon: Icons.logout_rounded, tooltip: tr('logout'), onTap: () => app.signOut())
            else
              IconBtn(icon: Icons.translate_rounded, tooltip: tr('language'), onTap: () => push(context, const LanguageScreen())),
          ]),
        ),
      ),
      bottom: PrimaryButton(label: trf('continue_as', {'role': roleName(_sel)}), onPressed: () => app.chooseRole(_sel)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        children: [
          FadeIn(child: Text(tr('who_are_you'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.8))),
          const SizedBox(height: 4),
          FadeIn(delay: stagger(1), child: Text(tr('who_are_you_sub'), style: TextStyle(color: p.muted, fontSize: 14.5, fontWeight: FontWeight.w500))),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .95,
            children: [
              for (var i = 0; i < Role.values.length; i++)
                FadeIn(
                  delay: stagger(i + 2, stepMs: 70),
                  child: _RoleCard(role: Role.values[i], selected: _sel == Role.values[i], onTap: () => setState(() => _sel = Role.values[i])),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FadeIn(
            delay: stagger(7),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.brandTint, borderRadius: BorderRadius.circular(Gap.rCard)),
              child: Row(children: [
                const Mascot(size: 48, book: false),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('role_tip'), style: TextStyle(fontSize: 12.5, color: p.ink2, height: 1.45, fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
          if (app.signedIn == null) ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () => app.chooseRole(Role.admin),
                icon: Icon(Icons.verified_user_outlined, size: 18, color: p.brand),
                label: Text(tr('owner_login'), style: TextStyle(color: p.brand, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.selected, required this.onTap});
  final Role role;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = roleColors(p, role);
    return GestureDetector(
      onTap: onTap,
      child: Pressable(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(Gap.rCard),
            border: Border.all(color: selected ? p.brand : p.border, width: selected ? 2 : 1),
            boxShadow: selected ? [...p.shadow, BoxShadow(color: p.brandTint, spreadRadius: 4)] : p.shadow,
          ),
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconBox(roleIcon(role), fg: c.$1, bg: c.$2, size: 50),
              const Spacer(),
              Text(roleName(role), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.2)),
              const SizedBox(height: 2),
              Text(tr('role_${role.name}_short'), maxLines: 2, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3)),
            ]),
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedScale(
                scale: selected ? 1 : 0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Amber strip that says the app is running with sample data.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isDemo) return const SizedBox.shrink();
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: p.warnTint, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.science_outlined, color: p.warn, size: 19),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('demo_banner'), style: TextStyle(color: p.warn, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.3))),
      ]),
    );
  }
}

/// Close every pushed screen so the Gate's screen shows.
void backToRoot(BuildContext context) {
  final nav = Navigator.maybeOf(context);
  nav?.popUntil((r) => r.isFirst);
}
