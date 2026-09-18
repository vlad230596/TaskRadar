# TaskRadar — Flutter client

The client for TaskRadar (Android + Windows + web since F10), and since F6 the
only one; see
`../flutter-migration-plan.md` for the iteration plan and `../README.md` for the
product.

The backend (`../backend`) is unchanged apart from a few additive endpoints and
is the source of truth for every shape this app parses.

## Where `frontend/src/...` went

Comments and this file point at files under `../frontend/` — the React PWA this
client replaced. **That directory no longer exists**: F6 deleted it, on purpose
and in the iteration where the Windows build finally made it redundant. The
references are kept rather than rewritten because they still say the true thing
— *this was ported from that file, and that file made this decision first* — and
because the file is one command away:

```
git log --diff-filter=D -- frontend          # the commit that removed it
git show <that commit>^:frontend/src/lib/types.ts
```

Nothing in this app builds, tests or runs against it. It is a citation, not a
dependency.

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

### The web target (F10)

In production the bundle is served by the same origin as the API, so its base
URL is empty and resolves to `Uri.base.origin` at run time -- there is nothing
to configure and no CORS anywhere. That is also why `flutter run -d chrome`
against a backend on another port does not work out of the box: the browser
refuses the cross-origin request, and the backend has no CORS policy to make it
legal. Either put both behind one origin, or pass an explicit
`--dart-define=TASKRADAR_API_URL=...` **and** accept that it will be blocked
until the backend allows it.

A production-shaped build:

```
flutter build web --release --no-web-resources-cdn --base-href /
```

`--no-web-resources-cdn` is not optional: without it the engine fetches
CanvasKit from gstatic at run time and the deployed Content-Security-Policy
refuses it. Fonts are the same story from the other direction -- Roboto is
bundled through `pubspec.yaml` because CanvasKit rasterises text itself and
cannot use the system's fonts; the comment there has the details.

Three things the web build deliberately does not have: local notifications
(`NotificationSupport.none`), dictation (`VoiceModelUnsupported` -- the
recogniser needs a 225 MB model on disk), and the file-backed stores. The last
one is a substitution rather than a subtraction: `providers/dependencies.dart`
swaps in the `localStorage`-backed twins from `lib/storage/web_stores.dart`,
which keep the same contracts.

The default is `http://localhost:3001`, which is only correct for the desktop
target. The login screen prints the URL it is actually using, because "cannot
connect" on a phone is almost always a wrong base URL.

## Release builds (Windows)

`flutter build windows --release` plus `scripts/package-windows-app.ps1`, which
is what CI runs:

```
powershell -ExecutionPolicy Bypass -File ..\scripts\package-windows-app.ps1 -Version dev
```

That produces `taskradar-<version>-windows-x64.zip` holding the build, the
installer and a README. `.github/workflows/app-release.yml` attaches the same
zip (plus a checksum and an attestation) to the GitHub Release for a tag, and
`app-ci.yml` builds it on every push as an artifact -- the desktop target is not
compiled by `flutter analyze` or `flutter test`, so a build is the only thing
that notices when it breaks.

The installer inside the zip matters: without the Start-menu shortcut it
creates, Windows silently drops every notification an unpackaged app posts. See
`scripts/install-windows-app.ps1`.

## Release builds (Android)

A release APK is signed with the owner's own key, which is **not in this
repository** and never will be: no keystore, no passwords, no alias.
`android/app/build.gradle.kts` reads the signing config from
`android/key.properties` (gitignored) or from `TASKRADAR_ANDROID_*` environment
variables, which is what `.github/workflows/app-release.yml` supplies from its
Actions secrets.

With no config, a release build **fails with a message** naming what is missing.
That is the fix, not a limitation: until F5 the release build type was signed
with the *debug* keystore, which produces an APK that installs and runs and looks
fine — right up to the day that keystore is regenerated and Android refuses to
update the installed app. Debug builds need no configuration at all and are
untouched.

[`RELEASE-ANDROID.md`](RELEASE-ANDROID.md) is the owner's instruction: generating
the keystore, where to keep it, what goes in `key.properties`, which Actions
secrets to create — and why that key can never be lost or replaced.

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
  models/        freezed models (ported from the React client's types.ts;
                 see "Where frontend/src/... went" above)
  api/           dio client, error types, one class per endpoint group
  domain/        pure logic with no plugins and no clock of its own
  notifications/ the side-effecting half: plugin, timezone, scheduler
  storage/       secure token storage, board snapshot file, offline capture
                 queue (F8.1), and their browser twins (F10)
  voice/         on-device dictation (F9): the model and where it lives, the
                 microphone and the recogniser, both behind interfaces
  providers/     riverpod: singletons, session state, board, project, forms
  navigation/    the one router, and the seam F4's deep link plugs into
  screens/       splash / login / board / project / note editor / archive /
                 scopes / inbox / settings / notification bench (a diagnostic)
  widgets/       reusable pieces of the screens
test/
  support/       fake HTTP transport (routed + stateful), fake token storage,
                 fake notification gateway, fake snapshot store, fake settings
                 store, fake capture queue, fake microphone/recogniser/model
                 store, JSON fixtures
```

## The board and its read cache (F2)

`GET /board?archived=false` in one request, drawn as a vertical list of project
cards on a narrow window and as columns on a wide one — see "The desktop
layout (F6)" below.

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

`screens/project_screen.dart`: tasks and notes, as two tabs on a narrow window.
Tabs rather than two stacked lists for a mechanical reason as much as a layout
one -- the task list is a `ReorderableListView` and it has to *be* the
scrollable in order to scroll, to pull-to-refresh and to auto-scroll during a
drag, which two stacked lists in one scroll view cannot all do. F6 puts them
side by side on a wide window, which keeps that property intact: each pane is
still its own scrollable.

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

### Renaming a project

`PATCH /projects/:id` (B6) is a project's only field update, and it is reachable
from two places: the project screen's menu, and **every row of the archive**.
The second is not a bonus — the archive is where you meet a project whose name
made sense in January, and the server allows a rename there deliberately so that
fixing it does not mean unarchive → rename → archive again, which writes
`archivedAt` twice to change a string. `archivedAt` is not in the payload, so a
rename can move a project between the board and the archive in neither
direction.

The write is optimistic with a rollback, queued behind the other project writes
(`ProjectLifecycle`, `providers/archive_providers.dart`), and it **splices**
rather than invalidating: `Board.applyProject`, `ArchivedBoard.applyProject` and
`ProjectHeader.applyProject` each take the row for the one list they own, so a
rename costs exactly one request. There is no re-read at all, and that is
provable rather than hopeful — `isCurrent` is "the first `pending` task in
position order", so a name can move neither the order, nor the current task, nor
a reminder date. It is the same argument that lets a reminder date be set in one
request (see the blocker cycle above).

The alarms do change, and again with nothing in the write path mentioning the
scheduler: a notification says which project it is about
(`TaskReminder.projectName`), so the spliced board publishes a new target set
and `reminderSync` re-arms it with the new wording. A renamed project that kept
nagging under its old name for weeks is exactly the bug that costs nothing to
avoid here.

Only the providers that are *already alive* are updated (`ref.exists`
before `ref.read(...notifier)`): reading a provider that does not exist creates
it, and creating either board means fetching a list nobody has open.

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

Renaming used to be impossible from any client, and `archive_screen_test.dart`
carried a test saying so. `PATCH /projects/:id` has since landed, so that test
was replaced by the `renaming` group in the same file rather than deleted — see
"Renaming a project" above.

## The desktop layout, and installing it (F6)

F6 is the iteration where the desktop stops being "the phone app in a bigger
window". Two screens grow a second layout, and the build grows a way to be
installed.

### One breakpoint, two layouts

`widgets/adaptive_layout.dart` holds the only number: **840 logical pixels**,
Material 3's "expanded" boundary. Above it the desktop layout, below it the
phone one, on both screens, decided from the window and nothing else.

- **The board** becomes the original picture of this product: a column per
  project with its **task line running top to bottom**
  (`widgets/project_column.dart`). The columns are computed to fill the window
  and wrap, tops aligned — a project's column is exactly as tall as its task
  list, because that height *is* information.
- **The project screen** puts tasks and notes side by side instead of behind
  tabs. The notes are the context you came to restore; reading them while
  looking at the task list is the gesture, and on a 1600px window hiding half
  the screen to show one list would be silly.

The column prints a title only for the rows worth reading at a glance — the
current task and every blocker, with its date — and draws everything else as a
dot with the title in a tooltip. Printing all twelve titles of a twelve-task
project would turn a fifteen-project board into a wall of text, which is the
one property `../README.md` builds the whole product around. The tooltip is
honest here in a way it would not be on a phone: this layout only renders where
there is a mouse.

One control is layout-specific rather than shared: the board's **refresh
button**, which exists only on the wide layout. A mouse cannot pull to refresh
— a wheel does not overscroll — so without it a desktop board could only be
refreshed by restarting the app.

### Installing it on Windows

```
flutter build windows --release --dart-define=TASKRADAR_API_URL=https://<host>
powershell -ExecutionPolicy Bypass -File ..\scripts\install-windows-app.ps1 -Autostart
```

`../scripts/install-windows-app.ps1` is per-user and needs no elevation. It does
two things that matter more than convenience:

1. **It copies the build out of the build tree.** `flutter clean` or the next
   build rewrites `build/windows/x64/runner/Release`, and a Start-menu or
   Startup shortcut pointing into it breaks silently — the app just stops
   opening one day.
2. **It writes the app's AppUserModelID into the shortcut.** Windows will not
   show a toast for an unpackaged Win32 app unless a Start-menu shortcut
   carrying that ID exists, `flutter build windows` does not create one, and
   `WScript.Shell` cannot set the property — so the script builds the shortcut
   through `IShellLink` + `IPropertyStore` and then reads the ID back to prove
   it stuck. The ID must stay equal to the one in
   `lib/notifications/local_notification_gateway.dart`; if the two ever
   disagree, the toast is dropped with no error anywhere.

`-Autostart` adds a Startup shortcut, and is off by default: the board is
something you open in the morning, not something that opens you. `-Uninstall`
removes both shortcuts and the installed copy; the signed-in session and the
cached board are untouched, because they belong to the app rather than to the
installation.

That shortcut closes a **deployment** gap, not F1's acceptance. F1 is the
question of whether a phone delivers a reminder after a night of vendor battery
optimisation, and nothing on a desktop answers it.

### What is not verified here

The two layouts are covered by widget tests at 1400x900 (`test/board_screen_test.dart`
and `test/project_screen_test.dart`, groups "desktop layout (F6)"), including an
overflow guard, and `flutter build windows --release` passes. **Nobody has looked
at the result on a real screen** — that is the same gap every previous iteration
recorded, and the remaining F6 step for a human: open it, resize the window
across 840px in both directions, and check that the board still reads at a
glance.

## Scopes (F7)

A scope is a space projects live in -- "work at company A", "home", "the dacha"
-- and the board shows exactly one at a time. `../README.md` has the product
argument; this is what it costs in the client.

### The board is fetched whole and filtered locally

The server *can* filter it (`GET /board?scopeId=`) and this client deliberately
does not ask it to. The reason is not performance:

**the local alarm queue is armed from the board.** A server-filtered board would
arm the alarms of the scope currently on screen and silently drop every other
one -- so opening "Работа" in the morning would disarm the reminder about the
cable for the dacha, and nobody would find out until a date passed unremarked.
Two smaller reasons point the same way: switching scopes is then instant and
works with no signal, and there is still exactly one snapshot file rather than
one per scope.

`providers/scope_providers.dart` holds that decision and the filter
(`projectsInScope`); the board and the archive both use it, and
`boardReminderBridge` keeps reading the **unfiltered** list.

### The switcher does not exist until it means something

Every installation has exactly one scope the moment the migration runs, and a
chip row offering a single choice is furniture. So `hasMultipleScopes` gates the
switcher above the board *and* the "move to scope" item in the project menu:
until a second scope is created, F7 is invisible. That is also what makes it
free for someone who never wanted it.

### The selection is an id, and it is resolved, not trusted

`SettingsStore.readSelectedScopeId` returns a string written on a previous run.
The scope it names can be gone -- deleted, or this database restored from a
backup -- so `activeScope` resolves it against the live list and falls back to
the first scope, which is the same default the server uses for a project created
without one. "The scope I was looking at was deleted" is then an ordinary state
instead of an empty board with no explanation.

A failed *write* of that preference does not roll the choice back: the board
jumping to another scope under the user's finger is a worse lie than the choice
being forgotten by tomorrow.

### What a move costs

Moving a project between scopes is one `PATCH /projects/:id` and no re-read. It
provably cannot disturb anything else -- task `position` orders tasks within a
project, `isCurrent` is computed from those positions, and `archivedAt` is not
in the payload -- so the row is spliced into whatever lists are on screen, the
same way a rename is. It is also the one write in this app that shows a success
message, because it makes the project disappear from the board it was performed
on.

## The sandbox (F8)

Write a line down now, decide where it goes later. `screens/inbox_screen.dart`
is both halves: a capture field at the top that owns the keyboard, and the pile
under it, oldest first.

### Capture works with no network (F8.1)

F8 made capture the one write in this app that was *not* optimistic: the text
stayed in the field until the server had it, because a line that appears and
then evaporates on a train breaks the sandbox's only promise -- **it is written
down now** -- and there was no queue to make the optimistic version true.

F8.1 built the queue, and with it that decision flipped. `CaptureQueue` in
`providers/capture_queue_providers.dart` writes the line to a file
(`storage/capture_queue_store.dart`) and *then* to the screen, so the promise
holds in a lift, on a train, in a plane. Sending happens afterwards: on capture,
on app start, on resume (`widgets/capture_flush_scope.dart`) and on
pull-to-refresh.

Three things about it are load-bearing:

- **the mark.** An unsent line says "не отправлено". Without it, "written down"
  and "written down in my pocket" look identical, and that difference is what
  someone needs in order to decide whether it is safe to forget the thought;
- **the key.** Every queued line carries a client-generated `captureKey` and
  `POST /inbox` upserts on it. A phone cannot tell "the request never arrived"
  from "it arrived and the answer was lost", so it retries -- and without the
  key the second case would leave a twin in the pile;
- **the disk error is still reported.** A failed queue write means the line
  exists nowhere, so that one keeps the text in the field.

This is the **only** exception to "writes need the network", and it does not
generalise: an inbox line has no order to be inserted into the wrong place in,
no state another device can change, and a lifetime of hours, so merging two
devices is set union. Filing has all three, which is why it still requires a
connection -- tapping an unsent line says so.

### Filing is one request, and it invalidates the board

`POST /inbox/:id/file` creates the task at the end of the project and deletes
the item in one transaction. Two requests from a client would have two ways to
be half-done -- the same thing filed twice, or the thought gone -- and neither
is visible to the person who typed it.

The response is a raw task row with **no `isCurrent`**, like every other
mutation endpoint, so `Inbox.file` does not splice it anywhere: it invalidates
the board and lets `GET /board` answer with the project's settled list. That is
one request for something done a handful of times a day, and it re-arms the
reminder queue for free.

### What an inbox item deliberately cannot do

No status, no reminder date, no order, no project. An item you can work on
directly is an item you never file, and a pile that has quietly become a second
task list is the failure this feature has to avoid. The only things a line can
become are: a task in a project, a project of its own, corrected text, or
nothing.

### Why the badge is on the board

`_InboxButton` in `screens/board_screen.dart` draws the count in the app bar. An
inbox is a promise that what was written there will be dealt with, and the only
thing that keeps that promise is seeing every morning that three lines are still
waiting. The count is nullable and the badge is absent while the pile is
loading: "0" that turns into "3" is a small lie told on every cold start.

## Dictation (F9)

Hold the microphone in the sandbox composer, speak, release; the text lands in
the field, to be corrected before it is captured. Recognition happens **on the
device** -- nothing is uploaded, which is the whole reason the system
recogniser was not used.

- `voice/voice_model.dart` -- which model and why (GigaAM v3 NeMo CTC, the
  punctuated export, MIT), plus the numbers: 163 MB to download, 236 MB on disk;
- `voice/voice_model_store.dart` -- fetching, unpacking (in another isolate) and
  deleting it. It decides whether a model is present by *looking at the files*,
  because a half-finished unpack would make a flag in preferences lie;
- `voice/speech_recognizer.dart` / `voice/voice_recorder.dart` -- the two
  platform seams, both behind interfaces so everything above them is testable;
- `providers/voice_providers.dart` -- the install state and the dictation state
  machine;
- `widgets/dictate_button.dart` -- the gesture.

The model is not in the APK and is not fetched silently: a quarter of a
gigabyte is presented in Settings as something to agree to, with the size before
the decision and a delete button after it. The microphone only appears once it
is there -- a button that answers "сначала скачайте 163 МБ" lies about what it
does.

Two implementation notes that cost time to find: the recogniser is held by
`ref.watch` rather than `ref.read` (otherwise Riverpod disposes it between two
phrases and the next press pays the multi-second load again), and the minimum
hold is measured with a `Timer` rather than two `DateTime.now()` readings (a
timer runs on the clock `pump` advances, so a widget test can hold the button
for two seconds).

**Not verified on a device.** Nobody has said a word into a real microphone yet:
latency, recognition quality and memory behaviour with the model loaded are all
unmeasured, and everything below the platform seam is a fake in the tests.

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

## The icon

A radar sweep: two rings, a sector opening from the centre, one amber blip on
the inner ring. Dark indigo tile, `#1B2050`.

Every file that ships it is drawn by `scripts/generate-app-icons.py` from one
set of constants at the top of that script — about twenty PNGs plus a
seven-image `.ico`, across web, Android and Windows. Change the geometry or the
colours there and re-run it; the SVG masters under `design/icon/` are written by
the same run, so they cannot drift from what ships:

```
python -m pip install pillow
python scripts/generate-app-icons.py
```

Three details are not the same drawing at different sizes, and the script says
why for each: the **maskable** web icons and the Android **adaptive**
foreground are full-bleed with the art pulled into the safe zone a launcher
mask cannot crop; the **apple-touch-icon** has square corners because iOS
rounds it itself and paints transparency black; and the **monochrome**
silhouette (Android 13 themed icons, and the status-bar icon at 24 dp) drops
the sector, which would merge with the rings once everything is one colour.

The status-bar icon is `@drawable/ic_notification`, resolved by name at run
time — which is what `res/raw/keep.xml` exists to protect from R8 (see Local
reminders, above).
