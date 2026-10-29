import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/plan.dart';
import '../core/strings.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../services/upi.dart';
import '../ui/widgets.dart';

/// Batches this person looks after: admin sees all, teacher sees own.
List<Batch> myBatches(Membership m, List<Batch> all) => m.role == Role.admin ? all : all.where((b) => b.teacherUid == m.uid).toList();

List<Membership> approvedStudents(List<Membership> members, {String? batchId}) => members
    .where((x) => x.role == Role.student && x.approved && (batchId == null || x.batchIds.contains(batchId)))
    .toList()
  ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Pending requests this person may approve.
List<Membership> pendingFor(Membership me, List<Membership> members, List<Batch> batches) {
  final pend = members.where((x) => x.status == MemberStatus.pending).toList();
  if (me.role == Role.admin) return pend;
  final mine = batches.where((b) => b.teacherUid == me.uid).map((b) => b.id).toSet();
  final myStudents = members.where((x) => x.role == Role.student && x.batchIds.any(mine.contains)).map((x) => x.uid).toSet();
  return pend.where((x) {
    if (x.role == Role.student) return x.batchIds.any(mine.contains);
    if (x.role == Role.parent) return x.childUids.any(myStudents.contains);
    return false;
  }).toList();
}

String monthLabel(String key) {
  final parts = key.split('-');
  if (parts.length != 2) return key;
  final m = int.tryParse(parts[1]) ?? 1;
  return '${tr('m$m')} ${parts[0]}';
}

String prettyDate(DateTime d) => '${d.day} ${tr('m${d.month}')} ${d.year}';
String prettyDay(DateTime d) => '${dayShort(d.weekday)}, ${d.day} ${tr('m${d.month}')}';

String greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return tr('good_morning');
  if (h < 17) return tr('good_afternoon');
  return tr('good_evening');
}

String firstName(String n) => n.trim().split(RegExp(r'\s+')).first;

String digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

Future<void> openWhatsApp(BuildContext context, String phone, String text) async {
  final d = digitsOnly(phone);
  final uri = Uri.parse('https://wa.me/${d.length == 10 ? '91$d' : d}?text=${Uri.encodeComponent(text)}');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) toast(context, tr('err_whatsapp'));
}

Future<void> callPhone(BuildContext context, String phone) async {
  final ok = await launchUrl(Uri.parse('tel:${phone.replaceAll(' ', '')}')).catchError((_) => false);
  if (!ok && context.mounted) toast(context, tr('err_call'));
}

/// Percentage of class days a student was present, from attendance days.
({int present, int total}) attendanceCount(String uid, List<AttendanceDay> days) {
  var p = 0, t = 0;
  for (final d in days) {
    if (!d.marked.contains(uid)) continue;
    t++;
    if (d.present.contains(uid)) p++;
  }
  return (present: p, total: t);
}

int pct(int a, int b) => b == 0 ? 0 : (a * 100 / b).round();

/// Batch's next class time as a short text ("Today 5:00 PM", "Tue 7:00 AM").
String nextClassText(Batch b) {
  final now = DateTime.now();
  final nowMin = now.hour * 60 + now.minute;
  for (var add = 0; add < 8; add++) {
    final d = now.add(Duration(days: add));
    if (!b.days.contains(d.weekday)) continue;
    if (add == 0 && nowMin > b.endMin) continue;
    final when = add == 0 ? tr('today') : (add == 1 ? tr('tomorrow') : dayShort(d.weekday));
    return '$when · ${timeLabel(b.startMin)}';
  }
  return timeLabel(b.startMin);
}

String errorMessage(Object e) {
  final denied = (e is BackendError && e.code == 'permission') || e.toString().contains('permission-denied');
  if (denied && planReadOnly) return tr('err_plan_readonly');
  if (denied) return tr('err_permission');
  if (e is BackendError) {
    final k = 'err_${e.code}';
    final t = tr(k);
    if (t != k) return t;
  }
  return tr('err_unknown');
}

/// Push a screen and wait until it closes.
Future<T?> push<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => Backdrop(child: page),
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: c, child: SlideTransition(position: Tween(begin: const Offset(.08, 0), end: Offset.zero).animate(c), child: child));
      },
    ));


/// A UPI app's own icon from the phone (or its first letter when the phone gives none).
class UpiIcon extends StatelessWidget {
  const UpiIcon(this.app, {super.key, this.size = 38});
  final UpiApp app;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (app.icon != null) {
      return ClipRRect(borderRadius: BorderRadius.circular(size * .28), child: Image.memory(app.icon!, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true));
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Color(app.color), borderRadius: BorderRadius.circular(size * .28)),
      child: Text(app.letter, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * .34)),
    );
  }
}
