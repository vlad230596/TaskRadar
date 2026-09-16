import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_client.dart';
import 'package:taskradar/api/auth_api.dart';
import 'package:taskradar/api/board_api.dart';
import 'package:taskradar/domain/board_reminders.dart';
import 'package:taskradar/domain/project_summary.dart';

/// **Manual test.** Runs against a real, running TaskRadar backend.
///
/// ## Why this exists next to the fixture-based tests
///
/// Every other test in this directory feeds the models JSON that someone in
/// this repository wrote. That proves the parser matches the fixture; it cannot
/// prove the fixture matches the server. A field the backend renamed, a
/// `null` where the client requires a value, a date format that changed -- none
/// of those fail a fixture test, and all of them fail on a phone.
///
/// So this test skips the fixtures entirely: it logs in, pulls `GET /board` off
/// the wire and runs the response through the same [BoardApi], models and
/// domain helpers the app uses.
///
/// ## Running it
///
/// Skipped by default -- `flutter test` must stay green with no server and no
/// credentials. To run it, point it at a backend and give it a login:
///
/// ```
/// flutter test test/live_board_contract_test.dart \
///   --dart-define=TASKRADAR_LIVE_URL=http://127.0.0.1:3001 \
///   --dart-define=TASKRADAR_LIVE_EMAIL=... \
///   --dart-define=TASKRADAR_LIVE_PASSWORD=...
/// ```
///
/// The credentials are dart-defines rather than anything committed: the real
/// ones live in `../CREDENTIALS.local.md`, which is gitignored on purpose.
void main() {
  const baseUrl = String.fromEnvironment('TASKRADAR_LIVE_URL');
  const email = String.fromEnvironment('TASKRADAR_LIVE_EMAIL');
  const password = String.fromEnvironment('TASKRADAR_LIVE_PASSWORD');

  final skip = baseUrl.isEmpty || email.isEmpty || password.isEmpty
      ? 'manual: pass --dart-define=TASKRADAR_LIVE_URL/_EMAIL/_PASSWORD'
      : null;

  test('the live GET /board parses into the app\'s own models', () async {
    final client = ApiClient.forBaseUrl(baseUrl);

    final login = await AuthApi(client).login(email: email, password: password);
    client.setToken(login.token);

    // The real parse. Any contract drift throws right here.
    final board = await BoardApi(client).fetchBoard();

    expect(board, isNotEmpty, reason: 'seed the dev database first');

    for (final entry in board) {
      expect(entry.project.id, isNotEmpty);
      expect(entry.project.name, isNotEmpty);
      expect(
        entry.project.archivedAt,
        isNull,
        reason: 'archived=false must not return archived projects',
      );

      // Task order is part of the contract -- `isCurrent` is computed against
      // it server-side.
      // `double`, not `int`: `position` is a Float server-side and a bisected
      // one comes back as e.g. 1062.5. See the note on `Task.position`.
      var previousPosition = double.negativeInfinity;
      for (final task in entry.tasks) {
        expect(task.projectId, entry.project.id);
        expect(task.position, greaterThan(previousPosition));
        previousPosition = task.position;
      }

      // Exactly the two derived values the board screen draws.
      expect(entry.tasks.where((task) => task.isCurrent).length, lessThan(2));
      expect(() => ProjectSummary.of(entry), returnsNormally);
    }

    // And the value the whole native client exists for: every reminder date
    // must be readable as a calendar date by the scheduler's parser.
    for (final reminder in remindersFromBoard(board)) {
      expect(
        reminder.remindAt,
        matches(r'^\d{4}-\d{2}-\d{2}T'),
        reason: 'the YYYY-MM-DD prefix is what every date comparison uses',
      );
    }

    // Printed rather than asserted: the point of running this by hand is to
    // see what the server actually sent.
    // ignore: avoid_print
    print(
      'live /board: ${board.length} projects, '
      '${board.fold<int>(0, (sum, entry) => sum + entry.tasks.length)} tasks, '
      '${remindersFromBoard(board).length} reminders',
    );
  }, skip: skip);
}
