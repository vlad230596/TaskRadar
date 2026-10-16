# Android emulator checks

Two suites run against the isolated QA package `com.taskradar.app.qa`:

- `run-back.mjs`: what Android Back does in every text field, on every screen
  and through the screen hierarchy. The rules are in
  [`docs/android-back-testing-guide.md`](../../docs/android-back-testing-guide.md).
- `run-offline.mjs`: a cold start with no network and with a hanging server,
  a timed cached board, the cached screens, and the refresh once the network is
  back. See [`docs/offline-testing-guide.md`](../../docs/offline-testing-guide.md)
  and [`docs/offline-capabilities.md`](../../docs/offline-capabilities.md).

## Run

With a dedicated emulator already running, from the repository root:

```powershell
.\scripts\test-android-qa.ps1 -Device emulator-5554
```

The script does five things:

1. Builds the QA APK: release, debug-signed, `TASKRADAR_QA=true`, API at
   `http://10.0.2.2:18743`.
2. Checks the package **inside** the APK with `aapt`.
3. Installs it.
4. Runs both suites twice in a row with no retries.
5. Stops at the first failure.

Useful variants:

- `-SkipBuild` reuses `results/taskradar-qa.apk`.
- `-Suite back|offline` runs one suite.
- `-Passes 1` runs a single pass.
- While developing, run the runners directly:
  `node tests/android/run-back.mjs --only "task /"`.

Each runner starts its own synthetic API on `127.0.0.1:18743`. That port must
be free.

## Layout

| Path | What | Copy to another project |
| --- | --- | --- |
| `lib/device.mjs` | adb wrapper: UI tree, keyboard state, Back, typing, radios | As is |
| `lib/fault-server.mjs` | HTTP server with `online`, `offline` and `hanging` around any in-memory API | As is |
| `lib/back-contract.mjs` | The Back protocol for one field, clean Back | As is |
| `taskradar/fake-api.mjs` | TaskRadar's API contract in memory, with synthetic data | Rewrite |
| `taskradar/app.mjs` | Package, ports, sign-in through the form | Rewrite |
| `taskradar/back-scenarios.mjs` | The table of fields and screens | Rewrite |
| `run-back.mjs`, `run-offline.mjs` | Runners and reports | Adapt |
| `results/` | APK, `back-pass-N.json`, `offline-pass-N.json` (Git-ignored) | — |

Nothing here needs npm: Node 20+ and the Android SDK are enough.

## Safety

- **Only `emulator-*` serials are accepted.** The suites clear app data.
- **Only the QA package is cleared or installed.** The regular
  `com.taskradar.app` and its data are never touched.
- **The synthetic account and data never leave loopback.** Reports contain no
  bodies, tokens or passwords.
- **Settings are restored in `finally`.** The suites change Wi-Fi, mobile data
  and Gboard's `stylus_handwriting_enabled`.

## Not covered here

- **Dictation and AI screens.** They need a microphone, the model or the AI
  server. Their offline wording is covered by `dictation_parse_test.dart`. The
  Back guard on the dictation and "Причесать" screens has **no automated check
  yet**: it is the same `UnsavedChangesGuard` that `back_guard_test.dart`
  covers on the task screen, but nothing exercises it on those two screens.
- **CI.** The suites run locally; an emulator in CI needs hardware
  acceleration.
- **Physical phone timing.**
