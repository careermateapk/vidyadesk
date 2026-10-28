import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';

// ---------------------------------------------------------------------------
// Splash
// ---------------------------------------------------------------------------

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _logo = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  late final AnimationController _bar = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..forward();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 2300), () {
      if (mounted) context.appRead.finishSplash();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _logo.dispose();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = CurvedAnimation(parent: _logo, curve: Curves.elasticOut);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF0E6A70), Color(0xFF073B3F), Color(0xFF041F22)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Stack(children: [
          const Positioned(top: -120, right: -120, child: _Glow(size: 360, color: Color(0x66F5A524))),
          const Positioned(bottom: -140, left: -120, child: _Glow(size: 380, color: Color(0x5514B8A6))),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: logo,
                builder: (context, child) => Transform.scale(scale: logo.value, child: Transform.rotate(angle: (1 - logo.value) * -.6, child: child)),
                child: const Floaty(child: AppLogo(size: 108)),
              ),
              const SizedBox(height: 26),
              FadeIn(
                delay: const Duration(milliseconds: 400),
                child: const Text('VidyaDesk', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
              ),
              const SizedBox(height: 6),
              FadeIn(
                delay: const Duration(milliseconds: 650),
                child: Text(tr('tagline'), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 150,
                child: AnimatedBuilder(
                  animation: _bar,
                  builder: (context, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(
                      value: Curves.easeInOut.transform(_bar.value),
                      minHeight: 5,
                      backgroundColor: const Color(0x33FFFFFF),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFF5A524)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 36,
            child: FadeIn(
              delay: const Duration(milliseconds: 900),
              child: Text(tr('made_in_india'), textAlign: TextAlign.center, style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Floaty(
        amount: 14,
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]))),
      );
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
    return Scaffold(
      appBar: widget.firstTime ? null : InnerBar(title: tr('language')),
      body: SafeArea(
        top: widget.firstTime,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          children: [
            if (widget.firstTime) ...[
              FadeIn(child: Row(children: [const AppLogo(size: 44), const SizedBox(width: 10), Text('VidyaDesk', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: p.brand))])),
              const SizedBox(height: 28),
              FadeIn(delay: stagger(1), child: const Text('Choose your language', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.6))),
              const SizedBox(height: 4),
              FadeIn(delay: stagger(2), child: Text('अपनी भाषा चुनें · Apni bhasha chunein', style: TextStyle(color: p.muted, fontSize: 15, fontFamily: 'NotoDeva'))),
              const SizedBox(height: 24),
            ],
            for (var i = 0; i < _opts.length; i++)
              FadeIn(
                delay: stagger(i + 3),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _LangCard(
                    code: _opts[i].$1,
                    title: _opts[i].$2,
                    sample: _opts[i].$3,
                    glyph: _opts[i].$4,
                    selected: _sel == _opts[i].$1,
                    isDefault: i == 0,
                    onTap: () {
                      setState(() => _sel = _opts[i].$1);
                      if (!widget.firstTime) context.appRead.setLanguage(_opts[i].$1);
                    },
                  ),
                ),
              ),
            const SizedBox(height: 10),
            if (widget.firstTime)
              FadeIn(
                delay: stagger(7),
                child: PrimaryButton(label: 'Continue', onPressed: () => context.appRead.setLanguage(_sel)),
              ),
            if (!widget.firstTime)
              Text(tr('lang_change_note'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _LangCard extends StatelessWidget {
  const _LangCard({required this.code, required this.title, required this.sample, required this.glyph, required this.selected, required this.isDefault, required this.onTap});
  final String code, title, sample, glyph;
  final bool selected, isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final deva = code == 'hi';
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? p.brandTint : p.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? p.brand : p.border, width: selected ? 2 : 1),
          boxShadow: selected ? p.shadow : null,
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            width: 52,
            height: 52,
            decoration: BoxDecoration(gradient: selected ? p.gold : null, color: selected ? null : p.cardAlt, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: Text(glyph, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: selected ? const Color(0xFF073B3F) : p.brand, fontFamily: deva ? 'NotoDeva' : null)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFamily: deva ? 'NotoDeva' : null)),
                if (isDefault) ...[const SizedBox(width: 8), Tag('Default', fg: p.warn, bg: p.warnTint)],
              ]),
              const SizedBox(height: 2),
              Text(sample, style: TextStyle(color: p.muted, fontSize: 14, fontFamily: deva ? 'NotoDeva' : null)),
            ]),
          ),
          AnimatedScale(
            scale: selected ? 1 : 0,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, size: 18, color: p.dark ? const Color(0xFF0B1220) : Colors.white),
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
      Role.admin => Icons.business_center_rounded,
      Role.teacher => Icons.co_present_rounded,
      Role.student => Icons.school_rounded,
      Role.parent => Icons.family_restroom_rounded,
    };

String roleName(Role r) => tr('role_${r.name}');

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final colors = [
      (p.brand, p.brandTint),
      (p.indigo, p.indigoTint),
      (p.warn, p.warnTint),
      (p.success, p.successTint),
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          children: [
            FadeIn(
              child: Row(children: [
                const AppLogo(size: 40),
                const SizedBox(width: 10),
                Text('VidyaDesk', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: p.brand)),
                const Spacer(),
                if (app.signedIn != null)
                  TextButton(onPressed: () => app.signOut(), child: Text(tr('logout')))
                else
                  IconButton(
                    tooltip: tr('language'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LanguageScreen())),
                    icon: Icon(Icons.translate_rounded, color: p.brand),
                  ),
              ]),
            ),
            const SizedBox(height: 26),
            FadeIn(delay: stagger(1), child: Text(tr('who_are_you'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.6))),
            const SizedBox(height: 4),
            FadeIn(delay: stagger(2), child: Text(tr('who_are_you_sub'), style: TextStyle(color: p.muted, fontSize: 15))),
            const SizedBox(height: 22),
            for (var i = 0; i < Role.values.length; i++)
              FadeIn(
                delay: stagger(i + 3, stepMs: 80),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    onTap: () => app.chooseRole(Role.values[i]),
                    child: Row(children: [
                      IconBox(roleIcon(Role.values[i]), fg: colors[i].$1, bg: colors[i].$2, size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(roleName(Role.values[i]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(tr('role_${Role.values[i].name}_sub'), style: TextStyle(color: p.muted, fontSize: 13, height: 1.3)),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: p.muted),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FadeIn(
              delay: stagger(8),
              child: AppCard(
                color: p.cardAlt,
                child: Row(children: [
                  Icon(Icons.lightbulb_rounded, color: p.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tr('role_tip'), style: TextStyle(fontSize: 13, color: p.muted, height: 1.35))),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yellow strip that says the app is running with sample data.
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
      decoration: BoxDecoration(color: p.warnTint, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(Icons.science_rounded, color: p.warn, size: 20),
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
