import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'dependencies.dart';

part 'shell_providers.g.dart';

/// Which of the three modes the app is in, and how planning is drawing projects
/// (F12).
///
/// ## Why the mode is state and not a route
///
/// Same argument `app.dart` makes about being signed in. The three modes are
/// not places you navigate *to* -- they are three answers to "what should be on
/// screen right now", and exactly one of them is true at a time. As a route,
/// every mode switch would push or replace a page, the back button would walk
/// backwards through modes the user did not think of as history, and restoring
/// the last mode at startup would mean synthesising a navigation stack. As
/// state it is one integer, the back button keeps meaning "out of this
/// sub-screen", and restoring it is a read.
///
/// The sub-screens (a project, a task, the sandbox, the dictation screen) are
/// still real routes pushed **on top** of the shell, exactly as F3 arranged
/// them -- so this sits between the session switch and the router rather than
/// replacing either.

/// The three modes, in the order they appear in the bottom bar.
///
/// Each carries the string it is stored as. Stored by name rather than by index
/// because an index is only stable as long as nobody inserts a mode; a name
/// survives reordering, and an unrecognised one falls back to [AppMode.plan]
/// instead of landing on whatever happens to be at that position now.
enum AppMode {
  /// Everything that needs a decision: projects, ages, the sandbox.
  plan('plan'),

  /// The two-to-five tasks actually being worked on. F13 fills it.
  work('work'),

  /// What is closed and what has been hanging around. F13 fills it.
  history('history');

  const AppMode(this.wireName);

  final String wireName;

  /// The mode stored under [wireName], or null if this build has never heard of
  /// it.
  static AppMode? fromWireName(String? name) {
    if (name == null) return null;
    for (final mode in values) {
      if (mode.wireName == name) return mode;
    }
    return null;
  }
}

/// How the planning mode draws projects.
///
/// The spec calls the two **equal** ("вариант плиток равноправный"), which is
/// why this is remembered rather than reset: a list is better for reading the
/// current task of each project, tiles are better for seeing fifteen of them at
/// once, and which one a person wants is a fact about them rather than about
/// the session.
enum PlanLayout {
  list('list'),
  tiles('tiles');

  const PlanLayout(this.wireName);

  final String wireName;

  static PlanLayout? fromWireName(String? name) {
    if (name == null) return null;
    for (final layout in values) {
      if (layout.wireName == name) return layout;
    }
    return null;
  }
}

/// The mode the app is in.
///
/// ## Why this is synchronous and the stored value arrives late
///
/// The obvious shape is `Future<AppMode>` -- read the preference, then build
/// the shell. That would put a spinner in front of the whole app on every cold
/// start in exchange for one `getString`, and on a slow first
/// `SharedPreferences.getInstance` that spinner is visible. Instead the mode
/// starts at [AppMode.plan] and the stored one is applied when it arrives,
/// which is a frame or two later and before anything is readable.
///
/// The ordering hazard that creates is real and handled: if the user taps
/// "Работа" inside that window, the restore must not drag them back. Hence
/// [_restored] -- an explicit choice wins over a late read, permanently.
@Riverpod(keepAlive: true)
class ShellMode extends _$ShellMode {
  /// True once the stored mode has been applied *or* deliberately discarded.
  /// Not the same as "the read finished": a user tap sets it too.
  bool _restored = false;

  @override
  AppMode build() {
    _restore();
    return AppMode.plan;
  }

  Future<void> _restore() async {
    final stored = AppMode.fromWireName(
      await ref.read(settingsStoreProvider).readAppMode(),
    );
    if (!ref.mounted || _restored) return;
    _restored = true;
    if (stored != null) state = stored;
  }

  /// Switches mode and remembers it.
  ///
  /// The write's failure is swallowed on purpose, exactly as the scope
  /// selection's is: a preference that could not be persisted must not make the
  /// screen refuse to change under the user's finger. The worst case is that
  /// the app opens on planning tomorrow.
  Future<void> select(AppMode mode) async {
    _restored = true;
    if (state == mode) return;
    state = mode;
    try {
      await ref.read(settingsStoreProvider).writeAppMode(mode.wireName);
    } catch (_) {
      // Deliberately swallowed; see above.
    }
  }
}

/// Which way planning is drawing projects. Same restore-vs-tap rule as
/// [ShellMode].
@Riverpod(keepAlive: true)
class PlanLayoutPreference extends _$PlanLayoutPreference {
  bool _restored = false;

  @override
  PlanLayout build() {
    _restore();
    return PlanLayout.list;
  }

  Future<void> _restore() async {
    final stored = PlanLayout.fromWireName(
      await ref.read(settingsStoreProvider).readPlanLayout(),
    );
    if (!ref.mounted || _restored) return;
    _restored = true;
    if (stored != null) state = stored;
  }

  Future<void> select(PlanLayout layout) async {
    _restored = true;
    if (state == layout) return;
    state = layout;
    try {
      await ref.read(settingsStoreProvider).writePlanLayout(layout.wireName);
    } catch (_) {
      // Deliberately swallowed; see [ShellMode.select].
    }
  }
}
