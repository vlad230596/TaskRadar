import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_schedule.dart';

/// The app's own, deliberately small, view of the notification plugin.
///
/// Two reasons this interface exists instead of passing
/// `FlutterLocalNotificationsPlugin` around:
///
/// 1. **Tests.** The plugin is a singleton over a `MethodChannel`; in
///    `flutter test` every call would either throw `MissingPluginException` or
///    have to be faked at the channel level, i.e. by asserting on method-name
///    strings. An interface this narrow can be implemented by a fake that
///    records real objects (see `test/support/fake_notification_gateway.dart`).
/// 2. **Platform honesty.** The plugin exposes the union of every platform's
///    abilities and answers `null` or throws for the ones the current platform
///    lacks. This interface answers the question the app actually asks --
///    "can this device do reminders at all, and what is missing?" -- with
///    [NotificationSupport] and [NotificationPermissionState].
abstract interface class NotificationGateway {
  /// What this platform can do. Constant for the process lifetime; cheap.
  NotificationSupport get support;

  /// Creates channels, wires callbacks, resolves the device timezone. Safe to
  /// call more than once.
  Future<void> initialize();

  /// Registers the handler for a notification the user tapped **while this
  /// isolate was alive** -- app in the foreground, or resumed from the
  /// background (F4).
  ///
  /// ## Why this is not the whole story
  ///
  /// It cannot see the case that matters most. When the app is not running, the
  /// tap starts the process, and `flutter_local_notifications` states plainly
  /// that the response callback is **not** invoked for the notification that
  /// launched the app -- that tap is only readable through
  /// [takeLaunchPayload]. Wiring this alone gives a deep link that works
  /// perfectly in every test on a warm app and silently does nothing at 09:00
  /// on a phone that spent the night with the app swiped away, which is the only
  /// time it is actually needed.
  ///
  /// ## Why the handler is settable rather than a constructor argument
  ///
  /// The gateway is created by a provider; the thing that knows how to navigate
  /// is created later, by another. Taps that arrive in between are **buffered**
  /// and delivered when a handler appears -- an implementation may not drop
  /// them.
  void setTapHandler(void Function(String? payload) handler);

  /// The payload of the notification that **launched** the app, or null.
  ///
  /// Consuming: the second call answers null. The alternative -- a plain getter
  /// re-read whenever convenient -- is a bug on Android, where `onNewIntent`
  /// replaces the activity's launch intent, so a later read would return the
  /// payload of a *background* tap that [setTapHandler] has already delivered,
  /// and the app would navigate twice.
  Future<String?> takeLaunchPayload();

  /// Asks the OS for whatever is still missing, showing system prompts.
  ///
  /// Must only be called from a user gesture -- Android shows the
  /// `POST_NOTIFICATIONS` dialog once and remembers a denial forever, so
  /// spending it on a cold start the user was not looking at is unrecoverable
  /// without a trip to system settings.
  Future<NotificationPermissionState> requestPermissions();

  /// Reads the current permission state without prompting.
  Future<NotificationPermissionState> permissions();

  /// Arms one alarm. Replaces any existing notification with the same id.
  ///
  /// Deliberately takes loose fields rather than a [ScheduledReminder]: the
  /// bench screen also needs to arm one-off diagnostic alarms that are
  /// explicitly *not* task reminders (different payload, reserved id, not swept
  /// by a resync). One primitive, two callers, no special case.
  ///
  /// [exact] false asks the OS for a best-effort alarm instead; see
  /// [NotificationPermissionState.canScheduleExactAlarms].
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime fireAt,
    required bool exact,
    String? payload,
  });

  /// Posts a notification right now. Used by the bench, and by nothing else.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  /// Everything the OS has queued for this app.
  ///
  /// The single most useful diagnostic in this whole iteration: it is what
  /// separates "the alarm was never armed" (a bug in this app) from "the alarm
  /// was armed and never fired" (the power-management problem that killed the
  /// PWA). Those two have identical symptoms from the user's side.
  Future<List<PendingNotification>> pending();

  Future<void> cancel(int id);

  Future<void> cancelAll();
}

/// What the platform underneath a [NotificationGateway] actually supports.
@immutable
class NotificationSupport {
  const NotificationSupport({
    required this.schedulesReminders,
    required this.hasRuntimePermission,
    required this.hasExactAlarmPermission,
    required this.survivesReboot,
    required this.note,
  });

  /// Android: the whole feature. This is the platform F1 is about.
  static const NotificationSupport android = NotificationSupport(
    schedulesReminders: true,
    hasRuntimePermission: true,
    hasExactAlarmPermission: true,
    survivesReboot: true,
    note:
        'Android: полная поддержка. Точные будильники, запрос разрешений, '
        'перепланировка после перезагрузки.',
  );

  /// Windows: the desktop target, and explicitly *not* part of F1's acceptance.
  ///
  /// What works: the plugin initialises, `show`/`zonedSchedule`/`pending` are
  /// implemented by `flutter_local_notifications_windows`, so the bench screen
  /// is usable for eyeballing the queue while developing on the desktop.
  ///
  /// What does not, by itself: Windows toast notifications for an *unpackaged*
  /// Win32 app require a Start-menu shortcut carrying the app's AppUserModelID,
  /// which `flutter build windows` does not create. So a scheduled toast from a
  /// build that was merely copied somewhere may simply never appear, and that is
  /// a deployment gap, not a bug in this code. F6 closes it on the deployment
  /// side: `../../../scripts/install-windows-app.ps1` writes that shortcut and
  /// verifies the id it wrote. There is still no runtime permission model and no
  /// reboot-survival contract to speak of -- a scheduled toast is kept by the
  /// Windows notification platform, not re-armed by us.
  ///
  /// The decision: do not pretend. The scheduler runs on Windows (so the same
  /// code path is exercised and cannot rot), every call is guarded against
  /// throwing, and the bench screen prints this note so nobody spends an evening
  /// debugging desktop toasts thinking they are the deliverable.
  static const NotificationSupport windows = NotificationSupport(
    schedulesReminders: true,
    hasRuntimePermission: false,
    hasExactAlarmPermission: false,
    survivesReboot: false,
    note:
        'Windows: не входит в приёмку F1. Планировщик работает и очередь видна, '
        'но всплывающий тост у неупакованного приложения требует ярлыка с '
        'AppUserModelID в меню «Пуск» — его сборка Flutter не создаёт. '
        'Отсутствие тоста на десктопе ничего не говорит про телефон.',
  );

  /// Anything else (iOS/macOS/Linux/web are not targets; a headless test VM
  /// falls here too).
  static const NotificationSupport none = NotificationSupport(
    schedulesReminders: false,
    hasRuntimePermission: false,
    hasExactAlarmPermission: false,
    survivesReboot: false,
    note: 'Эта платформа не поддерживается: напоминания не планируются.',
  );

  /// Whether arming alarms is attempted at all.
  final bool schedulesReminders;

  /// Whether there is a user-facing notification permission to ask for.
  final bool hasRuntimePermission;

  /// Whether there is a separate exact-alarm permission.
  final bool hasExactAlarmPermission;

  /// Whether the platform needs (and has) a boot receiver to re-arm alarms.
  final bool survivesReboot;

  /// One paragraph, in Russian, shown verbatim on the bench screen.
  final String note;
}

/// The two Android permissions that decide whether any of this works, plus the
/// "we could not ask" case.
@immutable
class NotificationPermissionState {
  const NotificationPermissionState({
    required this.notificationsEnabled,
    required this.canScheduleExactAlarms,
  });

  /// Used where the platform has no such concept, so the bench shows "n/a"
  /// rather than a misleading green tick.
  static const NotificationPermissionState unknown =
      NotificationPermissionState(
        notificationsEnabled: null,
        canScheduleExactAlarms: null,
      );

  /// `POST_NOTIFICATIONS`. Null means "not applicable / could not be read".
  ///
  /// When this is false nothing is shown and **no error is raised anywhere** --
  /// `zonedSchedule` still succeeds, the alarm still fires, and the OS drops the
  /// notification on the floor. That silence is exactly why the bench screen
  /// puts this flag on screen.
  final bool? notificationsEnabled;

  /// `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`. Null means "not applicable".
  ///
  /// False is a degradation, not a failure: see [NotificationScheduleMode].
  final bool? canScheduleExactAlarms;

  /// True when nothing is known to be missing.
  bool get isUsable => notificationsEnabled != false;

  NotificationScheduleMode get scheduleMode => canScheduleExactAlarms == false
      ? NotificationScheduleMode.inexact
      : NotificationScheduleMode.exact;
}

/// How precisely alarms are being armed right now.
enum NotificationScheduleMode {
  /// `AndroidScheduleMode.exactAllowWhileIdle`: fires at the requested minute
  /// even in Doze.
  exact,

  /// `AndroidScheduleMode.inexactAllowWhileIdle`: the fallback when the exact
  /// alarm permission was refused. The alarm still fires and still pierces Doze,
  /// but Android batches it with other wakeups and it can drift by hours -- for
  /// "remind me in the morning" a 09:00 alarm arriving at 13:00 is a different
  /// product. The bench says so out loud instead of degrading quietly.
  inexact,
}

/// One entry of the OS's queue, reduced to what the bench and the resync need.
@immutable
class PendingNotification {
  const PendingNotification({
    required this.id,
    this.title,
    this.body,
    this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;

  /// Whether this entry was put there by the reminder scheduler (as opposed to
  /// the bench's manual test alarms, or anything a later iteration adds).
  bool get isReminder => taskIdFromPayload(payload) != null;

  @override
  String toString() => 'PendingNotification(#$id, $title, $payload)';
}
