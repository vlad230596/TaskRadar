# What TaskRadar does without a network

This is the contract as of 25 October 2026. Two test suites enforce it: the
widget and provider tests in `app/test/` (`offline_reads_test.dart`,
`back_guard_test.dart`, `session_provider_test.dart` and others), and the
emulator suite in `tests/android/` (`run-offline.mjs`). If the app's behaviour
changes, update this table, the tests and the code together.

## Policy

- **Reads come from a local copy. Most writes need the server.** Two kinds
  of write go into an on-device queue instead: capturing a line into the
  sandbox (the capture queue), and creating a task or editing its fields --
  title, description, status, reminder, category (the outbox). Deletes, moves,
  notes, projects, categories and the "in work" set still need the network.
- **Offline task edits are gentle, not merged.** A create carries an
  idempotency key (`createKey`), so a replay cannot make a twin. An edit
  carries the values it was made against (`expected`); if the server's task
  changed meanwhile, the edit is skipped -- the server's value stays -- and the
  history mode's «Офлайн» view shows both values with «Применить моё»,
  «Скопировать» and «Оставить».
- **Cached data says that it is cached.** The board shows "Данные из кэша". A
  project, its notes and the "in work" set show "Показан локальный снимок" or
  "Локальная копия от …".
- **A failed write fails visibly.** Unless the outbox took it, the optimistic
  change is rolled back and a snackbar says "… Нет связи с сервером." A write
  against a list that never loaded, or whose load failed, loads it first; it
  never answers with the stored error of an old failed load.
- **Unsent is marked.** A row from the outbox says "не отправлено", turns
  green ("отправлено") for a few seconds once sent, then looks like any other.
  The history mode's icon and its «Офлайн» switch carry the count.
- **A slow server and an absent server look the same.** A stored session opens
  the app at once. Each cached read waits at most `readCacheGrace` (400 ms)
  before it shows the copy.
- **The cache belongs to one user.** When a different person signs in, the
  board snapshot, the read cache, the capture queue, the outbox and the
  selected scope are all wiped.

## Matrix

"Cached" means the screen draws the last good server answer. The cache is
updated on every successful read.

| Area | No network, with a copy | No network, no copy | Writes offline |
| --- | --- | --- | --- |
| Start with a stored session | Opens straight to the last mode. `/auth/me` is checked in the background, and only a 401 signs out | Same | — |
| Login | — | "Не удалось подключиться к серверу" | — |
| Logout | Works. Deletes the token locally | Same | — |
| Board (plan mode) | Cached (`board-snapshot.v1.json`), with "Данные из кэша" and Повторить | "Не удалось загрузить доску… Локального снимка тоже нет" | Create project: snackbar |
| Scope list and switcher | Cached (`read-cache.v1/scopes`). The remembered scope still applies | No switcher; all scopes shown | Create, rename and move: snackbar or rollback |
| "В работе" set (work mode, plan strip) | Cached (`read-cache.v1/focus`), with "Локальная копия от …" | Error page with Повторить; the strip says "не загрузилось" | Take, drop, done: rollback and snackbar |
| Project: tasks | From the board snapshot, with "Показан локальный снимок — задачи и правки уйдут, когда появится связь" | "Не удалось открыть проект… Локального снимка… нет" | Create, status, title, description, reminder, category: **outbox**, marked "не отправлено". Reorder, delete, unfile: snackbar ("Нет связи") |
| Project: notes | Cached per project (`read-cache.v1/notes.<id>`), with "Локальная копия" | Error on the notes tab with Повторить | Create, edit, delete: rollback and snackbar. The typed title stays in the field |
| Task screen | Opens from the project snapshot | "Не удалось открыть задачу…" with Повторить | Field edits: outbox. A task created offline cannot be opened until it is sent |
| Task life (event journal) | Not cached; the block collapses with an error mark | Same | — |
| History mode | Not cached: error with Повторить. A failed refresh keeps the data it already had | Same | Read-only. «Офлайн» works: the outbox and a week of what it sent |
| Archive | Not cached: error with Повторить | Same | Snackbar |
| Sandbox: capture | **Works.** Lines are queued on disk and marked "не отправлено" | Same | Sent on start, on resume, on pull-to-refresh, after each capture, and every 30 s while the app is in front with something unsent |
| Sandbox: existing lines | Server lines already in memory stay. Queued lines are always shown | "Не удалось загрузить песочницу" (pull to retry) | Edit, file, discard: snackbar |
| Dictation: recording and recognition | **Works** on the device once the model is downloaded | Same | — |
| Dictation: "Разобрать" (AI) | "Нет связи с сервером — можно сохранить как есть". The words are kept | Same | Saving to the sandbox works (capture queue). Saving to a project works (outbox): "сохранена на телефоне — уйдёт при связи" |
| "Причесать" (AI tidy) | Same failure message. The source text stays editable | Same | — |
| Settings: reminder time, AI level, notifications, dictation archive | Local, all work | Same | Local |
| Settings: AI models, statistics, prompts | "Нет связи с сервером." | Same | Snackbar |
| Voice model download | Needs the network | Same | — |
| Reminders | Armed from the board snapshot. They fire with no network | No snapshot: nothing new is armed | — |
| Notification tap | Opens the project and task from the snapshot | "Не удалось открыть задачу… Локального снимка нет" with Повторить | — |

## Where it lives

| Piece | File |
| --- | --- |
| Board snapshot | `app/lib/storage/board_snapshot_store.dart`, `boardView` in `app/lib/providers/board_providers.dart` |
| Read cache (set, notes, scopes) | `app/lib/storage/read_cache_store.dart`, `readThroughCache` in `app/lib/providers/read_cache_providers.dart` |
| "Cached" indicator | `app/lib/widgets/local_copy_note.dart`, `_StaleBanner` in `plan_screen.dart`, `_ProjectBanner` in `project_screen.dart` |
| Non-blocking session start | `Session.build` in `app/lib/providers/session_provider.dart` |
| Loud failure for a list that never loaded | `app/lib/domain/not_loaded.dart` and the writers in `project_providers.dart` and `focus_providers.dart` |
| Capture queue and its retries | `app/lib/providers/capture_queue_providers.dart`, `app/lib/widgets/capture_flush_scope.dart` |
| Outbox of task writes | `app/lib/storage/outbox_store.dart`, `app/lib/providers/outbox_providers.dart`, `app/lib/domain/outbox_overlay.dart`, «Офлайн» in `app/lib/widgets/outbox_history.dart`; server side `createKey` and `expected` in `backend/src/routes/tasks.ts` |

## Known limits

These are deliberate, or not yet covered:

- **Offline editing is task fields only.** Notes, projects, categories,
  moves and deletes still need the network. A task created offline cannot be
  edited or opened until it is sent.
- **Skipped edits are whole.** An edit that conflicts on one of its fields
  (e.g. "Причесать" saving title and description together) is skipped as a
  whole. The server check has a small race window between its read and its
  write (see `routes/tasks.ts`).
- **History, archive, the task journal and the AI screens** are not cached.
- **Sandbox sending** has no background worker. Lines go out only while the app
  is running.
- **The emulator suite cannot capture into the sandbox.** Capture needs the
  microphone and the 225 MB model, so `capture_queue_provider_test.dart` covers
  the queue instead.
- **No board snapshot means reminders are not re-armed.** If the snapshot is
  missing (fresh install, wiped, unreadable) and there is no network, the
  reminder sync has nothing to arm until the board loads.
- **Timing is measured on an emulator.** It is not proof for a physical phone.
