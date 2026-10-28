import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'attendance.dart';
import 'batches.dart';
import 'common.dart';
import 'fees.dart';
import 'learner_home.dart';
import 'notices.dart';
import 'people.dart';
import 'resources.dart';
import 'schedule.dart';
import 'settings.dart';
import 'staff_home.dart';
import 'tests.dart';

class _Tab {
  const _Tab(this.icon, this.activeIcon, this.label, this.page);
  final IconData icon, activeIcon;
  final String label;
  final Widget page;
}

/// Bottom navigation for the logged-in, approved person. Tabs depend on the role.
/// Staff get a big centre "+" button for quick actions.
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
  int _refresh = 0;

  @override
  void initState() {
    super.initState();
    context.appRead.childIndex = 0;
  }

  int get childIndex => _child;
  void setChild(int i) {
    context.appRead.childIndex = i;
    setState(() => _child = i);
  }

  /// Go to a tab by its index in the tab list.
  void goTo(int tab) => setState(() => _i = tab);

  /// Go to the tab that shows [page] type, e.g. 'fees'.
  void goToNamed(String name) {
    final i = _names().indexOf(name);
    if (i >= 0) setState(() => _i = i);
  }

  void reloadAll() => setState(() => _refresh++);

  List<String> _names() => switch (widget.m.role) {
        Role.admin => ['home', 'batches', 'fees', 'profile'],
        Role.teacher => ['home', 'batches', 'students', 'profile'],
        Role.student => ['home', 'schedule', 'resources', 'fees', 'profile'],
        Role.parent => ['home', 'attendance', 'resources', 'fees', 'profile'],
      };

  List<_Tab> _tabs() {
    final m = widget.m;
    final home = _Tab(Icons.home_outlined, Icons.home_rounded, tr('nav_home'), switch (m.role) {
      Role.admin || Role.teacher => StaffHome(m: m),
      Role.student => StudentHome(m: m),
      Role.parent => ParentHome(m: m, childIndex: _child, onChild: setChild),
    });
    final more = _Tab(Icons.person_outline_rounded, Icons.person_rounded, tr('nav_more'), SettingsPage(m: m));
    switch (m.role) {
      case Role.admin:
        return [
          home,
          _Tab(Icons.layers_outlined, Icons.layers_rounded, tr('nav_batches'), BatchesPage(m: m)),
          _Tab(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, tr('nav_fees'), FeesPage(m: m)),
          more,
        ];
      case Role.teacher:
        return [
          home,
          _Tab(Icons.layers_outlined, Icons.layers_rounded, tr('nav_batches'), BatchesPage(m: m)),
          _Tab(Icons.groups_outlined, Icons.groups_rounded, tr('nav_students'), PeoplePage(m: m)),
          more,
        ];
      case Role.student:
        return [
          home,
          _Tab(Icons.calendar_month_outlined, Icons.calendar_month_rounded, tr('nav_schedule'), ScheduleScreen(m: m, tab: true)),
          _Tab(Icons.folder_copy_outlined, Icons.folder_copy_rounded, tr('nav_resources'), ResourcesPage(m: m)),
          _Tab(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, tr('nav_fees'), MyFeesPage(m: m, studentUid: m.uid, studentName: m.name)),
          more,
        ];
      case Role.parent:
        final ci = _child.clamp(0, m.childUids.isEmpty ? 0 : m.childUids.length - 1);
        final cu = m.childUids.isEmpty ? '' : m.childUids[ci];
        final cn = m.childNames.length > ci ? m.childNames[ci] : '';
        return [
          home,
          _Tab(Icons.fact_check_outlined, Icons.fact_check_rounded, tr('nav_attendance'), MyAttendancePage(key: ValueKey('att-$cu'), m: m, studentUid: cu, studentName: cn)),
          _Tab(Icons.folder_copy_outlined, Icons.folder_copy_rounded, tr('nav_resources'), ResourcesPage(key: ValueKey('res-$cu'), m: m)),
          _Tab(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, tr('nav_fees'), MyFeesPage(key: ValueKey('fee-$cu'), m: m, studentUid: cu, studentName: cn)),
          more,
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final i = _i.clamp(0, tabs.length - 1);
    final staff = widget.m.isStaff;
    return PopScope(
      canPop: i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _i = 0);
      },
      child: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween(begin: const Offset(0, .015), end: Offset.zero).animate(a), child: c),
          ),
          child: KeyedSubtree(key: ValueKey('tab$i-$_child-$_refresh'), child: tabs[i].page),
        ),
        bottomNavigationBar: _FloatingNav(
          tabs: tabs,
          index: i,
          onTap: (v) => setState(() => _i = v),
          onPlus: staff ? () => showQuickAdd(context, widget.m, shell: this) : null,
        ),
      ),
    );
  }
}

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({required this.tabs, required this.index, required this.onTap, this.onPlus});
  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final items = <Widget>[];
    for (var k = 0; k < tabs.length; k++) {
      if (onPlus != null && k == tabs.length ~/ 2) items.add(_Plus(onTap: onPlus!));
      items.add(Expanded(child: _NavItem(tab: tabs[k], on: k == index, onTap: () => onTap(k))));
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.border),
            boxShadow: [BoxShadow(color: (p.dark ? Colors.black : const Color(0xFF281E78)).withValues(alpha: p.dark ? .5 : .22), blurRadius: 30, offset: const Offset(0, 12), spreadRadius: -12)],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: items),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.tab, required this.on, required this.onTap});
  final _Tab tab;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(horizontal: on ? 16 : 6, vertical: 4),
          decoration: BoxDecoration(color: on ? p.brandTint : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Icon(on ? tab.activeIcon : tab.icon, size: 23, color: on ? p.brand : p.muted),
        ),
        const SizedBox(height: 3),
        Text(tab.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? p.brand : p.muted)),
      ]),
    );
  }
}

class _Plus extends StatelessWidget {
  const _Plus({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Pressable(
          child: Transform.translate(
            offset: const Offset(0, -16),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: p.button,
                boxShadow: [...p.glow(p.brand), BoxShadow(color: p.bg, spreadRadius: 5)],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick add sheet
// ---------------------------------------------------------------------------

Future<void> showQuickAdd(BuildContext context, Membership m, {HomeShellState? shell}) async {
  final p = context.pal;
  shell ??= HomeShell.of(context);
  final admin = m.role == Role.admin;
  final pick = await showModalBottomSheet<String>(
    context: context,
    builder: (c) {
      Widget tile(String id, IconData icon, String label, Color fg, Color bg, int i) => FadeIn(
            delay: stagger(i, startMs: 20, stepMs: 40),
            child: GestureDetector(
              onTap: () => Navigator.pop(c, id),
              child: Pressable(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                  decoration: BoxDecoration(color: p.cardAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.border)),
                  child: Column(children: [
                    IconBox(icon, fg: fg, bg: bg, size: 48),
                    const SizedBox(height: 8),
                    Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2)),
                  ]),
                ),
              ),
            ),
          );
      final tiles = [
        tile('att', Icons.fact_check_outlined, tr('mark_attendance'), p.success, p.successTint, 0),
        if (admin) tile('fee', Icons.currency_rupee_rounded, tr('collect_fee'), p.warn, p.warnTint, 1),
        tile('notice', Icons.campaign_outlined, tr('send_notice'), p.danger, p.dangerTint, 2),
        tile('batch', Icons.layers_outlined, tr('new_batch'), p.brand, p.brandTint, 3),
        tile('week', Icons.calendar_month_outlined, tr('week_schedule'), p.indigo, p.indigoTint, 4),
        tile('invite', Icons.person_add_alt_1_outlined, tr('invite_people'), p.brand, p.brandTint, 5),
        tile('res', Icons.folder_copy_outlined, tr('add_resource'), const Color(0xFF0EA5B7), const Color(0xFF0EA5B7).withValues(alpha: .13), 6),
        tile('hw', Icons.edit_note_rounded, tr('give_homework'), p.warn, p.warnTint, 7),
        tile('test', Icons.quiz_outlined, tr('tests_marks'), p.success, p.successTint, 8),
      ];
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('quick_add'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3)),
            Text(tr('quick_add_sub'), style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: .98,
              children: tiles,
            ),
          ]),
        ),
      );
    },
  );
  if (pick == null || !context.mounted) return;
  final b = context.appRead.backend;
  switch (pick) {
    case 'fee':
      shell?.goToNamed('fees');
    case 'notice':
      final batches = myBatches(m, await b.batches(m.instituteId));
      if (context.mounted) await push(context, PostNoticeScreen(m: m, batches: batches));
    case 'batch':
      final members = await b.members(m.instituteId);
      if (context.mounted) await push(context, CreateBatchScreen(m: m, members: members));
    case 'week':
      await push(context, ScheduleScreen(m: m));
    case 'res' || 'hw':
      final batches = myBatches(m, await b.batches(m.instituteId));
      if (context.mounted) await push(context, AddResourceScreen(m: m, batches: batches, kind: pick == 'hw' ? 'homework' : null));
    case 'test':
      await push(context, TestsPage(m: m));
    case 'invite':
      if (admin) {
        await push(context, InstituteCodeScreen(m: m));
      } else {
        shell?.goToNamed('batches');
      }
    case 'att':
      final all = myBatches(m, await b.batches(m.instituteId));
      if (!context.mounted) return;
      final now = DateTime.now();
      final list = [...all]..sort((a, c) {
          final ra = a.runsOn(now) ? 0 : 1, rc = c.runsOn(now) ? 0 : 1;
          return ra != rc ? ra - rc : a.startMin - c.startMin;
        });
      if (list.isEmpty) {
        toast(context, tr('no_batches_yet'));
        return;
      }
      final batch = list.length == 1 ? list.first : await _pickBatch(context, list);
      if (batch != null && context.mounted) await push(context, MarkAttendanceScreen(m: m, batch: batch));
  }
  shell?.reloadAll();
}

Future<Batch?> _pickBatch(BuildContext context, List<Batch> list) {
  final p = context.pal;
  final now = DateTime.now();
  return showModalBottomSheet<Batch>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('which_batch'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final b in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.all(12),
                onTap: () => Navigator.pop(c, b),
                child: Row(children: [
                  IconBox(Icons.layers_outlined, fg: p.brand, bg: p.brandTint),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${daysCode(b.days)} · ${timeLabel(b.startMin)}', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  if (b.runsOn(now)) Tag(tr('today'), fg: p.success, bg: p.successTint),
                ]),
              ),
            ),
        ]),
      ),
    ),
  );
}
