# TaskRadar — Flutter client

Native client for TaskRadar (Android + Windows). Replaces the frozen React PWA in
`../frontend`; see `../flutter-migration-plan.md` for the iteration plan and
`../README.md` for the product.

The backend (`../backend`) is unchanged apart from a few additive endpoints and
is the source of truth for every shape this app parses.

## Running

The API base URL is baked in at build time — there is no settings screen for it:

```
# Windows desktop, backend on the same machine
flutter run -d windows

# Android phone on the same Wi-Fi as the dev backend
flutter run -d <device> --dart-define=TASKRADAR_API_URL=http://<lan-ip>:3001

# Android emulator (the host is 10.0.2.2, not localhost)
flutter run -d emulator-5554 --dart-define=TASKRADAR_API_URL=http://10.0.2.2:3001
```

The default is `http://localhost:3001`, which is only correct for the desktop
target. The login screen prints the URL it is actually using, because "cannot
connect" on a phone is almost always a wrong base URL.

## Code generation

Models (`freezed` + `json_serializable`) and providers (`riverpod_generator`)
are generated. After changing anything annotated:

```
dart run build_runner build
```

The riverpod and json_serializable versions in `pubspec.yaml` are pinned to exact
versions on purpose — the comments there explain which constraint forces which.

## Layout

```
lib/
  config/        build-time configuration (API base URL)
  models/        freezed models ported from ../frontend/src/lib/types.ts
  api/           dio client, error types, one class per endpoint group
  domain/        pure logic with no plugins and no clock of its own
  notifications/ the side-effecting half: plugin, timezone, scheduler
  storage/       secure token storage, board snapshot file
  providers/     riverpod: singletons, session state, board, form controllers
  screens/       splash / login / board / notification bench (F1, temporary)
  widgets/       reusable pieces of the screens
test/
  support/       fake HTTP transport, fake token storage, fake notification
                 gateway, fake snapshot store, JSON fixtures
```

## The board and its read cache (F2)

`GET /board?archived=false` in one request, drawn as a vertical list of project
cards. The wide "column per project" layout from the original product sketch is
**F6**, for the desktop target, and is deliberately not built yet.

Three providers rather than one, for a reason worth knowing before touching
them (`lib/providers/board_providers.dart` has the long version):

- `boardProvider` — only the network;
- `boardSnapshotProvider` — only the disk, read once per run;
- `boardViewProvider` — a plain synchronous fold of the two into the single
  value the screen renders.

That split is what makes "draw the snapshot instantly, refresh in parallel"
race-free. A single notifier that returned the cache and then overwrote its own
state would lose the fresh board to the stale one whenever the transport
answered faster than the first value was published — which is exactly what a
fake transport does in tests.

The snapshot (`lib/storage/board_snapshot_store.dart`) is a versioned JSON file
in the application-support directory. It is **read-only cache**: no write ever
originates from it, and F3/F4 mutations will require the network, as
`../flutter-migration-plan.md` insists. Every way it can be untrustworthy
(absent, truncated, corrupt, older schema) maps to "there is no snapshot", which
the screen shows as *loading* — never as an empty board, because "you have no
projects" and "the cache is unreadable" look identical and mean the opposite.
**The token is not in it**; that stays in `flutter_secure_storage`.

One framework default is overridden on purpose: Riverpod 3 retries a failed
provider ten times over ~38 seconds, which would leave the pull-to-refresh
spinner turning long after the failure was known. See `noAutomaticRetry`.

### Checking the models against the real server

Fixtures prove the parser matches the fixture, not that the fixture matches the
server. `test/live_board_contract_test.dart` logs into a running backend and
pushes the real response through the real `BoardApi`. It is skipped unless it is
given a URL and credentials:

```
flutter test test/live_board_contract_test.dart \
  --dart-define=TASKRADAR_LIVE_URL=http://127.0.0.1:3001 \
  --dart-define=TASKRADAR_LIVE_EMAIL=... \
  --dart-define=TASKRADAR_LIVE_PASSWORD=...
```

## Local reminders (F1)

The app schedules its own alarms through `flutter_local_notifications`; there is
no FCM and nothing server-side. The split is deliberate:

- `lib/domain/reminder_schedule.dart` — which alarm should exist, with which id,
  at which instant. No plugin, no clock: `now` and the timezone are parameters,
  so the timezone trap from `../frontend/src/lib/reminders.ts` and the day
  boundaries are covered by ordinary unit tests.
- `lib/notifications/` — the platform half, behind a narrow `NotificationGateway`
  interface so the tests never touch a method channel.

The scheduler's entire API is "here is the complete set of reminders that should
exist, make it so" (`ReminderScheduler.sync`). Nobody calls it: `reminderSync`
*watches* `reminderTargets`, so replacing the target set **is** the reschedule.
F2 plugged the real data into that seam — `boardReminderBridge` writes
`remindersFromBoard(board)` after every board change (cached or fresh) and the
queue follows. The bench screen still writes synthetic rows to the same place,
and nothing downstream can tell the difference.

**Verifying it actually works is a manual, on-device job** — see
[`NOTIFICATIONS-CHECKLIST.md`](NOTIFICATIONS-CHECKLIST.md). Nothing in `flutter
test` can tell you whether a vendor's battery optimiser kills the alarm
overnight, and that is the exact risk F1 exists to measure.

Android specifics live in `android/app/src/main/AndroidManifest.xml` (runtime
notification permission, exact alarms, boot receiver) and
`android/app/src/main/res/raw/keep.xml` (the notification icon must survive R8);
each is commented with why it is there and what breaks silently without it.

On Windows the scheduler runs and the queue is inspectable, but desktop toasts
are **not** part of F1's acceptance — an unpackaged Win32 app needs a Start-menu
shortcut carrying its AppUserModelID, which `flutter build windows` does not
create. See `NotificationSupport.windows`.
