import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/backend.dart';
import '../data/demo_backend.dart';
import '../data/firebase_backend.dart';
import '../data/models.dart';
import '../services/push.dart';
import '../services/upi.dart';
import 'config.dart';
import 'plan.dart';
import 'strings.dart';

/// Holds who is logged in, their roles, and the phone settings
/// (language, theme, chosen role). Screens listen to it.
class AppState extends ChangeNotifier {
  AppState();

  late Backend backend;
  SharedPreferences? _prefs;

  bool ready = false;
  bool splashDone = false;
  String? startError;

  // phone settings
  String lang = 'en';
  bool languageChosen = false;
  ThemeMode themeMode = ThemeMode.light;
  Role? chosenRole;

  // login
  SignedIn? signedIn;
  AppUser? profile;
  List<Membership> memberships = [];
  Membership? active;
  bool loadingAccount = false;

  /// Set when the admin removed me from a coaching (its name). Shows the "removed" screen.
  String? removedFrom;

  /// Remembers my approved roles, and finds ones that disappeared (removed by the admin).
  void _checkRemoved({required bool detect}) {
    final key = 'knownMems_${signedIn?.uid ?? ''}';
    Map<String, dynamic> known = {};
    try {
      known = jsonDecode(_prefs?.getString(key) ?? '{}') as Map<String, dynamic>;
    } catch (_) {}
    final now = {for (final m in memberships) if (m.approved) m.id: m.instituteName};
    // Waiting requests that are now approved → show the welcome (congratulations) screen once.
    final pkey = 'pendingMems_${signedIn?.uid ?? ''}';
    final wasPending = _prefs?.getStringList(pkey) ?? const <String>[];
    final ok = memberships.where((m) => m.approved && wasPending.contains(m.id) && m.role != Role.admin).firstOrNull;
    if (ok != null) welcome = ok;
    _prefs?.setStringList(pkey, [for (final m in memberships) if (m.status == MemberStatus.pending) m.id]);
    if (detect) {
      final gone = known.keys.where((id) => !memberships.any((m) => m.id == id)).toList();
      if (gone.isNotEmpty) removedFrom = '${known[gone.first]}';
    }
    _prefs?.setString(key, jsonEncode(now));
  }

  // ---------- "new" numbers on home tiles ----------

  /// How many new things in each section since it was last opened:
  /// doubts, results, notices, resources, admissions.
  Map<String, int> badges = {};

  /// Parent: my children's profile photos (uid → photo).
  Map<String, String> childPhotos = {};

  Future<void> loadChildPhotos() async {
    final m = active;
    if (m == null || m.role != Role.parent || m.childUids.isEmpty) return;
    try {
      childPhotos = await backend.childPhotos(m.instituteId, m.childUids);
      notifyListeners();
    } catch (_) {}
  }

  /// Test: every student/parent account can make ONE demo fee payment (no money).
  /// Turn off with [demoFeeOn] = false when testing is over.
  static const demoFeeOn = true;
  bool get demoFeeLeft => demoFeeOn && !isDemo && !(_prefs?.getBool('demoFee_${signedIn?.uid ?? ''}') ?? false);
  void useDemoFee() => _prefs?.setBool('demoFee_${signedIn?.uid ?? ''}', true);

  /// Newest unseen items for "What's new" (section, title, time).
  List<(String, String, int)> newItems = [];

  String _seenKey(String k) => 'seen_${active?.id ?? ''}_$k';

  int seenAt(String k) {
    final key = _seenKey(k);
    final v = _prefs?.getInt(key);
    if (v != null) return v;
    final now = DateTime.now().millisecondsSinceEpoch;
    _prefs?.setInt(key, now); // first time: start counting from now
    return now;
  }

  void markSeen(String k) {
    _prefs?.setInt(_seenKey(k), DateTime.now().millisecondsSinceEpoch);
    if ((badges[k] ?? 0) != 0) {
      badges = {...badges, k: 0};
      newItems = newItems.where((x) => x.$1 != k).toList();
      notifyListeners();
    }
  }

  bool _loadingBadges = false;

  Future<void> loadBadges() async {
    final m = active;
    if (m == null || !m.approved || _loadingBadges) return;
    _loadingBadges = true;
    try {
      final inst = m.instituteId;
      final out = <String, int>{};
      final items = <(String, String, int)>[];
      if (m.isStaff) {
        final seenD = seenAt('doubts');
        final ds = await backend.doubts(inst);
        final open = ds.where((d) => !d.solved && (d.replies.isEmpty || !d.replies.last.staff) && d.lastAt > seenD);
        out['doubts'] = open.length;
        if (m.role == Role.admin || m.role == Role.teacher) {
          try {
            final seenL = seenAt('admissions');
            out['admissions'] = (await backend.leads(inst)).where((l) => l.createdAt > seenL).length;
          } catch (_) {}
        }
      } else {
        if (m.role == Role.parent) loadChildPhotos();
        final su = m.role == Role.student ? m.uid : (m.childUids.isEmpty ? '' : m.childUids[childIndex.clamp(0, m.childUids.length - 1)]);
        Set<String> myBatches = {...m.batchIds};
        if (m.role == Role.parent && su.isNotEmpty) {
          try {
            myBatches = (await backend.attendanceForStudent(inst, su)).map((a) => a.batchId).toSet();
          } catch (_) {}
        }
        bool mine(String b) => b.isEmpty || myBatches.isEmpty || myBatches.contains(b);
        final seenN = seenAt('notices');
        final ns = (await backend.notices(inst)).where((n) => n.createdAt > seenN && mine(n.batchId)).toList();
        out['notices'] = ns.length;
        for (final n in ns) {
          items.add(('notices', n.text, n.createdAt));
        }
        final seenR = seenAt('results');
        final ts = (await backend.tests(inst, publishedOnly: true)).where((t) => t.publishedAt > seenR && t.marks.containsKey(su)).toList();
        out['results'] = ts.length;
        for (final t in ts) {
          items.add(('results', t.title, t.publishedAt));
        }
        if (su.isNotEmpty) {
          final seenD = seenAt('doubts');
          final ds = (await backend.doubts(inst, studentUid: su)).where((d) => d.replies.any((r) => r.staff && r.at > seenD)).toList();
          out['doubts'] = ds.length;
          for (final d in ds) {
            items.add(('doubts', d.subject, d.lastAt));
          }
        }
        final seenRes = seenAt('resources');
        out['resources'] = (await backend.resources(inst)).where((r) => r.createdAt > seenRes && mine(r.batchId)).length;
      }
      items.sort((a, b) => b.$3.compareTo(a.$3));
      badges = out;
      newItems = items.take(5).toList();
      notifyListeners();
    } catch (_) {
    } finally {
      _loadingBadges = false;
    }
  }

  /// A request of mine that just got approved (shows "Congratulations" once).
  Membership? welcome;

  void dismissWelcome() {
    welcome = null;
    notifyListeners();
  }

  void dismissRemoved() {
    removedFrom = null;
    notifyListeners();
  }

  /// The active role's coaching and its VidyaDesk plan.
  Institute? inst;
  PlanStatus? get plan => inst == null || inst!.id != active?.instituteId ? null : PlanStatus(planFrom(inst!.plan), inst!.planUntil);

  /// The VidyaDesk owner (sees the owner panel).
  bool get isOwner => ownerEmails.contains((profile?.email ?? signedIn?.email ?? '').toLowerCase());

  /// Reads the active coaching (plan, owner phone) again.
  Future<void> loadInstitute() async {
    final m = active;
    if (m == null || !m.approved) {
      inst = null;
      planReadOnly = false;
      return;
    }
    try {
      inst = await backend.institute(m.instituteId);
    } catch (_) {}
    planReadOnly = plan?.grace ?? false;
    notifyListeners();
  }

  bool get isDemo => backend.isDemo;

  /// Parent: which child is selected (shared by every screen).
  int childIndex = 0;

  /// When the notifications screen was last opened (ms).
  int lastSeenNotif = 0;

  Future<void> markNotifSeen() async {
    lastSeenNotif = DateTime.now().millisecondsSinceEpoch;
    await _prefs?.setInt('notifSeen', lastSeenNotif);
    notifyListeners();
  }

  AppLifecycleListener? _life;

  Future<void> start() async {
    loadUpiApps();
    // Coming back to the app: read the plan again (it may have been renewed).
    _life ??= AppLifecycleListener(onResume: () {
      if (signedIn != null) refreshMemberships(check: true).then((_) => loadBadges());
    });
    Push.onChange = () {
      if (signedIn != null) refreshMemberships(check: true);
    };
    Push.onNew = loadBadges;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    lang = _prefs?.getString('lang') ?? 'en';
    languageChosen = _prefs?.getBool('langChosen') ?? false;
    themeMode = switch (_prefs?.getString('theme')) { 'dark' => ThemeMode.dark, 'system' => ThemeMode.system, _ => ThemeMode.light };
    lastSeenNotif = _prefs?.getInt('notifSeen') ?? 0;
    final r = _prefs?.getString('role');
    chosenRole = r == null ? null : roleFrom(r);
    Strings.lang = lang;

    backend = firebaseConfigured ? FirebaseBackend() : DemoBackend();
    try {
      await backend.init();
    } catch (e) {
      startError = e.toString();
      backend = DemoBackend();
      await backend.init();
    }
    signedIn = backend.current;
    if (signedIn != null) await loadAccount();
    ready = true;
    notifyListeners();
  }

  void finishSplash() {
    splashDone = true;
    notifyListeners();
  }

  // ---------- settings ----------

  Future<void> setLanguage(String l) async {
    lang = l;
    Strings.lang = l;
    languageChosen = true;
    await _prefs?.setString('lang', l);
    await _prefs?.setBool('langChosen', true);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    await _prefs?.setString('theme', switch (m) { ThemeMode.dark => 'dark', ThemeMode.system => 'system', _ => 'light' });
    notifyListeners();
  }

  Future<void> chooseRole(Role? r) async {
    chosenRole = r;
    if (r == null) {
      await _prefs?.remove('role');
    } else {
      await _prefs?.setString('role', r.name);
    }
    notifyListeners();
  }

  // ---------- account ----------

  /// Called after a login. Loads profile and roles and picks the active role.
  Future<void> loadAccount() async {
    loadingAccount = true;
    notifyListeners();
    try {
      signedIn = backend.current;
      if (signedIn == null) {
        profile = null;
        memberships = [];
        active = null;
      } else {
        profile = await backend.profile(signedIn!.uid);
        memberships = profile == null ? [] : await backend.myMemberships();
        _checkRemoved(detect: true);
        _pickActive();
        Push.sync(backend, memberships);
        await loadInstitute();
      }
    } finally {
      loadingAccount = false;
      notifyListeners();
    }
  }

  void _pickActive() {
    final live = memberships.where((m) => m.status != MemberStatus.rejected).toList();
    final keep = active == null ? null : live.where((m) => m.id == active!.id).firstOrNull;
    if (keep != null) {
      active = keep;
      return;
    }
    final role = chosenRole;
    Membership? pick;
    if (role != null) {
      pick = live.where((m) => m.role == role && m.approved).firstOrNull ?? live.where((m) => m.role == role).firstOrNull;
      if (pick == null && role == Role.teacher) pick = live.where((m) => m.role == Role.admin && m.teaches).firstOrNull;
    } else {
      pick = live.where((m) => m.approved).firstOrNull ?? live.firstOrNull;
      if (pick != null) chosenRole = pick.role;
    }
    active = pick;
  }

  void switchTo(Membership m) {
    active = m;
    if (inst?.id != m.instituteId) inst = null;
    chooseRole(m.role);
    notifyListeners();
    loadInstitute();
  }

  /// After joining or creating something, re-read the roles and show [m].
  Future<void> refreshAndShow(Membership m) async {
    joining = false;
    memberships = await backend.myMemberships();
    _checkRemoved(detect: false);
    active = memberships.where((x) => x.id == m.id).firstOrNull ?? m;
    Push.sync(backend, memberships);
    notifyListeners();
    await loadInstitute();
  }

  Future<void> refreshMemberships({bool check = false}) async {
    if (signedIn == null) return;
    try {
      memberships = await backend.myMemberships();
    } catch (_) {
      return;
    }
    _checkRemoved(detect: check);
    final id = active?.id;
    active = memberships.where((m) => m.id == id).firstOrNull;
    if (active == null) _pickActive();
    Push.sync(backend, memberships);
    notifyListeners();
    await loadInstitute();
  }

  /// Leave a role, or (owner) delete the whole institute. Then show another role.
  Future<void> removeRole(Membership m, {bool deleteInstitute = false}) async {
    if (deleteInstitute) {
      await backend.deleteInstitute(m.instituteId);
    } else {
      await backend.leave(m);
    }
    memberships = await backend.myMemberships();
    _checkRemoved(detect: false);
    if (active?.id == m.id || (deleteInstitute && active?.instituteId == m.instituteId)) {
      final live = memberships.where((x) => x.status != MemberStatus.rejected).toList();
      active = live.where((x) => x.approved).firstOrNull ?? live.firstOrNull;
      await chooseRole(active?.role);
    }
    notifyListeners();
  }

  Future<void> setPhoto(String photo) async {
    await backend.setPhoto(photo);
    profile = profile?.withPhoto(photo);
    for (final m in memberships) {
      m.photo = photo;
    }
    active?.photo = photo;
    notifyListeners();
  }

  Future<void> saveProfile(AppUser u) async {
    await backend.saveProfile(u);
    profile = u;
    memberships = await backend.myMemberships();
    _pickActive();
    notifyListeners();
  }

  /// Wants to join one more place / role (opens the join screens).
  void startNewJoin(Role r) {
    active = null;
    joining = true;
    chooseRole(r);
    notifyListeners();
  }

  /// True while the person is adding one more role / institute from Settings.
  bool joining = false;

  void cancelJoin() {
    joining = false;
    _pickActive();
    if (active == null && memberships.isNotEmpty) active = memberships.first;
    if (active != null) chooseRole(active!.role);
    notifyListeners();
  }

  Future<void> signOut() async {
    await Push.clear();
    await backend.signOut();
    signedIn = null;
    profile = null;
    memberships = [];
    active = null;
    joining = false;
    removedFrom = null;
    welcome = null;
    notifyListeners();
  }
}

/// Gives every screen access to [AppState] and rebuilds them when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppStateX on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);
}
