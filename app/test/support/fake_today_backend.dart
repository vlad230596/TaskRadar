import 'package:taskradar/models/today_history.dart';

import 'fake_backend.dart';

/// `GET/PATCH /settings` and `GET /reviews/status` on a [FakeBackend], for
/// the screens and providers of `design/today-history-contract.md`.
class FakeTodayServer {
  FakeTodayServer(
    FakeBackend backend, {
    this.settings = const OwnerSettings(),
    ReviewStatus? initialStatus,
  }) : status = initialStatus ?? const ReviewStatus(due: false) {
    backend.on('GET', '/settings', (_) => jsonResponse(settings.toJson()));
    backend.on('PATCH', '/settings', (match) {
      final body = match.body;
      patches.add(Map<String, dynamic>.of(body));
      settings = settings.copyWith(
        laterHorizonDays: body['laterHorizonDays'] as int?,
        reviewWeekday: body['reviewWeekday'] as int?,
        reviewTime: body['reviewTime'] as String?,
      );
      return jsonResponse(settings.toJson());
    });
    backend.on('GET', '/reviews/status', (_) => jsonResponse(status.toJson()));
  }

  OwnerSettings settings;
  ReviewStatus status;
  final List<Map<String, dynamic>> patches = <Map<String, dynamic>>[];
}
