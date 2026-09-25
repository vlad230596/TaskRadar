import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/dictation_api.dart';
import '../models/board_project.dart';
import '../providers/board_providers.dart';
import '../providers/capture_queue_providers.dart';
import '../providers/dependencies.dart';
import '../providers/project_providers.dart';
import '../providers/reminder_providers.dart';
import '../providers/voice_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/dictation.dart';
import '../widgets/mutation_feedback.dart';

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
  const FieldDestination(this.label);

  @override
  final String label;
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

  /// True while the server's model is turning the words into a task (F14).
  /// Shown as its own stage, and keeps "Готово" from saving twice.
  bool _tidying = false;

  /// The model's proposal, once "Разобрать" has been pressed and answered.
  /// Non-null means the screen shows the proposal -- title, description,
  /// reminder -- instead of the words, and that is what "Готово" saves.
  ParsedDictation? _parsed;

  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  /// The proposed reminder, `YYYY-MM-DD`. Separate from [_parsed] because the
  /// user can take it off without throwing the rest of the proposal away.
  String? _remindDate;

  /// Why the last "Разобрать" did not work, said under the words. Null once
  /// anything else happens.
  String? _tidyProblem;

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
    _text.dispose();
    _textFocus.dispose();
    _title.dispose();
    _description.dispose();
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
        await _leave(text);

      case SandboxDestination():
        // Through the capture queue like everything else the sandbox accepts,
        // so dictating with no signal writes the line to disk and sends it when
        // there is a network (F8.1).
        final ok = await runMutation(
          context,
          () => ref.read(captureQueueProvider.notifier).capture(text),
          failure: 'Не удалось записать строчку на устройство.',
        );
        if (ok) await _leave(null);

      case ProjectDestination(:final projectId, :final name):
        // What is on screen is what is saved: the proposal if "Разобрать" was
        // pressed and answered, the words as they stand otherwise. Never a
        // silent round trip to the model on the way out -- the user should
        // not find a title in the project they did not see here.
        final parsed = _parsed != null;
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
          ),
          success: remindDate == null
              ? 'Задача добавлена в «$name».'
              : 'Задача добавлена в «$name», напомню ${_shortDate(remindDate)}.',
          failure: 'Не удалось добавить задачу.',
        );
        if (ok) await _leave(null);
    }
  }

  /// "Разобрать": the words as a task -- a verb-first title, the rest as the
  /// description, "напомни в пятницу" as a date -- shown on this screen for
  /// correction before anything is saved (F14).
  ///
  /// ## Why a button and not a step inside "Готово"
  ///
  /// It was a step inside "Готово" first, and it was opaque: the words on the
  /// screen were one thing, the task that landed in the project another, and
  /// whether the model had been reached at all was invisible. Now nothing
  /// happens to the words unless asked, the answer is on screen before it is
  /// saved, and a failure is said out loud instead of being swallowed.
  ///
  /// Only for a task going into a project. The sandbox keeps the raw words:
  /// a line there has no description to put the rest into, and it gets its
  /// title when it is filed.
  Future<void> _tidy() async {
    final text = _text.text.trim();
    if (text.isEmpty || _tidying) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _tidying = true;
      _tidyProblem = null;
    });

    String? problem;
    try {
      final zone = await ref.read(deviceTimeZoneNameProvider.future);
      final parsed = await ref
          .read(dictationApiProvider)
          .parse(text: text, timeZone: zone);
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _title.text = parsed.title;
        _description.text = parsed.description ?? '';
        _remindDate = parsed.remindDate;
      });
    } on NetworkException {
      problem = 'Нет связи с сервером — можно сохранить как есть.';
    } on ApiException catch (error) {
      problem = error.statusCode == 503
          ? 'Разбор не настроен на сервере.'
          : 'Модель не ответила — попробуйте ещё раз.';
    } catch (error) {
      debugPrint('Dictation parse failed: $error');
      problem = 'Не получилось разобрать.';
    } finally {
      if (mounted) {
        setState(() {
          _tidying = false;
          _tidyProblem = problem;
        });
      }
    }
  }

  /// Back to the words as recognised, proposal thrown away.
  void _untidy() {
    setState(() {
      _parsed = null;
      _remindDate = null;
    });
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
  }) async {
    final provider = projectTasksProvider(projectId);
    final keepAlive = ref.listenManual(provider, (_, _) {});
    try {
      await ref.read(provider.future);
      await ref
          .read(provider.notifier)
          .create(title, description: description, remindAt: remindAt);
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
        data: _voiceTheme,
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
                // user is reading it. The proposal is a different view, with
                // nothing to jump. With the keyboard up it is collapsed
                // after all -- the user is typing into the text by then, and on
                // a phone those 90 px were most of what the keyboard left of
                // it (the words shrank to two lines and scrolled out of sight).
                if (recording || (!keyboard && _parsed == null))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: recording
                        ? const VoiceLevelMeter()
                        : const SizedBox(height: 72),
                  ),
                Expanded(
                  child: _parsed != null
                      ? _proposal()
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
                    _destination = value;
                    // A proposal is a task's shape; anywhere else the words go
                    // as they are, and keeping it on screen would say otherwise.
                    if (value is! ProjectDestination) {
                      _parsed = null;
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
    final (Widget leading, String label, String? clock) = _tidying
        ? (const _Spinner(), 'Разбираю', null)
        : _parsed != null
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        children: <Widget>[
          SizedBox(width: 20, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppText.voiceStage)),
          if (clock != null) Text(clock, style: AppText.voiceClock),
        ],
      ),
    );
  }

  Widget _textArea(DictationState state, {required bool compact}) {
    final note = switch (state) {
      DictationRecording(modelLoading: true) =>
        'модель ещё грузится — на запись это не влияет',
      DictationRecording() => 'сохранится и без сети',
      DictationFailed(:final message) => message,
      // The reference page prints this one under the *recognised* text, not
      // under the meter -- which is the moment it actually answers a question:
      // the phrase is on screen, the phone is in a lift, and the thing you want
      // to know before pressing «Готово» is whether pressing it can lose the
      // sentence. Shown while recording as well, since the same doubt is what
      // stops someone dictating at all.
      DictationIdle() => _tidyProblem ?? 'сохранится и без сети',
      _ => null,
    };
    final canTidy =
        state is DictationIdle && _destination is ProjectDestination;

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
            if (note != null || canTidy)
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
                          onPressed: value.text.trim().isEmpty
                              ? null
                              : () => unawaited(_tidy()),
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

  /// The model's proposal, editable: what "Готово" will save.
  ///
  /// A list rather than a column, so a focused field is scrolled into what the
  /// keyboard leaves of the screen instead of being covered by it.
  Widget _proposal() {
    const label = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 13,
      letterSpacing: 0.4,
      color: AppColors.voiceMuted,
    );
    final remindDate = _remindDate;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      children: <Widget>[
        const Text('НАЗВАНИЕ', style: label),
        const SizedBox(height: 6),
        _proposalField(
          _title,
          style: AppText.dictated.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          hint: 'Что сделать',
        ),
        const SizedBox(height: 20),
        const Text('ОПИСАНИЕ', style: label),
        const SizedBox(height: 6),
        _proposalField(
          _description,
          style: AppText.dictated.copyWith(fontSize: 17),
          hint: 'Нет описания',
        ),
        if (remindDate != null) ...<Widget>[
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
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.voiceMuted,
              padding: EdgeInsets.zero,
            ),
            onPressed: _untidy,
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Как надиктовано'),
          ),
        ),
      ],
    );
  }

  Widget _proposalField(
    TextEditingController controller, {
    required TextStyle style,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      maxLines: null,
      textCapitalization: TextCapitalization.sentences,
      style: style,
      cursorColor: AppColors.voiceBright,
      decoration: InputDecoration(
        filled: false,
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        // Flush with the labels above: the theme's inset is for a boxed
        // field, and these have no box.
        contentPadding: EdgeInsets.zero,
        hintText: hint,
        hintStyle: style.copyWith(color: AppColors.voiceLine),
      ),
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

/// The dark palette, as a theme, so Material's own bits (the popup menu, the
/// text selection handles, the snackbar) land on it too.
final ThemeData _voiceTheme = buildAppTheme().copyWith(
  scaffoldBackgroundColor: AppColors.voiceBackground,
  canvasColor: AppColors.voiceBackground,
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: AppColors.voiceBright,
    selectionColor: AppColors.indigo,
    selectionHandleColor: AppColors.voiceBright,
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: AppColors.railActive,
    surfaceTintColor: Colors.transparent,
    textStyle: const TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 15,
      color: AppColors.voiceInk,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.row),
      side: const BorderSide(color: AppColors.voiceLine),
    ),
  ),
  dividerTheme: const DividerThemeData(
    color: AppColors.voiceLine,
    thickness: 1,
    space: 1,
  ),
);
