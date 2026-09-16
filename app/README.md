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
  providers/     riverpod: singletons, session state, board, project, forms
  navigation/    the one router, and the seam F4's deep link plugs into
  screens/       splash / login / board / project / note editor /
                 notification bench (F1, temporary)
  widgets/       reusable pieces of the screens
test/
  support/       fake HTTP transport (routed + stateful), fake token storage,
                 fake notification gateway, fake snapshot store, JSON fixtures
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

F3 added one writer to `boardProvider` and no second source of truth:
`Board.applyProjectTasks` splices an authoritative task list for one project into
the board already in memory, so an edit inside a project updates the card without
a second `GET /board`. See "Inside a project" below.

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
flutter test test/live_board_contract_test.dart test/live_project_contract_test.dart \
  --dart-define=TASKRADAR_LIVE_URL=http://127.0.0.1:3001 \
  --dart-define=TASKRADAR_LIVE_EMAIL=... \
  --dart-define=TASKRADAR_LIVE_PASSWORD=...
```

`live_project_contract_test.dart` (F3) does the same for the **write** path; see
"Checking the writes against the real server" below.

## Inside a project (F3)

`screens/project_screen.dart`: tasks and notes, as two tabs. Tabs rather than
two columns for a mechanical reason as much as a layout one -- the task list is a
`ReorderableListView` and it has to *be* the scrollable in order to scroll, to
pull-to-refresh and to auto-scroll during a drag, which two stacked lists in one
scroll view cannot all do. F6's wide desktop layout puts them side by side.

This is the first iteration with real navigation, and it deliberately sits
**below** the session switch in `app.dart` (see the long note there): `home` is
still "signed out or signed in", and the project screen is a route pushed on top
of it. `navigation/app_routes.dart` also carries `appNavigatorKey` and
`ProjectRouteArgs.highlightTaskId` end to end, so F4's "tap a reminder, open that
task" is a caller of `AppRoutes.openProjectFromBackground` rather than a
restructuring.

### Writes: optimistic, then reconciled

Every write shows its result immediately and rolls back with a message if the
server refuses -- `widgets/mutation_feedback.dart` for the message,
`providers/project_providers.dart` for the rollback. There is still **no offline
editing**: no operation queue, no conflict resolution. An optimistic update is a
prediction with a one-round-trip lifetime.

Three rules from `../flutter-migration-plan.md` shape the whole file, and the
long comment at its top restates them where they would get broken:

1. **The server computes `isCurrent`.** So a mutation that can move the "first
   `pending` task" around -- create, status change, delete, reorder -- ends with
   one `GET /projects/:id/tasks`, the cheapest question whose answer is
   complete. A title or description edit provably cannot move it and costs no
   extra request (`mergeMutatedTask`).
2. **The cache is read-only.** Writes fail loudly without a network.
3. **Changing the reminder target set *is* the reschedule.** Nothing in the F3
   code mentions the scheduler. A settled task list is pushed into the board
   (`Board.applyProjectTasks`) and `boardReminderBridge` re-arms the alarms, as
   in F2. `applyProjectTasks` also means a write inside a project updates the
   board's counters, current task and badges **without a second `GET /board`**:
   a board row is `GET /projects/:id` plus exactly the `tasks` array the project
   screen just re-read.

### Two contract details worth knowing before touching the API

Both were found against the live server, and neither is visible to a fixture.

- **The mutation endpoints do not compute `isCurrent`.** `POST /projects/:id/tasks`,
  `PATCH /tasks/:id` and `PATCH /tasks/:id/position` answer with the raw Prisma
  row, with no `isCurrent` key at all. Merging one of those straight into the
  list silently drops the current-task highlight, which is what
  `frontend/src/components/TaskListItem.tsx` does.
- **`PATCH /tasks/:id/position` can renumber rows it does not return.** Normally
  a move writes one row, bisected between the neighbours the client named. When
  that float gap is exhausted the route renumbers *every* task in the project in
  one transaction and still replies with only the moved row
  (`backend/src/domain/position.ts`). The unconditional re-read above is the
  answer; the neighbours are named by **id**, which survives a rebalance, never
  by position.

  The same arithmetic is why `Task.position` is a `double`. It is a Prisma
  `Float`, and four reorders into one slot produce `2937.5` (confirmed against
  the live server). Declared `int` this does not crash -- `json_serializable`
  emits `(json['position'] as num).toInt()`, so it quietly becomes `2937` and
  the client's ordering key stops matching the server's with nothing to say so.

### "Not provided" is not "null"

`PATCH /tasks/:id` gives `description` and `remindAt` three states, not two:
absent leaves the column alone, `null` **erases** it (`backend/src/schemas.ts`
plus the `!== undefined` copy in `routes/tasks.ts`). In Dart those two collapse
the moment a field is typed `String?`, so a status change would carry
`description: null` and wipe text nobody touched -- with a 200, and an optimistic
UI showing exactly what the user expected.

`api/patch_field.dart` makes the third state impossible to reach by accident.
Fields the server declares `optional()` but not `nullable()` (a task's `title`
and `status`, a note's `title` and `content`) stay plain nullable parameters,
because for them `null` really does only mean "not provided".

### Markdown notes

`flutter_markdown_plus` 1.0.12, which is what the plan names: `flutter_markdown`
is the SDK's own package and is discontinued, and this is the maintained fork of
that same code. It resolves against this SDK where several newer renderers do
not -- see the comment in `pubspec.yaml`, and the note there on why
`markdown_widget` and `gpt_markdown` were passed over.

All rendering goes through `widgets/note_markdown.dart` so the list preview and
the editor preview cannot drift into two typographies, and so "markdown is
rendered" is one widget test rather than an eyeball check. `softLineBreak` is on
deliberately: these notes are typed in a plain multi-line field by someone who
pressed Enter because they meant a new line.

### Checking the writes against the real server

`test/live_project_contract_test.dart`, same shape and same dart-defines as the
board one. It works in a project it creates and then archives-and-deletes in a
teardown that runs even when an expectation fails -- the seeded dev projects are
what a human looks at by eye, and a test that scribbled on them would ruin that.

It earned its keep immediately: it found that `BaseOptions.contentType` was
sending `content-type: application/json` on bodiless requests, so **every
`DELETE` in the app** was answered `400 Body cannot be empty...` by Fastify. No
faked transport can see that, because a fake does not read the header. The fix is
in `ApiClient._onRequest`; the regression guard is in `test/api_client_test.dart`.

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
