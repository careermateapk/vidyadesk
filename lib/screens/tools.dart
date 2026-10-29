import 'package:flutter/material.dart';

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
    Future<void> go(Widget page) async {
      await push(context, page);
      onBack?.call();
    }

    return _tiles([
      (Icons.savings_rounded, tr('accounts'), p.success, () => gated(context, Feature.accounts, () => go(AccountsScreen(m: m)))),
      (Icons.payments_rounded, tr('payroll'), p.indigo, () => gated(context, Feature.payroll, () => go(PayrollScreen(m: m)))),
      (Icons.bar_chart_rounded, tr('reports'), p.brand, () => gated(context, Feature.reports, () => go(ReportsScreen(m: m)))),
      (Icons.person_search_rounded, tr('admissions'), p.warn, () => gated(context, Feature.admissions, () => go(AdmissionsScreen(m: m)))),
    ]);
  }
}

Widget _tiles(List<(IconData, String, Color, VoidCallback)> items) => Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: AppCard(
            onTap: items[i].$4,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            radius: 18,
            child: Column(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: items[i].$3.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)),
                child: Icon(items[i].$1, color: items[i].$3, size: 22),
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
    Future<void> go(Widget page) async {
      await push(context, page);
      onBack?.call();
    }

    final items = <(IconData, String, Color, VoidCallback)>[
      if (m.isStaff) ...[
        (Icons.folder_copy_rounded, tr('nav_resources'), const Color(0xFF0EA5B7), () => go(ResourcesPage(m: m, back: true))),
        (Icons.quiz_rounded, tr('tests'), p.success, () => gated(context, Feature.tests, () => go(TestsPage(m: m)))),
        (Icons.forum_rounded, tr('doubts'), p.warn, () => gated(context, Feature.doubts, () => go(DoubtsPage(m: m)))),
        (Icons.campaign_rounded, tr('nav_notices'), p.danger, () => go(NoticesPage(m: m, back: true))),
      ] else ...[
        if (m.role == Role.student)
          (Icons.fact_check_rounded, tr('attendance'), p.success, () => go(MyAttendancePage(m: m, studentUid: studentUid, studentName: studentName, back: true)))
        else
          (Icons.calendar_month_rounded, tr('nav_schedule'), p.indigo, () => go(ScheduleScreen(m: m))),
        (Icons.emoji_events_rounded, tr('results'), p.warn, () => gated(context, Feature.tests, () => go(TestsPage(m: m)))),
        (Icons.forum_rounded, tr('doubts'), p.brand, () => gated(context, Feature.doubts, () => go(DoubtsPage(m: m)))),
        (Icons.campaign_rounded, tr('nav_notices'), p.danger, () => go(NoticesPage(m: m, back: true))),
      ],
    ];
    return _tiles(items);
  }
}
