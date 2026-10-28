import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'attendance.dart';
import 'batches.dart';
import 'fees.dart';
import 'learner_home.dart';
import 'notices.dart';
import 'people.dart';
import 'settings.dart';
import 'staff_home.dart';

class _Tab {
  const _Tab(this.icon, this.activeIcon, this.label, this.page);
  final IconData icon, activeIcon;
  final String label;
  final Widget page;
}

/// Bottom navigation for the logged-in, approved person. Tabs depend on the role.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.m});
  final Membership m;

  @override
  State<HomeShell> createState() => HomeShellState();

  static HomeShellState? of(BuildContext context) => context.findAncestorStateOfType<HomeShellState>();
}

class HomeShellState extends State<HomeShell> {
  int _i = 0;
  int _child = 0;

  int get childIndex => _child;
  void setChild(int i) => setState(() => _child = i);
  void goTo(int tab) => setState(() => _i = tab);

  List<_Tab> _tabs() {
    final m = widget.m;
    final home = _Tab(Icons.home_outlined, Icons.home_rounded, tr('nav_home'), switch (m.role) {
      Role.admin || Role.teacher => StaffHome(m: m),
      Role.student => StudentHome(m: m),
      Role.parent => ParentHome(m: m, childIndex: _child, onChild: setChild),
    });
    final notices = _Tab(Icons.campaign_outlined, Icons.campaign_rounded, tr('nav_notices'), NoticesPage(m: m));
    final more = _Tab(Icons.person_outline_rounded, Icons.person_rounded, tr('nav_more'), SettingsPage(m: m));
    switch (m.role) {
      case Role.admin:
        return [
          home,
          _Tab(Icons.class_outlined, Icons.class_rounded, tr('nav_batches'), BatchesPage(m: m)),
          _Tab(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, tr('nav_fees'), FeesPage(m: m)),
          notices,
          more,
        ];
      case Role.teacher:
        return [
          home,
          _Tab(Icons.class_outlined, Icons.class_rounded, tr('nav_batches'), BatchesPage(m: m)),
          _Tab(Icons.groups_outlined, Icons.groups_rounded, tr('nav_students'), PeoplePage(m: m)),
          notices,
          more,
        ];
      case Role.student:
        return [
          home,
          _Tab(Icons.fact_check_outlined, Icons.fact_check_rounded, tr('nav_attendance'), MyAttendancePage(m: m, studentUid: m.uid, studentName: m.name)),
          _Tab(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, tr('nav_fees'), MyFeesPage(m: m, studentUid: m.uid, studentName: m.name)),
          notices,
          more,
        ];
      case Role.parent:
        final ci = _child.clamp(0, m.childUids.isEmpty ? 0 : m.childUids.length - 1);
        final cu = m.childUids.isEmpty ? '' : m.childUids[ci];
        final cn = m.childNames.length > ci ? m.childNames[ci] : '';
        return [
          home,
          _Tab(Icons.fact_check_outlined, Icons.fact_check_rounded, tr('nav_attendance'), MyAttendancePage(key: ValueKey('att-$cu'), m: m, studentUid: cu, studentName: cn)),
          _Tab(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, tr('nav_fees'), MyFeesPage(key: ValueKey('fee-$cu'), m: m, studentUid: cu, studentName: cn)),
          notices,
          more,
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tabs = _tabs();
    final i = _i.clamp(0, tabs.length - 1);
    return PopScope(
      canPop: i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _i = 0);
      },
      child: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          child: KeyedSubtree(key: ValueKey('tab$i-$_child'), child: tabs[i].page),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => _i = v),
          backgroundColor: p.card,
          indicatorColor: p.brandTint,
          height: 68,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final t in tabs)
              NavigationDestination(
                icon: Icon(t.icon, color: p.muted),
                selectedIcon: Icon(t.activeIcon, color: p.brand),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}
