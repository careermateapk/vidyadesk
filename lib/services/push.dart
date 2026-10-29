import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import '../data/backend.dart';
import '../data/models.dart';

/// Shows messages that arrive while the app is open.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Phone notifications through Firebase Cloud Messaging topics.
///   l_<inst>         every student and parent of an institute
///   s_<inst>         every teacher and admin
///   a_<inst>         admins
///   b_<inst>_<batch> one batch (its students and their parents)
///   u_<inst>_<uid>   one person (a parent also listens to each child's)
class Push {
  static bool get enabled => firebaseConfigured;
  static bool _listening = false;

  /// Called when a notification may have changed my roles or plan (removed, approved, plan).
  static void Function()? onChange;

  /// Called on any message while the app is open (to refresh the "new" numbers).
  static void Function()? onNew;

  static String learners(String inst) => 'l_$inst';
  static String staff(String inst) => 's_$inst';
  static String admins(String inst) => 'a_$inst';
  static String batch(String inst, String b) => 'b_${inst}_$b';
  static String person(String inst, String uid) => 'u_${inst}_$uid';

  /// Ask permission and listen to the topics of all my roles.
  static Future<void> sync(Backend backend, List<Membership> mine) async {
    if (!enabled) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      if (!_listening) {
        _listening = true;
        FirebaseMessaging.onMessageOpenedApp.listen((_) => onChange?.call());
        fm.getInitialMessage().then((m) {
          if (m != null) onChange?.call();
        });
        FirebaseMessaging.onMessage.listen((m) {
          if (const {'removed', 'approved', 'plan'}.contains(m.data['kind'])) onChange?.call();
          onNew?.call();
          // My own message (e.g. admin approving someone) — no pop-up for me.
          if (m.data['from'] != null && m.data['from'] == FirebaseAuth.instance.currentUser?.uid) return;
          final n = m.notification;
          if (n == null) return;
          messengerKey.currentState?.showSnackBar(SnackBar(
            duration: const Duration(seconds: 5),
            content: Text([n.title, n.body].whereType<String>().where((x) => x.isNotEmpty).join('\n')),
          ));
        });
      }
      final want = <String>{'all'};
      for (final m in mine) {
        if (m.status == MemberStatus.rejected) continue;
        final i = m.instituteId;
        want.add(person(i, m.uid));
        if (!m.approved) continue;
        switch (m.role) {
          case Role.admin:
            want.addAll([admins(i), staff(i)]);
          case Role.teacher:
            want.add(staff(i));
          case Role.student:
            want.add(learners(i));
            want.addAll(m.batchIds.map((b) => batch(i, b)));
          case Role.parent:
            want.add(learners(i));
            for (final c in m.childUids) {
              want.add(person(i, c));
              try {
                final att = await backend.attendanceForStudent(i, c);
                want.addAll(att.map((a) => batch(i, a.batchId)));
              } catch (_) {}
            }
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final had = (prefs.getStringList('pushTopics') ?? const []).toSet();
      for (final t in want.difference(had)) {
        await fm.subscribeToTopic(t);
      }
      for (final t in had.difference(want)) {
        await fm.unsubscribeFromTopic(t);
      }
      await prefs.setStringList('pushTopics', want.toList());
    } catch (_) {
      // notifications are a bonus — never block the app
    }
  }

  /// On logout: stop all notifications for this phone.
  /// Owner: one notification to every VidyaDesk user.
  static Future<bool> broadcast(String title, String body) async {
    if (notifyUrl.isEmpty) return false;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return false;
      final r = await http
          .post(Uri.parse(notifyUrl), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode({'action': 'broadcast', 'title': title, 'body': body}))
          .timeout(const Duration(seconds: 20));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear() async {
    if (!enabled) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pushTopics');
    } catch (_) {}
  }

  /// Send a notification (checked by our server). Fire and forget.
  static Future<void> send({required String inst, required String kind, required String title, required String body, required List<String> topics}) async {
    if (!enabled || notifyUrl.isEmpty || topics.isEmpty) return;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      await http
          .post(
            Uri.parse(notifyUrl),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode({'inst': inst, 'kind': kind, 'title': title, 'body': body, 'topics': topics.take(5).toList()}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}
