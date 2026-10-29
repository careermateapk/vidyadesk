import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'attendance.dart';
import 'admissions.dart';
import 'common.dart';
import 'doubts.dart';
import 'money.dart';
import 'notices.dart';
import 'reports.dart';
import 'resources.dart';
import 'schedule.dart';
import 'tests.dart';
import 'subscription.dart';
import '../core/plan.dart';

/// Admin-only money shortcuts.
class AdminToolsRow extends StatelessWidget {
  const AdminToolsRow({super.key, required this.m, this.onBack});
  final Membership m;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    Future<void> go(Widget page) async {
      await push(context, page);
      onBack?.call();
    }

    return _tiles(counts: [0, 0, 0, app.badges['admissions'] ?? 0], [
      (Icons.savings_rounded, tr('accounts'), p.success, () => gated(context, Feature.accounts, () => go(AccountsScreen(m: m)))),
      (Icons.payments_rounded, tr('payroll'), p.indigo, () => gated(context, Feature.payroll, () => go(PayrollScreen(m: m)))),
      (Icons.bar_chart_rounded, tr('reports'), p.brand, () => gated(context, Feature.reports, () => go(ReportsScreen(m: m)))),
      (Icons.person_search_rounded, tr('admissions'), p.warn, () => gated(context, Feature.admissions, () {
            app.markSeen('admissions');
            go(AdmissionsScreen(m: m));
          })),
    ]);
  }
}

Widget _tiles(List<(IconData, String, Color, VoidCallback)> items, {List<int> counts = const []}) => Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: AppCard(
            onTap: items[i].$4,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            radius: 18,
            child: Column(children: [
              CountBadge(
                count: i < counts.length ? counts[i] : 0,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: items[i].$3.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)),
                  child: Icon(items[i].$1, color: items[i].$3, size: 22),
                ),
              ),
              const SizedBox(height: 7),
              Text(items[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ],
    ]);

/// Row of four shortcut tiles on the home screens.
class ToolsRow extends StatelessWidget {
  const ToolsRow({super.key, required this.m, this.onBack, this.studentUid = '', this.studentName = ''});
  final Membership m;
  final VoidCallback? onBack;
  final String studentUid, studentName;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.app;
    Future<void> go(Widget page, [String seen = '']) async {
      if (seen.isNotEmpty) app.markSeen(seen);
      await push(context, page);
      onBack?.call();
      app.loadBadges();
    }

    final b = app.badges;
    // Teachers, students, parents never see what the admin's plan does not have.
    final hide = m.role != Role.admin;
    final tests = !hide || planHas(context, Feature.tests);
    final doubts = !hide || planHas(context, Feature.doubts);
    final all = <((IconData, String, Color, VoidCallback), int)>[
      if (m.isStaff) ...[
        ((Icons.folder_copy_rounded, tr('nav_resources'), const Color(0xFF0EA5B7), () => go(ResourcesPage(m: m, back: true))), 0),
        if (tests) ((Icons.quiz_rounded, tr('tests'), p.success, () => gated(context, Feature.tests, () => go(TestsPage(m: m)))), 0),
        if (doubts) ((Icons.forum_rounded, tr('doubts'), p.warn, () => gated(context, Feature.doubts, () => go(DoubtsPage(m: m), 'doubts'))), b['doubts'] ?? 0),
        ((Icons.campaign_rounded, tr('nav_notices'), p.danger, () => go(NoticesPage(m: m, back: true))), 0),
      ] else ...[
        if (m.role == Role.student)
          ((Icons.fact_check_rounded, tr('attendance'), p.success, () => go(MyAttendancePage(m: m, studentUid: studentUid, studentName: studentName, back: true))), 0)
        else
          ((Icons.calendar_month_rounded, tr('nav_schedule'), p.indigo, () => go(ScheduleScreen(m: m))), 0),
        if (tests) ((Icons.emoji_events_rounded, tr('results'), p.warn, () => go(TestsPage(m: m), 'results')), b['results'] ?? 0),
        if (doubts) ((Icons.forum_rounded, tr('doubts'), p.brand, () => go(DoubtsPage(m: m), 'doubts')), b['doubts'] ?? 0),
        ((Icons.campaign_rounded, tr('nav_notices'), p.danger, () => go(NoticesPage(m: m, back: true), 'notices')), b['notices'] ?? 0),
      ],
    ];
    final items = [for (final x in all) x.$1];
    final counts = [for (final x in all) x.$2];
    return _tiles(items, counts: counts);
  }
}
