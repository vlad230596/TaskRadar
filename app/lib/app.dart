import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications/reminder_lifecycle.dart';
import 'providers/session_provider.dart';
import 'screens/board_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';

/// Root widget.
///
/// ## Why there is no router
///
/// The whole app is "logged out or logged in", and which one is a piece of
/// *state*, not a place the user navigates to. Swapping `home` on the session
/// state means there is exactly one rule -- no route guards, no
/// `Navigator.pushReplacement` after login, and no way for a 401 handler deep in
/// the HTTP layer to need a `BuildContext` in order to get the user out. The 401
/// interceptor just flips the session and this rebuilds.
///
/// A real router (nested project/task routes, notification deep links) becomes
/// necessary at F4. It should be introduced *below* this switch, routing only
/// within the signed-in half, so this property survives.
class TaskRadarApp extends ConsumerWidget {
  const TaskRadarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    // The reminder resync-on-foreground listener sits *outside* the
    // session switch on purpose: it must not be torn down and re-created by a
    // login or a 401, and the alarms it maintains belong to the device, not to
    // the session. It reads nothing until the app is actually resumed, so it
    // costs nothing at startup.
    return ReminderLifecycleScope(
      child: MaterialApp(
        title: 'TaskRadar',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
        ),
        home: switch (session) {
          AsyncData(:final value) => value == SessionStatus.signedIn
              ? const BoardScreen()
              : const LoginScreen(),

          // `Session.build` catches everything it expects, so reaching here
          // means an unanticipated failure. Falling back to the login screen is
          // the right recovery: it is the one screen that works with no session
          // and no cached data, and it gives the user something to do.
          AsyncError() => const LoginScreen(),

          _ => const SplashScreen(),
        },
      ),
    );
  }
}
