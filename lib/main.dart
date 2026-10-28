import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'data/models.dart';
import 'screens/auth.dart';
import 'screens/home_shell.dart';
import 'screens/join.dart';
import 'screens/onboarding.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  final state = AppState();
  state.start();
  runApp(VidyaDeskApp(state: state));
}

class VidyaDeskApp extends StatelessWidget {
  const VidyaDeskApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: Builder(builder: (context) {
        final app = context.app;
        final hindi = app.lang == 'hi';
        return MaterialApp(
          title: 'VidyaDesk',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Palette.light, hindi: hindi),
          darkTheme: buildTheme(Palette.night, hindi: hindi),
          themeMode: app.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 500),
          themeAnimationCurve: Curves.easeInOut,
          home: const Gate(),
        );
      }),
    );
  }
}

/// Decides which screen to show from the app state.
class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final Widget page;
    final String key;
    if (!app.ready || !app.splashDone) {
      page = const SplashScreen();
      key = 'splash';
    } else if (!app.languageChosen) {
      page = const LanguageScreen(firstTime: true);
      key = 'lang';
    } else if (app.signedIn == null) {
      if (app.chosenRole == null) {
        page = const RoleScreen();
        key = 'role';
      } else {
        page = const LoginScreen();
        key = 'login';
      }
    } else if (app.loadingAccount && app.profile == null) {
      page = const Scaffold(body: LoadingView());
      key = 'loading';
    } else if (app.profile == null) {
      page = const ProfileFormScreen(withEmail: false);
      key = 'profile';
    } else if (app.chosenRole == null && app.memberships.isEmpty) {
      page = const RoleScreen();
      key = 'role2';
    } else if (app.joining || app.active == null) {
      final r = app.chosenRole ?? Role.student;
      page = JoinFlow(role: r);
      key = 'join-${r.name}';
    } else if (!app.active!.approved) {
      page = PendingScreen(m: app.active!);
      key = 'pending-${app.active!.id}';
    } else {
      page = HomeShell(m: app.active!);
      key = 'home-${app.active!.id}';
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(a), child: child),
      ),
      child: KeyedSubtree(key: ValueKey(key), child: page),
    );
  }
}
