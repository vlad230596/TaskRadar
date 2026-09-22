import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'navigation/app_routes.dart';
import 'notifications/reminder_lifecycle.dart';
import 'providers/session_provider.dart';
import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/capture_flush_scope.dart';
import 'widgets/notification_link_scope.dart';

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
///
/// ## F3: that router now exists, and it did stay below the switch
///
/// `home` is still the session switch and still the only rule about being
/// signed in. What F3 added is `onGenerateRoute` for the pages *pushed on top*
/// of it (see `navigation/app_routes.dart`): a push cannot escape the switch,
/// because flipping the session replaces `home`, which tears the whole navigator
/// -- and everything pushed onto it -- down. So a 401 during a task edit still
/// lands on the login screen with no route guard anywhere and no `BuildContext`
/// in the HTTP layer.
///
/// F4 reuses that: `AppRoutes.openProjectFromBackground` needs only the
/// navigator key wired in below, and the notification handler becomes a caller
/// rather than a reason to restructure this widget.
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The app's own answer to "what colour are the system icons", asserted at
      // the root rather than left to whatever the platform starts with.
      //
      // It has to be stated even though it matches the Android default,
      // because `AnnotatedRegion` is read from whatever is painted at the top
      // of the screen and **nothing resets it on the way out**. The dictation
      // route declares light icons for its dark surface; without a region here
      // to fall back to, popping it left the light screens with white icons on
      // `#F3F3F7` -- an invisible clock and battery, which is how this was
      // found. The pushed route paints above this one, so it still wins while
      // it is up.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: ReminderLifecycleScope(
        child: MaterialApp(
          title: 'TaskRadar',
          debugShowCheckedModeBanner: false,
          // Reachable without a BuildContext, for F4's notification tap. Harmless
          // until then; see `navigation/app_routes.dart`.
          navigatorKey: appNavigatorKey,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          // F12: one theme, built from the palette in the app's own icon rather
          // than generated from a seed, and deliberately the same in both slots.
          // `ColorScheme.fromSeed(brightness: dark)` used to invent a second skin
          // nobody had designed or looked at; see `theme/app_theme.dart`. The one
          // dark surface in the product is the dictation screen, which is dark on
          // purpose and always.
          theme: buildAppTheme(),
          darkTheme: buildAppTheme(),
          home: switch (session) {
            // F4: the board is wrapped rather than replaced. `NotificationLinkScope`
            // is where a reminder tap turns into a route, and it sits *inside* the
            // session switch on purpose -- resolving a task reads the board, which
            // needs a session, and a tap by a signed-out user would otherwise fire
            // a request that 401s and bounces them around. The tap is not lost by
            // waiting: it is held in the gateway's buffer or in the launch intent
            // until this exists. See the long note in that file.
            // F8.1: `CaptureFlushScope` wraps the signed-in half, not the whole
            // app. Lines captured offline live in a file on the device and are
            // sent from here when the app starts or comes back to the
            // foreground -- both of which need a session, which is exactly what
            // this branch means.
            // F12: the board screen became `ShellScreen` -- the three modes, with
            // planning as one of them. Everything around it is unchanged, which
            // is the point: the shell sits *below* the session switch and *above*
            // the router, so neither of the two rules this file is built on had
            // to move.
            AsyncData(:final value) =>
              value == SessionStatus.signedIn
                  ? const CaptureFlushScope(
                      child: NotificationLinkScope(child: ShellScreen()),
                    )
                  : const LoginScreen(),

            // `Session.build` catches everything it expects, so reaching here
            // means an unanticipated failure. Falling back to the login screen is
            // the right recovery: it is the one screen that works with no session
            // and no cached data, and it gives the user something to do.
            AsyncError() => const LoginScreen(),

            _ => const SplashScreen(),
          },
        ),
      ),
    );
  }
}
