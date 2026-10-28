import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/backend.dart';
import '../data/demo_backend.dart';
import '../data/firebase_backend.dart';
import '../data/models.dart';
import 'config.dart';
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

  bool get isDemo => backend.isDemo;

  Future<void> start() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    lang = _prefs?.getString('lang') ?? 'en';
    languageChosen = _prefs?.getBool('langChosen') ?? false;
    themeMode = switch (_prefs?.getString('theme')) { 'dark' => ThemeMode.dark, 'system' => ThemeMode.system, _ => ThemeMode.light };
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
        _pickActive();
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
    chooseRole(m.role);
    notifyListeners();
  }

  /// After joining or creating something, re-read the roles and show [m].
  Future<void> refreshAndShow(Membership m) async {
    joining = false;
    memberships = await backend.myMemberships();
    active = memberships.where((x) => x.id == m.id).firstOrNull ?? m;
    notifyListeners();
  }

  Future<void> refreshMemberships() async {
    if (signedIn == null) return;
    memberships = await backend.myMemberships();
    final id = active?.id;
    active = memberships.where((m) => m.id == id).firstOrNull;
    if (active == null) _pickActive();
    notifyListeners();
  }

  /// Leave a role, or (owner) delete the whole institute. Then show another role.
  Future<void> removeRole(Membership m, {bool deleteInstitute = false}) async {
    if (deleteInstitute) {
      await backend.deleteInstitute(m.instituteId);
    } else {
      await backend.leave(m);
    }
    memberships = await backend.myMemberships();
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
    await backend.signOut();
    signedIn = null;
    profile = null;
    memberships = [];
    active = null;
    joining = false;
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
