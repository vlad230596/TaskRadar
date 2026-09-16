import 'package:flutter/material.dart';

import '../screens/archive_screen.dart';
import '../screens/project_screen.dart';
import '../screens/settings_screen.dart';

/// The app's routes, and the seam F4 plugs the notification deep link into.
///
/// ## Why there is a router at all now, and where it sits
///
/// F0 deliberately had none: "signed out or signed in" is *state*, not an
/// address, so `app.dart` swaps `home` on it and the 401 interceptor never needs
/// a `BuildContext` to get the user out. That property is worth keeping, so this
/// router lives **below** that switch -- it generates routes only for the
/// signed-in half, and a 401 still tears the whole navigator down by flipping
/// the session rather than by navigating anywhere.
///
/// ## What F4 needs from it
///
/// F4's requirement is "tapping a notification opens that task". A notification
/// callback fires from a platform channel with no widget anywhere in scope, so
/// it needs two things that are easy to bolt on badly and cheap to provide
/// correctly up front:
///
/// - a navigator reachable without a `BuildContext` -- [appNavigatorKey];
/// - a route that is addressable by **id**, not by a `Project` object handed
///   over from the board. [ProjectScreen] therefore takes a `projectId` and
///   loads everything itself, which is also what lets it open from a cold start
///   with only the snapshot on disk.
///
/// [ProjectRouteArgs.highlightTaskId] is already carried end to end and already
/// tints the row it names. What F4 adds is the *sender*: a notification handler
/// that calls [openProjectFromBackground]. Nothing here has to change for it.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Arguments for [AppRoutes.project].
///
/// A typed object rather than a path like `/project/abc?task=def`: this is a
/// single-window app with no URL bar and no web target, so a parsed string would
/// be ceremony whose only real effect is turning a compile error into a runtime
/// one. The route *name* is still a constant, so `RouteSettings.name` remains
/// usable for observers and analytics.
@immutable
class ProjectRouteArgs {
  const ProjectRouteArgs({required this.projectId, this.highlightTaskId});

  final String projectId;

  /// The task to draw attention to on arrival, when the user got here from
  /// something that was about one specific task (F4: a reminder).
  final String? highlightTaskId;
}

abstract final class AppRoutes {
  /// The project screen. See [ProjectRouteArgs].
  static const String project = '/project';

  /// The archive: projects taken off the board, and the only place a project
  /// can be deleted from (F4).
  static const String archive = '/archive';

  /// Settings. One setting so far -- the hour reminders fire at (F4).
  static const String settings = '/settings';

  /// Hooked up as `MaterialApp.onGenerateRoute`.
  ///
  /// Returns null for anything it does not recognise, which lets
  /// `WidgetsApp` fall through to `onUnknownRoute` / assert in debug rather than
  /// silently showing a blank page.
  static Route<void>? onGenerateRoute(RouteSettings settings) {
    if (settings.name == archive) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const ArchiveScreen(),
      );
    }

    if (settings.name == AppRoutes.settings) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const SettingsScreen(),
      );
    }

    if (settings.name != project) return null;

    final args = settings.arguments;
    if (args is! ProjectRouteArgs) {
      // A typed-argument route reached without its arguments is a programming
      // error, and it is much easier to find here -- with the route name in the
      // message -- than as a null dereference inside the screen.
      throw ArgumentError.value(
        args,
        'settings.arguments',
        'route $project requires ProjectRouteArgs',
      );
    }

    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => ProjectScreen(
        projectId: args.projectId,
        highlightTaskId: args.highlightTaskId,
      ),
    );
  }

  /// Opens a project from inside the widget tree (the board card tap).
  static Future<void> openProject(
    BuildContext context, {
    required String projectId,
    String? highlightTaskId,
  }) {
    return Navigator.of(context).pushNamed<void>(
      project,
      arguments: ProjectRouteArgs(
        projectId: projectId,
        highlightTaskId: highlightTaskId,
      ),
    );
  }

  /// Opens the archive.
  static Future<void> openArchive(BuildContext context) =>
      Navigator.of(context).pushNamed<void>(archive);

  /// Opens settings.
  static Future<void> openSettings(BuildContext context) =>
      Navigator.of(context).pushNamed<void>(settings);

  /// Opens a project from outside the widget tree -- a notification tap, or
  /// anything else that starts at a platform channel.
  ///
  /// Returns false when there is no navigator yet (the app is still starting, or
  /// is on the login screen, where pushing a project screen would be wrong
  /// anyway). The caller is expected to remember the intent and retry.
  ///
  /// **F4's answer to "remember and retry"**: the intent is not held here at
  /// all. `NotificationLink` holds it as provider state and
  /// `widgets/notification_link_scope.dart` calls this only once it is itself
  /// mounted -- i.e. once the user is signed in and a navigator provably exists.
  /// A false return is therefore a bug rather than a normal condition, and the
  /// scope logs it instead of silently swallowing the tap.
  static bool openProjectFromBackground({
    required String projectId,
    String? highlightTaskId,
  }) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return false;

    navigator.pushNamed<void>(
      project,
      arguments: ProjectRouteArgs(
        projectId: projectId,
        highlightTaskId: highlightTaskId,
      ),
    );
    return true;
  }
}
