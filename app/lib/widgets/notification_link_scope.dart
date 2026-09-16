import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../navigation/app_routes.dart';
import '../providers/notification_link_providers.dart';

/// Turns a resolved reminder tap into a navigation, and an unresolvable one into
/// a sentence (F4).
///
/// ## Why this is a widget wrapped around the signed-in half
///
/// Three things have to be true at the moment a deep link is acted on, and this
/// placement is what makes all three true without a single check:
///
/// - **there is a navigator.** It is mounted under `MaterialApp.home`, so a
///   push cannot happen before the app has a route stack.
/// - **the user is signed in.** `app.dart` swaps `home` on the session, so this
///   widget does not exist while signed out -- and neither does the bridge it
///   watches, which is why a tap by a logged-out user does not fire a request
///   that would 401 and bounce them around. The tap waits (in the gateway's
///   buffer, or in the launch intent, which does not expire) until they are in.
/// - **the state outlives the screen.** [notificationLinkProvider] is
///   `keepAlive`, so navigating away and back, or a rebuild mid-resolution, does
///   not lose the request.
///
/// ## Why an ack, and why a dialog rather than a snackbar
///
/// The state is provider state and survives rebuilds, so acting on it in `build`
/// would navigate again on every frame. The scope acknowledges each terminal
/// state exactly once, which is also what lets "resolving" be a visible state
/// instead of a race.
///
/// The failures get a dialog because the user arrived here by tapping a
/// notification on a lock screen: they are looking at the phone for one specific
/// reason, and a snackbar that fades after four seconds while the board is still
/// loading is indistinguishable from the app having ignored them. "Задача не
/// найдена" has to be the thing on screen, with the reason and -- when there is
/// one -- something to do about it.
class NotificationLinkScope extends ConsumerStatefulWidget {
  const NotificationLinkScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotificationLinkScope> createState() =>
      _NotificationLinkScopeState();
}

class _NotificationLinkScopeState extends ConsumerState<NotificationLinkScope> {
  /// True while a dialog raised by this widget is up, so a second terminal
  /// state cannot stack a second dialog on top of it.
  bool _reporting = false;

  @override
  void initState() {
    super.initState();

    // The catch-up, for the same reason `boardReminderBridge` has one: `listen`
    // below only fires on *changes*, so a request that reached a terminal state
    // before this widget was mounted -- a sign-out and sign-in with a tap in
    // between -- would sit there forever. One shot, after the first frame, so
    // there is a navigator to push onto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handle(ref.read(notificationLinkProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    /*
     * Watched for its lifetime, not its value.
     *
     * `notificationLinkBridge` is what subscribes to the two tap paths. Like
     * every keepAlive provider it is never *created* until something
     * subscribes, and this is the right subscriber: it is mounted exactly when
     * a deep link is actionable.
     *
     * A cold start launched by a notification therefore reads its launch
     * payload here, one frame after login resolves -- not in `main`, where the
     * app does not yet know whether there is a session to open anything with.
     */
    ref.watch(notificationLinkBridgeProvider);

    ref.listen<NotificationLinkState>(notificationLinkProvider, (_, next) {
      _handle(next);
    });

    return widget.child;
  }

  void _handle(NotificationLinkState state) {
    if (!state.isTerminal || _reporting || !mounted) return;

    switch (state) {
      case NotificationLinkReady(:final projectId, :final taskId):
        // Acked *before* the push: the push rebuilds this subtree, and an
        // unacked ready state would be handled a second time by the
        // post-frame callback above.
        ref.read(notificationLinkProvider.notifier).ack();

        final opened = AppRoutes.openProjectFromBackground(
          projectId: projectId,
          highlightTaskId: taskId,
        );
        if (!opened) {
          // Documented as impossible from here (see `openProjectFromBackground`)
          // -- said out loud rather than swallowed, because the symptom would
          // otherwise be "tapping the reminder does nothing", which is the one
          // symptom this iteration must not have.
          debugPrint('Deep link to $projectId/$taskId found no navigator');
        }

      case NotificationLinkNotFound():
        _report(
          title: 'Задача не найдена',
          message:
              'Напоминание было о задаче, которой больше нет — её удалили '
              'после того, как будильник был поставлен. Само напоминание '
              'исчезнет при следующей синхронизации.',
        );

      case NotificationLinkUnreachable(:final error, :final taskId):
        _report(
          title: 'Не удалось открыть задачу',
          message:
              '${error == null ? 'Нет связи с сервером.' : describeApiError(error)}\n\n'
              'Локального снимка доски с этой задачей тоже нет, поэтому '
              'открыть её сейчас не получится.',
          retryTaskId: taskId,
        );

      case NotificationLinkIdle():
      case NotificationLinkResolving():
        break;
    }
  }

  /// [retryTaskId] is carried explicitly rather than re-read from the provider
  /// afterwards, because the ack below clears it: by the time the user presses
  /// "Повторить" there is no pending request left to ask about.
  Future<void> _report({
    required String title,
    required String message,
    String? retryTaskId,
  }) async {
    _reporting = true;
    // Acked here rather than after the dialog closes: while the dialog is up the
    // request has been dealt with, and leaving it pending would make a rebuild
    // behind the dialog try to handle it again.
    ref.read(notificationLinkProvider.notifier).ack();

    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (retryTaskId != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Повторить'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );

    _reporting = false;
    if (retry == true && retryTaskId != null && mounted) {
      await ref.read(notificationLinkProvider.notifier).open(retryTaskId);
    }
  }
}
