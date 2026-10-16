# Android Back button tests: setup and test logic

A portable guide based on the TaskRadar implementation (October 2026). Copy this
file into another repository and use it as the spec for the same checks.
TaskRadar is a Flutter app. The mechanism works with any app that exposes an
accessibility tree, and Flutter, Compose and Views all do.

Goal: for every text field and every screen, Back does one predictable thing.
This matters most when the soft keyboard is up, because Android consumes the
first Back press for itself. Text the user typed is never lost silently.

## 1. The contract

Settle these rules first and write them down before any test. The tests check
the rules, not the app's current behaviour.

| # | State when Back is pressed | Required result |
| --- | --- | --- |
| 1 | Keyboard up | Only the keyboard closes. Same screen, same text, no dialog |
| 2 | No unsaved input | Leave at once to the parent. **Never** show a dialog |
| 3 | Unsaved typed text on a full screen | "Discard changes?" dialog with *Stay*, *Discard*, and *Save* where the screen can save |
| 4 | Text field inside a dialog | The dialog closes; the screen under it stays |
| 5 | Popup menu or sheet open | Only the overlay closes |
| 6 | Root screen | The app goes to the background; reopening restores the signed-in state |
| 7 | After *Stay* | The dialog closes, the text is intact, and the keyboard does **not** come back by itself |
| 8 | The screen's own close or back arrow | Same rule as hardware Back (`maybePop`, not `pop`) |

Why these rules:

- **Rule 2:** a dialog in front of every read-only Back trains people to
  dismiss dialogs without reading them.
- **Rule 7:** after two Backs, the user is done typing. When the dialog closes,
  Flutter (and Views) hand focus back to the field, so the keyboard pops up
  again unless the app removes focus before it opens the dialog.
- **Rule 8:** an on-screen close button that calls `pop()` bypasses the guard.
  Hardware Back calls `maybePop`, so the two would behave differently.

Decide per product whether a non-root tab (for example "Work" in a bottom
navigation) should return to the home tab or leave the app. TaskRadar leaves
the app: modes are not a history. Whichever you choose, put it in the table and
test it.

## 2. App side (Flutter)

- **Use one guard widget for every screen with typed text.** TaskRadar's is
  `app/lib/widgets/unsaved_changes_guard.dart`. It wraps `PopScope` with these
  settings:
  - `canPop: !isDirty()`.
  - Rebuilds only the `PopScope` on each controller change (`ListenableBuilder`).
  - Unfocuses before showing the dialog (rule 7).
  - Pops with `Navigator.pop()` after *Discard* or after a successful *Save*.
    `pop` ignores `PopScope`; `maybePop` does not.
- **Define "dirty" against the last saved value, not "the field is non-empty".**
  An existing record is dirty only when its fields differ from what was saved.
  A new record is dirty when anything has been typed.
- **An inline field guards the screen it sits on.** A `PopScope` anywhere in a
  route's subtree registers with that route.
- **Unit-test the rule.** Call `tester.binding.handlePopRoute()`, which is how
  Back reaches the app once the IME has had its turn
  (`app/test/back_guard_test.dart`). This is fast, but it cannot see the
  keyboard. The emulator suite is what covers rule 1.

## 3. Environment

| Tool | Notes |
| --- | --- |
| Android Emulator and an AVD | A phone profile. TaskRadar uses API 36, 1080×2400. Refuse to run on a physical device: the suite clears app data |
| `adb` (platform-tools) | The only runtime dependency of the runner |
| `aapt` (build-tools) | Checks the package name inside the APK before installing |
| Node.js 20+ | Runner and synthetic API. **No npm packages**, so nothing to install |
| A separate QA package | `<app id>.qa`. Its own data, cleartext to the test API, and a label that says QA |

### Build a QA package that cannot replace the real app

- **Use one define for both sides.** Gradle reads the same
  `--dart-define=<APP>_QA=true` that enables the QA code in Dart, decoding
  `dart-defines` from the `dart-defines` project property. A separate
  environment variable can silently miss the Gradle daemon and produce an APK
  under the real id.
- **QA builds get `applicationIdSuffix = ".qa"`.** Use manifest placeholders for
  the label and for `usesCleartextTraffic`. The debug manifest then needs
  `tools:replace` for that attribute.
- **Build release, debug-signed, for the QA id only.** A profile build carries
  the VM service and adds about 0.5 s to cold start, which matters if you also
  time startup. Keep the release-signing guard for every other build.
- **Check the APK before installing:** run
  `aapt dump badging <apk> | head -1` and refuse anything that is not the QA id.

### Talk to a synthetic API, not production

- **Bind the API to loopback.** The emulator reaches the host's loopback at
  `10.0.2.2`. Do not use `adb reverse`, which also defeats network-off tests.
- **Keep the API in memory and seeded with synthetic data.** Return 404 for
  unknown routes and record them as "unexpected", so a new endpoint shows up in
  the report instead of as a blank screen.
- **Do not log request bodies or headers.**

TaskRadar's API is `tests/android/taskradar/fake-api.mjs`. It is wrapped by the
generic `tests/android/lib/fault-server.mjs`.

### Prepare the emulator

- Run `adb shell settings put secure stylus_handwriting_enabled 0`. On API 36,
  Gboard's stylus tutorial steals focus from injected taps. Save the old value
  and restore it in `finally`.
- Use the default Gboard IME. The suite detects the keyboard with
  `dumpsys input_method` (`mInputShown=true|false`). That flag is the IME
  manager's own, and it works on any keyboard.

## 4. How the runner reads and drives the app

All of this lives in `tests/android/lib/device.mjs` and uses plain adb:

| Need | How |
| --- | --- |
| UI tree | `adb exec-out uiautomator dump /dev/tty`, parsed to nodes |
| Find an element | By `resource-id`, or by a text match on `text`, `content-desc` or `hint` |
| Keyboard state | `dumpsys input_method`, then `mInputShown` |
| Back | `input keyevent KEYCODE_BACK` |
| Typing | `input text`, ASCII only. adb cannot type Cyrillic, and the language of the text does not matter for these checks |
| Which app is in front | `dumpsys window displays`, then `mCurrentFocus` / `mFocusedApp` |

What a Flutter app looks like in that tree:

- A button's tooltip or label is `content-desc`.
- A text field is an `EditText` whose value is `text` and whose label or hint is
  `hint`.
- `Semantics(identifier:)` becomes `resource-id`.
- A password field shows dots, so check its length, not its content.
- Fields with sentence capitalisation turn "qa" into "Qa", so compare
  case-insensitively.

## 5. The protocol per field

`tests/android/lib/back-contract.mjs` runs these steps for every row. Each step
records an observation, and the first failed expectation stops the row with a
summary of the screen.

1. **Open the screen.** Assert something that only this screen draws: its
   identity, not just "some text".
2. **Tap the field.** Assert the keyboard is up and an editable node is focused.
3. **Type a marker** (`qa edit`). Assert the field holds it.
4. **Back.** Assert the keyboard is down, the screen is the same, and the marker
   is still in the field (rule 1).
5. **Back.** Apply the screen's rule:
   - `confirm`: the dialog appears. Tap *Stay* and assert the dialog is gone,
     the text is kept and the keyboard is down (rule 7). Back again, the dialog
     appears again, tap *Discard*, and assert the parent screen.
   - `close`: the parent is visible and the dialog's identity is gone.
   - `leave`: the parent is visible.
   - `exit`: the app is no longer the focused package.
6. **Final check:** no keyboard on the parent. If the row has an `after` hook,
   it asserts side effects, for example that a discarded text never reached the
   server.

Add these rows next to the per-field ones:

- **Clean Back:** open each screen and press Back without typing. The parent
  must appear and no dialog may appear (rule 2).
- **Overlay:** open a popup menu and press Back. The menu closes and the screen
  stays (rule 5).
- **Hierarchy:** go board → project → task, then Back three times: project,
  board, launcher. Relaunch and assert the user is still signed in (rule 6).

Every row starts from a cold start of the signed-in app (force-stop, launch),
so no row depends on another. Signed-out rows (the login form) run first,
before one real sign-in through the form.

## 6. Writing the project table

One row per reachable text field. TaskRadar's table is
`tests/android/taskradar/back-scenarios.mjs`:

```js
{ kind: 'field', name: 'task / title', open: task, screen: SCREENS.task,
  field: { text: 'Купить плитку' }, text: ' qa edit', back: 'confirm',
  dialog: { title: 'Выйти без сохранения?', stay: 'Остаться', discard: 'Выйти' },
  parent: SCREENS.project, after: nothingSaved('qa edit') },
```

To build the inventory, search the code for `TextField`, `TextFormField` and
custom field widgets, and note where each one lives: route, inline, dialog,
bottom sheet, dialog-inside-sheet. List every `PopScope` and `WillPopScope`. A
field you cannot reach with synthetic data (it needs a microphone, a model, or
an AI backend) gets a widget test instead, and the table says so.

Navigation helpers (`board()`, `project()`, `task()`) open screens by tapping
labels, never by coordinates. If a label is ambiguous, add a
`Semantics(identifier:)` to the app instead of making the selector more clever.

## 7. Running it

TaskRadar, with the emulator already running:

```powershell
.\scripts\test-android-qa.ps1 -Device emulator-5554            # build, verify, install, 2 passes of both suites
.\scripts\test-android-qa.ps1 -SkipBuild -Suite back -Passes 1
node tests/android/run-back.mjs --only "task /"                 # one group, while developing
```

Reports go to `tests/android/results/back-pass-N.json`, which Git ignores. Each
report holds every step of every row, plus the screen summary of the first
failure.

**Acceptance means two consecutive green passes with no retries.** A row that
passes on the second attempt is a finding, not a pass.

## 8. Lessons from the first TaskRadar run

- **Back silently lost text on five screens.** These were the task screen (both
  an existing task and a new draft), dictation, "Причесать", the open sandbox
  line and the new-note composer. Only the note editor asked.
- **The keyboard came back after "Остаться"** because the dialog restored focus
  to the field. The fix is rule 7, unfocus before showing the dialog.
- **On-screen close buttons called `pop()`.** They bypassed the guard until they
  were switched to `maybePop()` (rule 8).
- **Two false alarms came from the runner, not the app.** Sentence
  capitalisation needs a case-insensitive comparison, and a password field
  needs a length check.
- **A full pass of 24 rows takes about 12 minutes** on API 36. Almost all of
  that is `uiautomator dump` (about 1–1.5 s per read).

## 9. Porting checklist

- [ ] The rules table is written down, including the root-screen and tab decisions.
- [ ] One guard widget; every on-screen close button uses `maybePop`.
- [ ] A QA package under its own id; the APK id is checked before install.
- [ ] A synthetic API on loopback; unknown routes are recorded.
- [ ] Inventory of every text field and where it lives; unreachable ones covered by widget tests.
- [ ] Rows: per field, clean Back per screen, overlays, the hierarchy chain.
- [ ] Emulator settings saved and restored in `finally`.
- [ ] Two consecutive green passes, no retries; the reports are kept out of Git.
