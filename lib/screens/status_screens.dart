import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/mascot.dart';
import '../ui/widgets.dart';
import 'subscription.dart' show Confetti;

/// Shown when the admin removed me from a coaching.
class RemovedScreen extends StatelessWidget {
  const RemovedScreen({super.key, required this.institute});
  final String institute;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final others = app.memberships.where((m) => m.status != MemberStatus.rejected).toList();
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 50, 24, 30), children: [
          const Center(child: Floaty(child: Mascot(size: 160, book: false))),
          const SizedBox(height: 8),
          Text(trf('removed_title', {'inst': institute}), textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(tr('removed_sub'), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 14, height: 1.5)),
          const SizedBox(height: 26),
          if (others.isNotEmpty) ...[
            PrimaryButton(label: tr('go_to_other_role'), onPressed: app.dismissRemoved),
            const SizedBox(height: 10),
            SoftButton(label: tr('logout'), onPressed: app.signOut),
          ] else ...[
            PrimaryButton(label: tr('login_again'), onPressed: app.signOut),
            const SizedBox(height: 10),
            SoftButton(
              label: tr('new_account'),
              onPressed: () async {
                await app.signOut();
                app.chooseRole(null);
              },
            ),
          ],
        ]),
      ),
    );
  }
}

/// "Congratulations" for a student / parent / teacher whose request was just approved.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.m});
  final Membership m;
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    final m = widget.m;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: IgnorePointer(child: Confetti(animation: _a))),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 60, 24, 30), children: [
            ScaleTransition(
              scale: CurvedAnimation(parent: _a, curve: const Interval(0, .35, curve: Curves.elasticOut)),
              child: const Center(child: Mascot(size: 180, book: false, wave: true)),
            ),
            const SizedBox(height: 8),
            Text(tr('congrats'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(trf('welcome_in', {'inst': m.instituteName, 'role': tr('role_${m.role.name}')}), textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 15, height: 1.5)),
            const SizedBox(height: 28),
            PrimaryButton(
              label: tr('lets_start'),
              onPressed: () {
                if (app.active?.id != m.id) app.switchTo(m);
                app.dismissWelcome();
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
