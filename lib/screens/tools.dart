import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../ui/widgets.dart';
import 'attendance.dart';
import 'common.dart';
import 'doubts.dart';
import 'notices.dart';
import 'resources.dart';
import 'schedule.dart';
import 'tests.dart';

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
        (Icons.quiz_rounded, tr('tests'), p.success, () => go(TestsPage(m: m))),
        (Icons.forum_rounded, tr('doubts'), p.warn, () => go(DoubtsPage(m: m))),
        (Icons.campaign_rounded, tr('nav_notices'), p.danger, () => go(NoticesPage(m: m, back: true))),
      ] else ...[
        if (m.role == Role.student)
          (Icons.fact_check_rounded, tr('attendance'), p.success, () => go(MyAttendancePage(m: m, studentUid: studentUid, studentName: studentName, back: true)))
        else
          (Icons.calendar_month_rounded, tr('nav_schedule'), p.indigo, () => go(ScheduleScreen(m: m))),
        (Icons.emoji_events_rounded, tr('results'), p.warn, () => go(TestsPage(m: m))),
        (Icons.forum_rounded, tr('doubts'), p.brand, () => go(DoubtsPage(m: m))),
        (Icons.campaign_rounded, tr('nav_notices'), p.danger, () => go(NoticesPage(m: m, back: true))),
      ],
    ];
    return Row(children: [
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
  }
}
