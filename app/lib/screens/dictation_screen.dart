import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dictation_api.dart';
import '../models/board_project.dart';
import '../providers/board_providers.dart';
import '../providers/capture_queue_providers.dart';
import '../providers/project_providers.dart';
import '../providers/voice_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ai_tidy.dart';
import '../widgets/dictation.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/tidy_progress.dart';

/// Where a dictation's words are going. Shown at the top of the screen, and
/// changeable *before* "Готово" -- which is the point of showing it.
///
/// The old behaviour was that a dictation belonged to whatever field the
/// microphone sat next to, decided before you spoke. In practice the decision is
/// made *by* speaking: a sentence turns out to be a task for "Дом" rather than a
/// line for the sandbox only once it has been said. So the destination is a
/// control on the screen rather than a property of the button that opened it.
sealed class DictationDestination {
  const DictationDestination();

  /// What the chip at the top of the screen says.
  String get label;
}

/// Straight into the sandbox, to be filed later. The default, because it is the
/// destination that requires no decision at all.
final class SandboxDestination extends DictationDestination {
  const SandboxDestination();

  @override
  String get label => 'Песочница';
}

/// Into a project, as a new task.
final class ProjectDestination extends DictationDestination {
  const ProjectDestination({required this.projectId, required this.name});

  final String projectId;
  final String name;

  @override
  String get label => name;
}

/// Back to the field that opened this screen -- the task text, a sandbox line.
///
/// Nothing is written anywhere: the screen pops with the text and the caller
/// puts it where it belongs. Not switchable, because the caller is a field that
/// is already open behind this screen and "send it somewhere else instead"
/// would leave that field waiting for words that went elsewhere.
final class FieldDestination extends DictationDestination {
  const FieldDestination(this.label, {this.kind = ParseKind.note});

  @override
  final String label;

  /// What "Разобрать" makes of the words for this field: [ParseKind.note] for
  /// a note, [ParseKind.taskTidy] for a task's text, [ParseKind.sandbox] for a
  /// sandbox line. Never [ParseKind.task] -- a field gets text back, and a
  /// reminder has nowhere to go in it.
  final ParseKind kind;
}

/// The dictation screen: dark, full of screen, and already recording (F12).
///
/// ## The five things the spec asked for, and where each one is
///
/// 1. **Recording starts on open.** [_DictationScreenState.initState] calls
///    `start`. There is no second action, no button to find, and nothing to
///    hold. See `providers/voice_providers.dart` for the three ordering
///    defects that made the old "press to start" fail on the first press.
/// 2. **No hold anywhere.** The only controls are "Готово", "Отменить", and the
///    text area.
/// 3. **The screen is up while the model loads**, and says so. The audio is
///    being written from the first frame regardless -- the weights are only
///    needed when the recording *ends*.
/// 4. **What was heard is 25 px on half the screen**, in a real text field, so
///    a misheard word is corrected here rather than found tomorrow.
/// 5. **Where it is going is visible and switchable** before "Готово".
///
/// ## Why "Готово" means two things and that is not ambiguity
///
/// While recording it stops and recognises; afterwards it saves and leaves. In
/// both cases it means "я закончил", which is the only thought the user has. The
/// alternative -- a separate "Стоп" and "Сохранить" -- puts two buttons in the
/// same 76 px of thumb, one of which is wrong at any given moment.
class DictationScreen extends ConsumerStatefulWidget {
  const DictationScreen({
    this.destination = const SandboxDestination(),
    super.key,
  });

  /// Where the text goes unless the user says otherwise.
  final DictationDestination destination;

  @override
  ConsumerState<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends ConsumerState<DictationScreen> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  late DictationDestination _destination = widget.destination;

  /// True once the user has committed and the screen is on its way out, so a
  /// rebuild cannot start a second save or a second recording.
  bool _leaving = false;

  /// True while the server's model is working on the words (F14). Shown as
  /// its own stage, and keeps "Готово" from saving twice.
  bool _tidying = false;

  /// The model's answer, once "Разобрать" has been pressed and answered.
  /// Non-null means "Результат AI | Исходник" is on screen, and the answer is
  /// what "Готово" saves. Of the subtype [_kind] asked for.
  TidyResult? _result;

  /// Whether the "Исходник" half is showing -- the words, editable, which
  /// every "Разобрать заново" starts from.
  bool _showSource = false;

  /// The answer as a task: [ParsedDictation], [TidiedTask].
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  /// The answer as one text: [TidiedNote], [TidiedLine].
  final TextEditingController _resultText = TextEditingController();

  /// The proposed reminder, `YYYY-MM-DD`. Separate from [_result] because the
  /// user can take it off without throwing the rest of the proposal away.
  String? _remindDate;

  /// Why the last "Разобрать" did not work, said under the words. Null once
  /// anything else happens.
  String? _tidyProblem;

  /// The stages of the "Разобрать" under way, or of the one that failed and
  /// can be repeated -- the card under the words. Null when there is neither.
  TidyProgress? _progress;

  /// The running parse; cancelled by "Отменить", and when the screen goes.
  TidyJob? _job;

  @override
  void initState() {
    super.initState();
    // After the first frame, not during it: `start` publishes state
    // synchronously before its first await, and a provider write inside
    // `initState` runs while this widget is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  @override
  void dispose() {
    _job?.cancel();
    _text.dispose();
    _textFocus.dispose();
    _title.dispose();
    _description.dispose();
    _resultText.dispose();
    super.dispose();
  }

  void _begin() {
    if (!mounted) return;
    unawaited(
      ref
          .read(voiceDictationProvider.notifier)
          .start(sink: (text) => appendDictated(_text, text: text)),
    );
  }

  /// The one button. See the note on the class.
  Future<void> _done() async {
    if (_leaving) return;
    final dictation = ref.read(voiceDictationProvider.notifier);

    if (ref.read(voiceDictationProvider) is DictationRecording) {
      unawaited(HapticFeedback.lightImpact());
      await dictation.finish();
      // Deliberately does not fall through to saving. Recognition takes
      // seconds, and a "Готово" that both stopped the recording and committed
      // whatever text happened to exist would commit the *previous* phrase.
      return;
    }

    await _save();
  }

  /// Ends the recording without committing, so the text can be corrected.
  ///
  /// This is the spec's "тап по области текста": the natural way to say "хватит,
  /// дальше я руками" is to reach for the words.
  Future<void> _stopForEditing() async {
    if (ref.read(voiceDictationProvider) is! DictationRecording) return;
    await ref.read(voiceDictationProvider.notifier).finish();
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      // Nothing to save is not a failure worth a dialog: leaving is what the
      // user meant.
      await _leave(null);
      return;
    }

    switch (_destination) {
      case FieldDestination():
        await _leave(_result == null ? text : _fieldText());

      case SandboxDestination():
        final line = _result is TidiedLine ? _resultText.text.trim() : '';
        // Through the capture queue like everything else the sandbox accepts,
        // so dictating with no signal writes the line to disk and sends it when
        // there is a network (F8.1).
        final ok = await runMutation(
          context,
          () => ref
              .read(captureQueueProvider.notifier)
              .capture(line.isEmpty ? text : line),
          failure: 'Не удалось записать строчку на устройство.',
        );
        if (ok) await _leave(null);

      case ProjectDestination(:final projectId, :final name):
        // What is on screen is what is saved: the proposal if "Разобрать" was
        // pressed and answered, the words as they stand otherwise. Never a
        // silent round trip to the model on the way out -- the user should
        // not find a title in the project they did not see here.
        final proposal = _result is ParsedDictation ? _result : null;
        final parsed = proposal != null;
        final title = parsed ? _title.text.trim() : '';
        final description = parsed ? _description.text.trim() : '';
        final remindDate = parsed ? _remindDate : null;
        final ok = await runMutation(
          context,
          () => _createTask(
            projectId,
            title.isEmpty ? text : title,
            description: description.isEmpty ? null : description,
            remindAt: remindDate,
            // Only when the proposal is what is being saved: after "Как
            // надиктовано" the task is the raw words, and labelling the sample
            // with them would score the model against an answer it never gave.
            dictationParseId: proposal?.parseId,
          ),
          success: remindDate == null
              ? 'Задача добавлена в «$name».'
              : 'Задача добавлена в «$name», напомню ${_shortDate(remindDate)}.',
          failure: 'Не удалось добавить задачу.',
        );
        if (ok) await _leave(null);
    }
  }

  /// What "Разобрать" turns the words into, which is where they are going:
  /// a task with a reminder for a project, a tidied line for the sandbox,
  /// and for a field whatever that field holds.
  ParseKind get _kind => switch (_destination) {
    ProjectDestination() => ParseKind.task,
    SandboxDestination() => ParseKind.sandbox,
    FieldDestination(:final kind) => kind,
  };

  /// "Разобрать": the words tidied by the server's model -- for a project a
  /// verb-first title, the rest as the description, "напомни в пятницу" as a
  /// date -- shown on this screen for correction before anything is saved
  /// (F14; every destination since F15).
  ///
  /// ## Why a button and not a step inside "Готово"
  ///
  /// It was a step inside "Готово" first, and it was opaque: the words on the
  /// screen were one thing, the task that landed in the project another, and
  /// whether the model had been reached at all was invisible. Now nothing
  /// happens to the words unless asked, the answer is on screen before it is
  /// saved, and a failure is said out loud instead of being swallowed.
  ///
  /// ## Always from the words
  ///
  /// The words stay in the text field -- "Исходник" -- and every run, the
  /// first and "Разобрать заново", sends them, never the previous answer. See
  /// `widgets/ai_tidy.dart`.
  ///
  /// ## Why the stages are shown
  ///
  /// A long dictation keeps the model busy for tens of seconds, and a spinner
  /// that long cannot be told from a request that died. So the parse is a
  /// stream of stages (`DictationApi.parseStream`), drawn as a card of steps
  /// with their times and a line saying when the server was last heard from.
  /// It fails only when the server has been silent for 20 s, never for being
  /// slow, and a failure keeps the card with "Повторить".
  void _tidy() {
    final text = _text.text.trim();
    if (text.isEmpty || _tidying) return;
    FocusScope.of(context).unfocus();
    _job?.cancel();

    late final TidyJob job;
    job = TidyJob.start(
      ref,
      kind: _kind,
      text: text,
      onProgress: () {
        if (mounted && _job == job) setState(() {});
      },
      onDone: (result) {
        if (!mounted || _job != job) return;
        setState(() {
          _job = null;
          _tidying = false;
          _progress = null;
          _showResult(result);
        });
      },
      onFailed: (failure) {
        if (!mounted || _job != job) return;
        setState(() {
          _job = null;
          _tidying = false;
          if (failure.unavailable) {
            // Nothing to repeat: the server has no model. Said under the
            // words, as before the stages existed.
            _progress = null;
            _tidyProblem = failure.message;
          }
        });
      },
    );
    setState(() {
      _job = job;
      _tidying = true;
      _tidyProblem = null;
      _progress = job.progress;
    });
  }

  /// "Разобрать заново": from the words as they now stand in "Исходник".
  void _rerun() {
    setState(() => _showSource = true);
    _tidy();
  }

  void _showResult(TidyResult result) {
    _result = result;
    _showSource = false;
    switch (result) {
      case ParsedDictation(:final title, :final description, :final remindDate):
        _title.text = title;
        _description.text = description ?? '';
        _remindDate = remindDate;
      case TidiedTask(:final title, :final description):
        _title.text = title;
        _description.text = description ?? '';
        _remindDate = null;
      case TidiedNote(:final content):
        _resultText.text = content;
      case TidiedLine(:final text):
        _resultText.text = text;
    }
  }

  /// "Отменить" on the card: the parse is dropped -- the connection with it,
  /// so the server stops asking the model -- and the words stay as they are.
  void _cancelTidy() {
    _job?.cancel();
    _job = null;
    setState(() {
      _tidying = false;
      _progress = null;
    });
  }

  /// "Как надиктовано": back to the words, the answer thrown away.
  void _untidy() {
    _job?.cancel();
    _job = null;
    setState(() {
      _tidying = false;
      _progress = null;
      _result = null;
      _showSource = false;
      _remindDate = null;
    });
  }

  /// The sandbox answer's project, taken: the words go to that project as a
  /// task instead, so they are parsed again -- as a task, from the source.
  void _takeSuggestion(String projectId, String name) {
    setState(() {
      _destination = ProjectDestination(projectId: projectId, name: name);
      _result = null;
      _showSource = false;
    });
    _tidy();
  }

  /// What a field gets back when the answer is what is saved.
  String _fieldText() {
    final String text = switch (_result) {
      TidiedTask() || ParsedDictation() => <String>[
        _title.text.trim(),
        _description.text.trim(),
      ].where((part) => part.isNotEmpty).join('\n'),
      TidiedNote() || TidiedLine() => _resultText.text.trim(),
      null => '',
    };
    return text.isEmpty ? _text.text.trim() : text;
  }

  /// Creates the task in a project whose screen is usually *not* open.
  ///
  /// `ProjectTasks` is an auto-disposing provider whose writes are no-ops
  /// until its list has loaded -- the optimistic row has nothing to be appended
  /// to. Read cold from here, it was still loading when `create` ran, so the
  /// task was silently dropped while the snackbar said "Задача добавлена". The
  /// subscription keeps the provider alive for the length of the write, and
  /// the `future` is the load it has to wait for.
  Future<void> _createTask(
    String projectId,
    String title, {
    String? description,
    String? remindAt,
    String? dictationParseId,
  }) async {
    final provider = projectTasksProvider(projectId);
    final keepAlive = ref.listenManual(provider, (_, _) {});
    try {
      await ref.read(provider.future);
      await ref
          .read(provider.notifier)
          .create(
            title,
            description: description,
            remindAt: remindAt,
            dictationParseId: dictationParseId,
          );
    } finally {
      keepAlive.close();
    }
  }

  /// `2026-09-25` as `25.09`.
  static String _shortDate(String date) {
    final parts = date.split('-');
    return parts.length == 3 ? '${parts[2]}.${parts[1]}' : date;
  }

  Future<void> _leave(String? result) async {
    if (!mounted || _leaving) return;
    _leaving = true;
    // Whatever is still open is thrown away: the words are already either saved
    // or deliberately abandoned.
    await ref.read(voiceDictationProvider.notifier).cancel();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _abandon() async {
    _text.clear();
    await _leave(null);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceDictationProvider);
    final recording = state is DictationRecording;
    // Read here, above the Scaffold, which strips the inset from its body.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The status bar belongs to whatever is under it, and under it is the
      // only dark screen in the app. Every other screen is `#F3F3F7`, so the
      // system default of dark icons is right for eight screens out of nine and
      // wrong for this one: on a device the clock and the battery came out dark
      // navy on `#14183C` and could not be read.
      //
      // `light` names the *icons*, not the background, which is the opposite of
      // how it reads. `systemNavigationBar*` is set too because the dictation
      // screen is the one place a gesture bar sits on the dark surface.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.voiceBackground,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Theme(
        // The one dark surface in the app, and it is dark by construction rather
        // than by a system setting -- see `theme/app_theme.dart`. Wrapping rather
        // than styling each widget keeps the text selection handles, the cursor
        // and the text field's own decoration on the same palette.
        data: voiceTheme,
        child: Scaffold(
          backgroundColor: AppColors.voiceBackground,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _header(),
                _stage(state),
                // The space is held rather than collapsed when the recording
                // stops: the text below must not jump up the screen while the
                // user is reading it. The answer is a different view, with
                // nothing to jump. With the keyboard up it is collapsed
                // after all -- the user is typing into the text by then, and on
                // a phone those 90 px were most of what the keyboard left of
                // it (the words shrank to two lines and scrolled out of sight).
                if (recording || (!keyboard && _result == null))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: recording
                        ? const VoiceLevelMeter()
                        : const SizedBox(height: 72),
                  ),
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: TidySegment(
                      showSource: _showSource,
                      onChanged: (value) => setState(() => _showSource = value),
                    ),
                  ),
                Expanded(
                  child: _result != null && !_showSource
                      ? _resultView()
                      : _textArea(state, compact: keyboard),
                ),
                _buttons(state, compact: keyboard),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 16, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Закрыть без записи',
            onPressed: _abandon,
            icon: const Icon(Icons.close, size: 22),
            color: AppColors.voiceMuted,
          ),
          const Spacer(),
          _DestinationChip(
            destination: _destination,
            onChanged: _destination is FieldDestination
                ? null
                : (value) => setState(() {
                    final kind = _kind;
                    _destination = value;
                    // An answer has the shape of where it was going: a task's
                    // for a project, a line's for the sandbox. Somewhere else
                    // it would be the wrong shape, so it goes, and the words
                    // are parsed again only if asked.
                    if (_kind != kind) {
                      _job?.cancel();
                      _job = null;
                      _tidying = false;
                      _progress = null;
                      _result = null;
                      _showSource = false;
                      _tidyProblem = null;
                    }
                  }),
          ),
        ],
      ),
    );
  }

  /// "Слушаю 0:12" and its three other faces.
  Widget _stage(DictationState state) {
    if (!_tidying && _result == null && state is DictationRecognising) {
      return _RecognitionCard(state);
    }

    final (Widget leading, String label, String? clock) = _tidying
        ? (const _Spinner(), 'Разбираю', null)
        : _result != null
        ? (
            const Icon(
              Icons.auto_awesome_outlined,
              size: 20,
              color: AppColors.voiceBright,
            ),
            'Разобрано — можно править',
            null,
          )
        : switch (state) {
            DictationStarting() => (const _Spinner(), 'Включаю микрофон', null),
            DictationRecording(:final elapsed) => (
              const RecordingDot(),
              'Слушаю',
              formatDictationClock(elapsed),
            ),
            DictationRecognising(:final length) => (
              const _Spinner(),
              'Распознаю',
              formatDictationClock(length),
            ),
            DictationFailed() => (
              const Icon(
                Icons.mic_off_outlined,
                size: 20,
                color: AppColors.voiceRecordingSoft,
              ),
              'Не получилось',
              null,
            ),
            DictationIdle() => (
              const Icon(
                Icons.edit_outlined,
                size: 20,
                color: AppColors.voiceMuted,
              ),
              'Можно править',
              null,
            ),
          };

    // The countdown to the ceiling. On the stage rather than in the note under
    // the words because this is where the eyes already are -- the clock -- and
    // in the recording colour, because it is the one thing on the screen that
    // is about to happen by itself.
    final countdown =
        !_tidying &&
            _result == null &&
            state is DictationRecording &&
            state.nearCeiling
        ? 'осталось ${formatDictationClock(state.left)}'
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        children: <Widget>[
          SizedBox(width: 20, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppText.voiceStage)),
          // In the row, not under it: a line appearing below would push the
          // meter and the words down the screen half a minute before the end.
          if (countdown != null)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.voiceRecordingSoft),
                borderRadius: BorderRadius.circular(Radii.row),
              ),
              child: Text(
                countdown,
                style: AppText.voiceNote.copyWith(
                  color: AppColors.voiceRecordingSoft,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          if (clock != null) Text(clock, style: AppText.voiceClock),
        ],
      ),
    );
  }

  Widget _textArea(DictationState state, {required bool compact}) {
    final note = switch (state) {
      DictationRecording(modelLoading: true) =>
        'модель ещё грузится — на запись это не влияет',
      DictationRecording(nearCeiling: true) =>
        'потом запись остановится сама — всё сказанное распознается',
      DictationRecording() => 'сохранится и без сети',
      DictationFailed(:final message) => message,
      // The reference page prints this one under the *recognised* text, not
      // under the meter -- which is the moment it actually answers a question:
      // the phrase is on screen, the phone is in a lift, and the thing you want
      // to know before pressing «Готово» is whether pressing it can lose the
      // sentence. Shown while recording as well, since the same doubt is what
      // stops someone dictating at all.
      DictationIdle() when _result != null => tidySourceHint,
      DictationIdle() => _tidyProblem ?? 'сохранится и без сети',
      _ => null,
    };
    // Everywhere the words can go (F15). Once there is an answer, running it
    // again is "Разобрать заново" under it.
    final canTidy = state is DictationIdle && _result == null;

    // While the later pieces are still being recognised the words so far take
    // the place of the field -- see [_partial]. No note, no tap: there is
    // nothing to stop and nothing to edit yet.
    if (state is DictationRecognising && state.partialText.isNotEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, compact ? 12 : 20, 20, 0),
        child: _partial(state.partialText),
      );
    }

    return GestureDetector(
      // The spec's second way to finish. `opaque` so the whole half-screen is
      // the target, including the blank part under the text.
      behavior: HitTestBehavior.opaque,
      onTap: state is DictationRecording
          ? () => unawaited(_stopForEditing())
          : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, compact ? 12 : 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              // Deaf to pointers while the microphone is open, so the tap lands
              // on the `GestureDetector` above rather than on the field's own
              // recogniser. `readOnly` alone is not enough -- a read-only
              // `TextField` still claims the gesture in order to place a
              // selection, and the tap that was meant to say "хватит" would do
              // nothing at all.
              child: IgnorePointer(
                ignoring: state is DictationRecording,
                child: TextField(
                  controller: _text,
                  focusNode: _textFocus,
                  // Never focused while the microphone is open: a keyboard
                  // covering two thirds of the screen during a recording hides
                  // the level meter, the clock and "Готово" all at once.
                  readOnly:
                      state is DictationRecording || state is DictationStarting,
                  showCursor: state is! DictationRecording,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppText.dictated,
                  cursorColor: AppColors.voiceBright,
                  decoration: InputDecoration(
                    filled: false,
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: state is DictationRecording ? 'Говорите…' : null,
                    hintStyle: AppText.dictated.copyWith(
                      color: AppColors.voiceLine,
                    ),
                  ),
                ),
              ),
            ),
            if (_progress case final progress?)
              Padding(
                padding: EdgeInsets.only(top: compact ? 6 : 14, bottom: 4),
                child: TidyProgressCard(
                  progress: progress,
                  onCancel: _cancelTidy,
                  onRetry: _tidy,
                ),
              )
            else if (note != null || canTidy)
              Padding(
                padding: EdgeInsets.only(top: compact ? 6 : 14, bottom: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: note == null
                          ? const SizedBox.shrink()
                          : Text(note, style: AppText.voiceNote),
                    ),
                    if (canTidy)
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _text,
                        builder: (context, value, _) => TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.voiceBright,
                            disabledForegroundColor: AppColors.voiceLine,
                            minimumSize: const Size(0, Targets.minimum),
                          ),
                          onPressed: value.text.trim().isEmpty ? null : _tidy,
                          icon: const Icon(
                            Icons.auto_awesome_outlined,
                            size: 18,
                          ),
                          label: const Text('Разобрать'),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// What the finished pieces said, while the rest are still being recognised.
  ///
  /// Not the text field: nothing has been delivered to it yet -- the sink
  /// hears the whole text once, at the end -- and an editable field whose
  /// contents are being replaced from underneath would lose whatever the user
  /// typed into it. Anchored to the bottom, so the newest words stay in view
  /// as the text grows past the screen.
  Widget _partial(String partial) {
    final before = _text.text.trimRight();
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        reverse: true,
        // At least the height of the area, with the text at its top: a
        // reversed scroll view on its own would sit a short text at the
        // bottom, far from where the field it stands in for starts.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text.rich(
              TextSpan(
                style: AppText.dictated,
                children: <InlineSpan>[
                  TextSpan(text: before.isEmpty ? partial : '$before $partial'),
                  const TextSpan(
                    text: ' …',
                    style: TextStyle(color: AppColors.voiceMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The model's answer, editable: what "Готово" will save.
  ///
  /// A list rather than a column, so a focused field is scrolled into what the
  /// keyboard leaves of the screen instead of being covered by it.
  Widget _resultView() {
    final heading = AppText.dictated.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w600,
    );
    final body = AppText.dictated.copyWith(fontSize: 17);
    final remindDate = _remindDate;
    final result = _result;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      children: <Widget>[
        if (result is ParsedDictation || result is TidiedTask) ...<Widget>[
          const TidyLabel('НАЗВАНИЕ'),
          TidyTextField(
            controller: _title,
            style: heading,
            hint: 'Что сделать',
          ),
          const SizedBox(height: 20),
          const TidyLabel('ОПИСАНИЕ'),
          TidyTextField(
            controller: _description,
            style: body,
            hint: 'Нет описания',
          ),
        ] else ...<Widget>[
          TidyLabel(result is TidiedLine ? 'СТРОКА' : 'ТЕКСТ'),
          TidyTextField(
            controller: _resultText,
            style: body,
            hint: 'Текста нет',
          ),
        ],
        if (remindDate != null && result is ParsedDictation) ...<Widget>[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.voiceLine),
              borderRadius: BorderRadius.circular(Radii.row),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.alarm, size: 18, color: AppColors.voiceBright),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    // Said plainly, because it changes the task: a reminder
                    // only fires for a blocked one.
                    'Напомнить ${_shortDate(remindDate)} · задача будет ждать',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: AppColors.voiceInk,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Без напоминания',
                  onPressed: () => setState(() => _remindDate = null),
                  icon: const Icon(Icons.close, size: 18),
                  color: AppColors.voiceMuted,
                ),
              ],
            ),
          ),
        ],
        // The sandbox answer's project: one tap sends the words there as a
        // task instead. Only for the sandbox itself -- a field behind this
        // screen is waiting for text, not for a project.
        if (result case TidiedLine(
          :final projectId?,
          :final projectName?,
        ) when _destination is SandboxDestination) ...<Widget>[
          const SizedBox(height: 20),
          const TidyLabel('ПОХОЖЕ НА ПРОЕКТ'),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.voiceBright,
                side: const BorderSide(color: AppColors.voiceLine),
                minimumSize: const Size(0, Targets.minimum),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.row),
                ),
              ),
              onPressed: () => _takeSuggestion(projectId, projectName),
              icon: const Icon(Icons.folder_outlined, size: 18),
              label: Text('Задачей в «$projectName»'),
            ),
          ),
        ],
      ],
    );
  }

  /// [compact] is the keyboard being up: "Отменить" goes (the cross in the
  /// header does the same), so what the keyboard leaves goes to the words.
  Widget _buttons(DictationState state, {required bool compact}) {
    final failed = state is DictationFailed;
    final busy =
        _tidying || state is DictationRecognising || state is DictationStarting;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, compact ? 12 : 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        // "Отменить" is the full width of the screen, like "Готово" above it.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_result != null) ...<Widget>[
            TidyActions(
              onAsIs: _untidy,
              onRerun: _tidying || busy ? null : _rerun,
            ),
            const SizedBox(height: 10),
          ],
          if (failed && state.retryable)
            _VoiceButton(
              label: 'Ещё раз',
              icon: Icons.refresh,
              onPressed: () =>
                  unawaited(ref.read(voiceDictationProvider.notifier).retry()),
            )
          else
            _VoiceButton(
              label: 'Готово',
              icon: Icons.check,
              onPressed: busy ? null : () => unawaited(_done()),
            ),
          if (!compact) ...<Widget>[
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: AppColors.voiceBright,
                  side: const BorderSide(color: AppColors.voiceLine),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.stub),
                  ),
                ),
                onPressed: () => unawaited(_abandon()),
                child: const Text('Отменить'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Готово": 76 px tall, white on the dark screen, the full width of it.
///
/// The biggest target in the app, deliberately. It is pressed while not looking
/// at the screen, it is the last step of a gesture whose whole point is not
/// having to look, and pressing the wrong thing here loses a sentence that only
/// existed as sound.
class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Targets.finishDictation,
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.voiceBackground,
          disabledBackgroundColor: AppColors.voiceLine,
          disabledForegroundColor: AppColors.voiceMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.large),
          ),
          textStyle: AppText.action.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 19,
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(label),
      ),
    );
  }
}

/// The chip that says where the words are going, and changes it.
class _DestinationChip extends ConsumerWidget {
  const _DestinationChip({required this.destination, required this.onChanged});

  final DictationDestination destination;

  /// Null makes the chip a label rather than a control -- see
  /// [FieldDestination].
  final void Function(DictationDestination value)? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final change = onChanged;

    final body = Container(
      height: 40,
      padding: EdgeInsets.fromLTRB(14, 0, change == null ? 14 : 10, 0),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.voiceLine),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            destination is SandboxDestination
                ? Icons.inbox_outlined
                : Icons.folder_outlined,
            size: 16,
            color: AppColors.voiceBright,
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            // A project can be called anything; the chip shares its row with a
            // close button and must not push it off the screen.
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.voiceBright,
              ),
            ),
          ),
          if (change != null) ...<Widget>[
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: AppColors.voiceBright,
            ),
          ],
        ],
      ),
    );

    if (change == null) return body;

    final view = ref.watch(boardViewProvider);
    final projects = view is BoardReady
        ? view.projects
        : const <BoardProject>[];

    return PopupMenuButton<DictationDestination>(
      tooltip: 'Куда уедет текст',
      position: PopupMenuPosition.under,
      onSelected: change,
      itemBuilder: (_) => <PopupMenuEntry<DictationDestination>>[
        const PopupMenuItem<DictationDestination>(
          value: SandboxDestination(),
          child: Text('Песочница'),
        ),
        if (projects.isNotEmpty) const PopupMenuDivider(),
        for (final entry in projects)
          PopupMenuItem<DictationDestination>(
            value: ProjectDestination(
              projectId: entry.project.id,
              name: entry.project.name,
            ),
            child: Text(entry.project.name),
          ),
      ],
      child: body,
    );
  }
}

/// "Распознаю · 3 из 8", a bar that fills, and a guess at the rest.
///
/// The top card of the reference page. A card rather than the stage row with
/// a number added, because for a long recording this *is* the screen for the
/// better part of a minute, and the bar needs the width.
class _RecognitionCard extends StatelessWidget {
  const _RecognitionCard(this.state);

  final DictationRecognising state;

  @override
  Widget build(BuildContext context) {
    // One piece is a short phrase: "1 из 1" would be a count of nothing, and
    // the bar would jump from empty to gone. It keeps the old face -- the
    // word, and a bar that only says "working".
    final counted = state.total > 1;
    final remaining = state.remaining;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.voiceLine),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(
                  child: Text(
                    counted
                        ? 'Распознаю · ${state.done} из ${state.total}'
                        : 'Распознаю',
                    style: AppText.voiceStage,
                  ),
                ),
                Text(
                  formatDictationClock(state.length),
                  style: AppText.voiceClock.copyWith(
                    fontSize: 14,
                    color: AppColors.voiceMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                // Null is indeterminate: the bar moves without claiming a
                // number it does not have -- the model may still be loading.
                value: counted ? state.fraction : null,
                minHeight: 6,
                backgroundColor: AppColors.voiceLine,
                color: AppColors.voiceLevelHigh,
              ),
            ),
            if (counted && remaining != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _roughly(remaining),
                style: AppText.voiceNote.copyWith(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "осталось около 20 с", "осталось около 2 мин". A guess, rounded like
  /// one: to five seconds under a minute, so the number does not flicker by
  /// one every piece.
  static String _roughly(Duration d) {
    final seconds = d.inSeconds;
    if (seconds < 5) return 'почти готово';
    if (seconds < 60) return 'осталось около ${(seconds / 5).round() * 5} с';
    return 'осталось около ${(seconds / 60).round()} мин';
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: AppColors.voiceBright,
      ),
    );
  }
}
