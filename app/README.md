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
  storage/       secure token storage
  providers/     riverpod: singletons, session state, form controllers
  screens/       splash / login / signed-in / notification bench (F1, temporary)
test/
  support/       fake HTTP transport, fake token storage, fake notification
                 gateway, JSON fixtures
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
exist, make it so" (`ReminderScheduler.sync`). F2/F4 will call it with
`remindersFromBoard(board)` after each `GET /board`; F1 feeds it synthetic rows
from the bench screen.

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
