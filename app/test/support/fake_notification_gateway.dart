import 'package:taskradar/notifications/notification_gateway.dart';
import 'package:timezone/timezone.dart' as tz;

/// In-memory [NotificationGateway].
///
/// Same reasoning as `FakeTokenStorage`: the real gateway talks to the OS over a
/// platform channel that does not exist in the `flutter test` VM. Implementing
/// the app's own narrow interface -- rather than intercepting
/// `flutter_local_notifications`'s method channel -- keeps these tests about
/// *scheduling decisions* instead of about the plugin's method-name strings.
///
/// It models the one behaviour of the real thing the scheduler actually relies
/// on: scheduling an id that is already queued **replaces** it.
class FakeNotificationGateway implements NotificationGateway {
  FakeNotificationGateway({
    this.support = NotificationSupport.android,
    this.permissionState = const NotificationPermissionState(
      notificationsEnabled: true,
      canScheduleExactAlarms: true,
    ),
  });

  @override
  NotificationSupport support;

  /// What [permissions] and [requestPermissions] answer.
  NotificationPermissionState permissionState;

  /// The queue, keyed by id, in the order ids were first added.
  final Map<int, FakeScheduledNotification> queue =
      <int, FakeScheduledNotification>{};

  /// Every [schedule] call, including re-arms of an id that was already there.
  /// This is how a test tells "left alone" apart from "scheduled again".
  final List<FakeScheduledNotification> scheduleCalls =
      <FakeScheduledNotification>[];

  final List<int> cancelledIds = <int>[];

  int initializeCount = 0;
  int cancelAllCount = 0;
  int pendingCount = 0;

  /// When set, every mutating call throws it. Used to prove the scheduler turns
  /// a platform failure into a report rather than an exception.
  Object? failure;

  /// Puts an entry in the queue without going through [schedule] -- stands in
  /// for "this was scheduled by a previous run of the app".
  void seed(FakeScheduledNotification notification) {
    queue[notification.id] = notification;
  }

  @override
  Future<void> initialize() async {
    initializeCount++;
  }

  @override
  Future<NotificationPermissionState> permissions() async => permissionState;

  @override
  Future<NotificationPermissionState> requestPermissions() async =>
      permissionState;

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime fireAt,
    required bool exact,
    String? payload,
  }) async {
    _maybeFail();
    final notification = FakeScheduledNotification(
      id: id,
      title: title,
      body: body,
      fireAt: fireAt,
      payload: payload,
      exact: exact,
    );
    scheduleCalls.add(notification);
    queue[id] = notification;
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    _maybeFail();
  }

  @override
  Future<List<PendingNotification>> pending() async {
    pendingCount++;
    return queue.values
        .map(
          (entry) => PendingNotification(
            id: entry.id,
            title: entry.title,
            body: entry.body,
            payload: entry.payload,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> cancel(int id) async {
    _maybeFail();
    cancelledIds.add(id);
    queue.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    _maybeFail();
    cancelAllCount++;
    queue.clear();
  }

  void _maybeFail() {
    final failure = this.failure;
    if (failure != null) throw failure;
  }
}

/// One entry of [FakeNotificationGateway.queue].
class FakeScheduledNotification {
  const FakeScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.exact,
    this.payload,
  });

  /// Convenience for seeding a queue entry whose fire time nobody asserts on.
  factory FakeScheduledNotification.stub({
    required int id,
    required tz.Location location,
    String? payload,
  }) => FakeScheduledNotification(
    id: id,
    title: 'stub',
    body: 'stub',
    fireAt: tz.TZDateTime(location, 2030),
    exact: true,
    payload: payload,
  );

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime fireAt;
  final String? payload;
  final bool exact;
}
