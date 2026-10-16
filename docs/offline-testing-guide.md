# Offline read tests on Android: setup and test logic

A portable guide based on the TaskRadar port (October 2026) of CashFlow's
offline suite. Copy it into another repository as the spec. It covers two
things:

- what to build into the app so cached content appears without the network;
- how to prove it on an emulator.

For the record of what TaskRadar itself does offline, see
[offline-capabilities.md](offline-capabilities.md).

## 1. First, write the matrix

List every screen and area, and answer three questions for each, before any
code or test. TaskRadar's answers are in `offline-capabilities.md`.

1. **No network, with a copy:** what is drawn, and how does it say that it is a
   copy?
2. **No network, never loaded:** what is the honest error, and where is the
   retry button?
3. **Writes:** queued, or failed out loud?

Decide which reads get a local copy. TaskRadar caches the board, the "in work"
set, project notes and the scope list. It does not cache history, the archive
or the AI screens. Anything not in the copy set needs an error with a retry
button, not an endless spinner.

## 2. App patterns that made the tests pass

| Problem found | Pattern | TaskRadar code |
| --- | --- | --- |
| Splash waited for `/auth/me` for up to 15 s when the server accepted and did not answer | A stored session opens the app immediately. The probe runs behind it, and only a 401 signs out | `Session.build` |
| Error page instead of yesterday's data | **Read-through cache:** start the request, read the copy, wait for the network for a short grace period (400 ms). On failure or timeout show the copy and mark it cached; when the late answer arrives, swap it in only if the list was not edited meanwhile. Every answer refreshes the copy | `readThroughCache`, `ReadCacheStore` |
| Cached data looked live | Track which keys are on screen from the copy, and show "Local copy from 09:40" | `cachedReadsProvider`, `LocalCopyNote` |
| A write against a list that never loaded returned normally, so the UI closed over the lost input | Throw the provider's error, or a `NotLoadedException` | `domain/not_loaded.dart` |
| A screen read only the network list, not the fold with the snapshot, and showed "loading" forever | Every screen reads the same fold that already falls back to the cache | `TaskScreen` → `projectViewProvider` |
| Queued lines waited for the next app restart | While the app is in front and something is unsent, retry every 30 s | `CaptureFlushScope` |
| One user's cache shown to another | When a different user signs in, wipe every per-user store | `Session._wipeLocalUserData` |

Make the cache store **never throw**. Treat an absent, truncated or
foreign-schema entry as "no copy". In widget tests, inject an in-memory store
globally (`test/flutter_test_config.dart`): real file I/O through
`path_provider` never completes inside the fake clock of a widget test.

## 3. Environment

The same as the Back suite (`android-back-testing-guide.md`, section 3): a
dedicated emulator, `adb`, `aapt`, Node 20+ with no npm packages, a QA package
under its own id, and a synthetic API on host loopback (`10.0.2.2` from the
emulator).

The QA build also carries the startup signal (section 5). Build it as
**release**, debug-signed, for the QA id only. TaskRadar measured profile
builds at about 2.1 s and release builds at 1.65–1.85 s on the same emulator.

## 4. Faults

`tests/android/lib/fault-server.mjs` wraps any in-memory API with three modes,
which `POST /__qa/control` switches:

| Mode | Behaviour | What it catches |
| --- | --- | --- |
| `online` | Normal answers | Baseline; writes the caches |
| `offline` | The socket is destroyed with no response. On top of that, the emulator radios are turned off (`svc wifi disable`, `svc data disable`) | An app that has no copy, or that treats an error as "empty" |
| `hanging` | The request is held open until the mode changes | **An app that waits for the network before drawing its cache.** An instant error cannot catch this |

`/__qa/control` also takes `mutate` (a change made "on another device", which
proves the refresh really landed) and `reseed`. `/__qa/status` returns the
mode, the calls (method, path, completed), the pending count, unexpected routes
and a minimal state view. It never contains bodies or tokens.

After turning the radios back on, wait for a real route
(`ping -c 1 10.0.2.2`), not a fixed sleep.

## 5. Measuring "the cached content is on screen"

`am start -W`, splash removal and automation round trips do not measure this.
Instead:

1. **QA build only:** when the first `BoardReady` with rows is built, wait one
   more frame. Then call the method channel `taskradar/qa`
   `cachedBoardRasterized` (`app/lib/qa/qa_signals.dart`).
2. **`MainActivity`, QA package only:** call `reportFullyDrawn()`.
3. **The runner:** write a marker to logcat, launch, and read this launch's
   `Fully drawn <pkg>/...: +N ms` and `Displayed <pkg>/...: +N ms`.

There are two assertions:

- **Cache on the first frame:** `Fully drawn` − `Displayed` ≤ 100 ms. This one
  does not depend on hardware. It proves nothing between process start and the
  rows waited for the network. In TaskRadar the two values are equal.
- **Absolute budget:** `Fully drawn` ≤ budget (2000 ms by default,
  `OFFLINE_STARTUP_BUDGET_MS` overrides it). This number belongs to the
  machine. Choose it per emulator **before** running, record it in the report,
  and never raise it in response to a failure.

Measurement hygiene: wait about 2 s after `force-stop` (and after a radio
change) before launching. Launching straight away adds 0.3–0.5 s of
process-teardown noise.

An over-budget start fails the pass only **at the end**. The scenario still
runs every functional check, so one slow cold start cannot hide whether the
offline behaviour works.

**Check the emulator before you blame the app.** TaskRadar measured
1.65–1.85 s on a fresh emulator. After about four hours of automation the same
APK took 3.2–4.3 s, and so did the launcher. These are the signs:

- `adb shell top` shows `graphics.composer3-service.ranchu` near 100% CPU, and
  the launcher busy on an idle home screen;
- `/proc/loadavg` stays above 3;
- swap is in use on a 2 GB AVD.

In that state, "Fully drawn" equals "Displayed": the cache is still on the
first frame, and only the platform got slower. Fix the machine (close host
load, reboot the AVD, give it more RAM), re-measure, and only then judge the
budget.

## 6. The scenario

`tests/android/run-offline.mjs`:

1. **Online.** Clear only the QA package. Sign in through the real form. Visit
   every screen whose copy you rely on (board, work set, notes). Wait until
   `/__qa/status` shows each read completed, then give the cache writes a
   moment.
2. **Offline.** Switch the API to `offline` and turn the radios off. Cold start.
   Assert:
   - the cached board is up within the budget, on the first frame;
   - the stale banner is shown;
   - no API call completed;
   - project → task opens from the snapshot;
   - a write shows "no connection";
   - notes and the work set are present and labelled as a copy.
3. **Restore.** Turn the radios on, wait for the route, and switch the server
   `online` with a renamed task. Press Retry. Assert the new title is shown and
   the banner is gone.
4. **Hanging.** Switch the API to `hanging`. Cold start: the cached board is up
   within the budget and a request is really pending. Hold for 30 s: nothing
   answered, and the board is still usable. Release with another rename, and
   assert it lands in place without signing in again.

**TaskRadar difference from CashFlow:** dio closes the socket after its own
10–15 s timeouts, so the pending count can be 0 by the end of the 30 s. The
assertion is "nothing answered and the screen did not care", and the report
records the counts.

Restore the radios and the handwriting setting in `finally`. Stop only the
server the run started (it runs inside the runner's own process).

## 7. What the emulator cannot cover

- **Capture through the microphone.** It needs a microphone and a model, so the
  queue is covered by `capture_queue_provider_test.dart`.
- **Physical phone timing and OEM power management.**
- **The real backend.** The synthetic API checks client behaviour only. Run the
  live contract tests (`app/test/live_*_contract_test.dart`) against a real
  server for that.

## 8. Porting checklist

- [ ] The matrix is written; the copy set is decided.
- [ ] Session start does not await the network.
- [ ] Read-through cache with a grace period, a "cached" marker, never-throwing storage, and a per-user wipe.
- [ ] Writes against unloaded lists throw; every screen reads the cache fold.
- [ ] The QA package (release, debug-signed, own id) emits the "useful frame" signal.
- [ ] A fault server with `online`, `offline` and `hanging`, plus radios off for `offline`.
- [ ] Both startup assertions; the budget is fixed before the run and recorded.
- [ ] Two consecutive passes with no retries; settings restored in `finally`.
