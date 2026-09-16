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
  screens/       splash / login / board / project / note editor / archive /
                 settings / notification bench (F1, kept as a diagnostic)
  widgets/       reusable pieces of the screens
test/
  support/       fake HTTP transport (routed + stateful), fake token storage,
                 fake notification gateway, fake snapshot store, fake settings
                 store, JSON fixtures
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
originates from it, and every F3/F4 mutation requires the network, as
`../flutter-migration-plan.md` insists. It also earns its keep a second time in
F4: it is what lets a reminder tapped with no signal still find the project its
task belongs to. Every way it can be untrustworthy (absent, truncated, corrupt,
older schema) maps to "there is no snapshot", which the screen shows as
*loading* — never as an empty board, because "you have no projects" and "the
cache is unreadable" look identical and mean the opposite.
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

`live_project_contract_test.dart` does the same for the **write** path, F3's and
F4's; see "Checking the writes against the real server" below.

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

## The day inside the app (F4)

F4 is the iteration after which this replaces the old way of working, so the
measure for every decision in it was "can a working day happen entirely in
here". Three things were missing for that and are now present: a blocker can be
given a date, a reminder can be acted on from the lock screen, and projects can
be created, archived and deleted without opening the web client.

### The blocker cycle

`widgets/task_list.dart`: choosing "Блокер" on a task that has no date opens the
date picker immediately, because "blocked" and "waiting until Tuesday" are one
thought and the second tap is the one that does not happen on a phone. The
result is an app full of dateless blockers -- tasks that are stuck and will
never say so again, which is the failure this product exists to prevent.
Cancelling the picker is a real answer; the row then says so in words and the
date can be added later by tapping that line.

**The date that goes to the server is a calendar date, never an instant.**
`domain/reminders.dart` now carries both halves of the timezone trap: reading
(`reminderCalendarDate`, ported from `frontend/src/lib/reminders.ts` in F2) and
writing (`calendarDateForApi`). The two obvious ways to serialise what
`showDatePicker` returns are both off by a day, in opposite directions --
`picked.toUtc()` stores the previous day east of UTC, a naked local timestamp
reads as UTC and shifts the other way west of it. Sending `YYYY-MM-DD` built
from local wall-clock parts sidesteps the instant entirely, which is right
because there is no instant here: the user picked a *day*. It is also
byte-for-byte what the React client sent from its `<input type="date">`, so an
old row and a new one are indistinguishable.

Setting a date takes **one request** and no re-read: `isCurrent` is "the first
`pending` task in position order", so a date can move neither the order nor the
current task. The alarms still change, with nothing in the write path mentioning
the scheduler -- see rule 3 in `providers/project_providers.dart`.

### The reminder hour is a setting now

`screens/settings_screen.dart`, persisted through `storage/settings_store.dart`
(`shared_preferences`, not the snapshot's file-plus-schema-version machinery and
not `flutter_secure_storage`; the long version is in that file).

`ReminderSettings` became **asynchronous** in the process, and that is the one
structural change F1 did not predict. Publishing the 09:00 default and
correcting it when the disk answers would arm the entire queue at the wrong hour
and re-arm it milliseconds later, on every cold start. Making the settle part of
the value costs nothing downstream, because `reminderSync` was already async.

Changing the hour re-arms everything by itself. Nothing calls "reschedule".

### Tapping a reminder opens the task

`providers/notification_link_providers.dart` plus
`widgets/notification_link_scope.dart`.

**A notification tap reaches a Flutter app two different ways, and only one of
them is obvious.** With the app alive (foreground, or backgrounded with the
process still around) the plugin invokes the response callback registered at
`initialize`. With the app **not running**, the tap starts the process and that
callback is *not* invoked for it -- `flutter_local_notifications` says so in as
many words, and the tap is readable only through
`getNotificationAppLaunchDetails`. Wire only the callback and the deep link works
in every test on a warm app and silently does nothing at 09:00 on a phone that
spent the night with the app swiped away, which is the only time it is needed.

Both are wired. The launch details are read **once, inside
`LocalNotificationGateway.initialize`**, and handed out once, which matters on
Android: `onNewIntent` calls `setIntent`, so a later read would return a
*background* tap the callback has already delivered and the app would navigate
twice. Taps that arrive before the navigation layer has subscribed are buffered
rather than dropped.

**The payload says `task:<id>`; the route needs a `projectId`.** There is no
`GET /tasks/:id` in the backend -- no route anywhere answers a question about a
task by id alone -- so the mapping comes from board data
(`projectIdForTask`). That turns out to be the better answer than widening the
payload: an id embedded when the alarm was armed is a cached copy that can go
stale over the weeks between arming and tapping, while the board is the current
truth by construction. It also works offline, which is half the reason the
snapshot holds tasks.

Resolution is three steps, in this order: what is already on screen (cache
included, so a reminder tapped in a basement still opens), then one board
refresh, then the archive (a project can be archived after its alarm was armed
and its tasks still open). A refresh that did not land short-circuits to "не
удалось" rather than "задача удалена" -- telling someone their task is gone when
the truth is that the train went into a tunnel is the worst available answer.
Both failures are an `AlertDialog` on the board, not a snackbar and not an empty
screen: the user is looking at the phone for one specific reason.

The whole graph is mounted **inside** the session switch (`app.dart`), so a tap
by a signed-out user never fires a request that 401s and bounces them around.
Nothing is lost by waiting -- the tap sits in the gateway's buffer or in the
launch intent, neither of which expires.

### Archive, delete, create

`providers/archive_providers.dart`, `screens/archive_screen.dart`, and the menu
on the project screen.

Archive is reversible, delete is not, and the second is only reachable through
the first -- `backend/src/domain/projectDeleteGuard.ts` answers 409 for an active
project. That split is copied from Trello on purpose
(`../project-tracker-brief.md`): the frequent gesture and the unrecoverable one
must not be the same gesture in the same place. The client states the rule
before the round trip rather than after the 409, but the guard stays server-side.

**The delete confirmation is not a yes/no.** Deleting a project takes its tasks
and its notes with it, and a yes/no in front of that is a speed bump a person
walking to the kitchen clears without reading. `confirmByTyping` in
`widgets/mutation_feedback.dart` asks the user to type the project's name, which
changes what is being measured: "are you sure" is a question about a mood, "which
project" is a question about a fact, and a mis-tap cannot answer it.

These four writes **invalidate** the board rather than splicing it
(`Board.applyProjectTasks` is for a row that is still there with different
tasks). That invalidation is also what disarms an archived project's reminders,
with no scheduler call anywhere: the refreshed board no longer contains its
blocked tasks, so the target set shrinks and the queue follows. An archived
project must stop nagging -- that is what archiving it means.

**Renaming a project is not possible**, from this client or any other: there is
no `PATCH /projects/:id` in the backend. `POST /projects` and the two archive
routes are a project's entire write surface. That is a missing endpoint, not a
missing screen, and `archive_screen_test.dart` has a test that should start
looking wrong the day it appears.

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
*watches* `reminderTargets` and `reminderSettings`, so replacing the target set
-- or changing the hour -- **is** the reschedule.
F2 plugged the real data into that seam — `boardReminderBridge` writes
`remindersFromBoard(board)` after every board change (cached or fresh) and the
queue follows. The bench screen still writes synthetic rows to the same place,
and nothing downstream can tell the difference.

F4 added three more writers to that same seam and **no second place that re-arms
anything**: setting a task's reminder date, changing the hour, and archiving or
unarchiving a project. Each one changes an input the graph already watches.

**Verifying it actually works is a manual, on-device job** — see
[`NOTIFICATIONS-CHECKLIST.md`](NOTIFICATIONS-CHECKLIST.md). Nothing in `flutter
test` can tell you whether a vendor's battery optimiser kills the alarm
overnight, and that is the exact risk F1 exists to measure. F4 added section 9
to that checklist: the persisted hour, the day the date picker actually sends,
and -- the one that fails silently -- tapping a reminder with the app **swiped
away**, which is a different code path from tapping it with the app alive.

Android specifics live in `android/app/src/main/AndroidManifest.xml` (runtime
notification permission, exact alarms, boot receiver) and
`android/app/src/main/res/raw/keep.xml` (the notification icon must survive R8);
each is commented with why it is there and what breaks silently without it.

On Windows the scheduler runs and the queue is inspectable, but desktop toasts
are **not** part of F1's acceptance — an unpackaged Win32 app needs a Start-menu
shortcut carrying its AppUserModelID, which `flutter build windows` does not
create. See `NotificationSupport.windows`.
