import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/dictation_api.dart';
import '../providers/dependencies.dart';
import '../providers/reminder_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'tidy_progress.dart';

/// "Разобрать" / "Причесать" (F14, F15): the server's model tidying text,
/// wherever text is written -- the dictation screen, a task, a note, a
/// sandbox line.
///
/// ## The rules this file is built around
///
/// - **The model always works from the source.** The source is the text as it
///   was -- dictated, typed, or corrected by hand in the "Исходник" view --
///   never an earlier answer. "Разобрать заново" sends the source again; a
///   tidied text tidied again drifts a little further from what was said each
///   time, and there would be no way back.
/// - **The source lives on the screen, and only there.** It is what the user
///   can compare the answer with and go back to ("Как надиктовано"); once the
///   result is saved nothing remembers it, and the server keeps no copy
///   beyond its dataset row.
/// - **Nothing is saved behind the user's back.** The answer is shown, editable,
///   and becomes the text only on "Готово".
///
/// The pieces are shared: the dictation screen puts them into its own layout
/// (it has a recording and a destination to show as well), and every other
/// place opens [AiTidyScreen], which is the same pieces on a screen of their
/// own.

/// What the "Исходник" view says under the source.
const String tidySourceHint =
    'это можно поправить руками и запустить разбор заново — AI всегда '
    'работает от исходника';

/// Why a parse did not give an answer, as said on the screen.
class TidyFailure {
  const TidyFailure(this.message, {this.unavailable = false});

  final String message;

  /// The server has no model at all: there is nothing to repeat, so the step
  /// card goes and the message is said on its own.
  final bool unavailable;
}

/// One parse under way: its stages for the step card, and a way to stop it.
///
/// A plain object, not a provider: it belongs to the one screen that started
/// it, and ends with that screen.
class TidyJob {
  TidyJob._(this.progress);

  /// Starts a parse of [text] as [kind]. [onProgress] is called after every
  /// stage (the caller repaints), and exactly one of [onDone] and [onFailed]
  /// at the end -- unless [cancel] came first, after which nothing is called.
  factory TidyJob.start(
    WidgetRef ref, {
    required ParseKind kind,
    required String text,
    String? noteTitle,
    required VoidCallback onProgress,
    required void Function(TidyResult result) onDone,
    required void Function(TidyFailure failure) onFailed,
  }) {
    final job = TidyJob._(TidyProgress(DateTime.now()));
    unawaited(
      job._run(
        ref,
        kind: kind,
        text: text,
        noteTitle: noteTitle,
        onProgress: onProgress,
        onDone: onDone,
        onFailed: onFailed,
      ),
    );
    return job;
  }

  /// What the step card draws.
  final TidyProgress progress;

  bool _cancelled = false;
  StreamSubscription<ParseProgress>? _subscription;

  bool get cancelled => _cancelled;

  /// Drops the parse -- the connection with it, so the server stops asking the
  /// model.
  void cancel() {
    _cancelled = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  Future<void> _run(
    WidgetRef ref, {
    required ParseKind kind,
    required String text,
    required String? noteTitle,
    required VoidCallback onProgress,
    required void Function(TidyResult result) onDone,
    required void Function(TidyFailure failure) onFailed,
  }) async {
    void fail(String message) {
      progress.fail(message, DateTime.now());
      onFailed(TidyFailure(message));
    }

    final String zone;
    try {
      zone = await ref.read(deviceTimeZoneNameProvider.future);
    } catch (error) {
      debugPrint('Tidy failed: $error');
      if (!_cancelled) fail('Не получилось разобрать.');
      return;
    }
    if (_cancelled) return;

    _subscription = ref
        .read(dictationApiProvider)
        .parseStream(
          text: text,
          timeZone: zone,
          kind: kind,
          noteTitle: noteTitle,
        )
        .listen(
          (event) {
            if (_cancelled) return;
            if (event is ParseDone) {
              onDone(event.result);
              return;
            }
            progress.record(event, DateTime.now());
            onProgress();
          },
          onError: (Object error) {
            if (_cancelled) return;
            if (error is ApiException && error.statusCode == 503) {
              onFailed(
                const TidyFailure(
                  'Разбор не настроен на сервере.',
                  unavailable: true,
                ),
              );
              return;
            }
            fail(tidyFailureMessage(error));
          },
        );
  }
}

/// What the step card says when the parse failed with [error].
String tidyFailureMessage(Object error) {
  switch (error) {
    case ParseSilenceException():
      return 'Сервер замолчал — можно повторить или сохранить как есть.';
    case NetworkException():
      return 'Нет связи с сервером — можно сохранить как есть.';
    case ApiException(statusCode: 429):
      return 'Дневной лимит AI-запросов исчерпан — до 00:00 UTC можно '
          'сохранить как есть.';
    case ApiException() when ModelFailure.of(error) != null:
      return modelFailureMessage(ModelFailure.of(error)!);
    case ApiException():
      return 'Модель не ответила — попробуйте ещё раз.';
    default:
      debugPrint('Tidy failed: $error');
      return 'Не получилось разобрать.';
  }
}

/// What the user can do about [failure], in their words. The provider's own
/// message never gets here (`ModelFailure`); its class is enough to tell "pick
/// another model" from "try again in a minute".
String modelFailureMessage(ModelFailure failure) {
  final model = failure.model == null ? 'Модель' : 'Модель «${failure.model}»';
  return switch (failure.cause) {
    'model_not_found' =>
      '$model недоступна у провайдера — выберите другую в Настройках.',
    'unauthorized' =>
      'Провайдер модели не принял ключ API — его нужно '
          'проверить на сервере.',
    'no_credits' => 'У провайдера модели закончились средства на счёте.',
    'rate_limited' =>
      'Провайдер модели ограничил частоту запросов — '
          'повторите через минуту.',
    'provider_down' =>
      'Провайдер модели сейчас не работает — попробуйте '
          'позже или сохраните как есть.',
    'timeout' => 'Модель не успела ответить — попробуйте ещё раз.',
    'unreachable' =>
      'Сервер не достучался до провайдера модели — '
          'попробуйте позже.',
    'bad_reply' => 'Модель ответила не по формату — попробуйте ещё раз.',
    'rejected' =>
      'Провайдер модели отклонил запрос — попробуйте другую '
          'модель в Настройках.',
    _ => 'Модель не ответила — попробуйте ещё раз.',
  };
}

/// "Результат AI | Исходник": which of the two the screen shows.
class TidySegment extends StatelessWidget {
  const TidySegment({
    required this.showSource,
    required this.onChanged,
    super.key,
  });

  final bool showSource;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget half(String label, {required bool source}) {
      final selected = showSource == source;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: Material(
            color: selected ? AppColors.voiceLine : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: selected ? null : () => onChanged(source),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: selected ? AppColors.card : AppColors.voiceMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.voiceWell,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          half('Результат AI', source: false),
          const SizedBox(width: 3),
          half('Исходник', source: true),
        ],
      ),
    );
  }
}

/// "НАЗВАНИЕ", "ОПИСАНИЕ": the label over a field of the answer.
class TidyLabel extends StatelessWidget {
  const TidyLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.4,
          color: AppColors.voiceMuted,
        ),
      ),
    );
  }
}

/// A field of the answer, or the source: no box, editable, as tall as its text.
class TidyTextField extends StatefulWidget {
  const TidyTextField({
    required this.controller,
    required this.style,
    required this.hint,
    this.fieldKey,
    this.revealWhole = false,
    super.key,
  });

  final TextEditingController controller;
  final TextStyle style;
  final String hint;
  final Key? fieldKey;

  /// Keep the whole field in view while it is edited, not just the caret's
  /// line -- when it fits in what the keyboard leaves of the list.
  ///
  /// For the title, which is read whole. The text field alone scrolls only as
  /// far as the caret: a title tapped in its second line, with the keyboard
  /// coming up, showed its second line and lost the first under the segment.
  /// A field taller than the window (a long description) is left to the
  /// caret, as before -- revealing all of it is not possible.
  final bool revealWhole;

  @override
  State<TidyTextField> createState() => _TidyTextFieldState();
}

class _TidyTextFieldState extends State<TidyTextField>
    with WidgetsBindingObserver {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_scheduleReveal);
    WidgetsBinding.instance.addObserver(this);
  }

  // The keyboard coming up (or changing height) shrinks the list after the
  // focus has already moved, so the reveal is redone then. Not through
  // `MediaQuery.viewInsetsOf`: the Scaffold strips the inset from its body, so
  // in here it never changes.
  @override
  void didChangeMetrics() => _scheduleReveal();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  void _scheduleReveal() {
    if (!widget.revealWhole || !_focus.hasFocus) return;
    // Two frames on. The first lets the list lay out at its new height; the
    // text field's own caret reveal runs in that same post-frame phase, after
    // this widget's (its observer registered later), and its scroll would
    // replace this one. Starting a frame later puts the whole field last.
    void reveal(Duration _) {
      if (!mounted || !_focus.hasFocus) return;
      final box = context.findRenderObject() as RenderBox?;
      final scrollable = Scrollable.maybeOf(context);
      if (box == null || scrollable == null) return;
      if (box.size.height > scrollable.position.viewportDimension) return;
      box.showOnScreen(
        duration: const Duration(milliseconds: 100),
        curve: Curves.fastOutSlowIn,
      );
    }

    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      binding.addPostFrameCallback(reveal);
      binding.scheduleFrame();
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: _focus,
      maxLines: null,
      keyboardType: TextInputType.multiline,
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
        hintText: widget.hint,
        hintStyle: style.copyWith(color: AppColors.voiceLine),
      ),
    );
  }
}

/// "Как надиктовано" and "Разобрать заново", side by side under the answer.
class TidyActions extends StatelessWidget {
  const TidyActions({required this.onAsIs, required this.onRerun, super.key});

  /// The source, as it is -- the answer thrown away.
  final VoidCallback onAsIs;

  /// The model again, from the source. Null while a parse is running.
  final VoidCallback? onRerun;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, IconData icon, VoidCallback? onPressed) {
      return Expanded(
        child: SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: AppColors.voiceInk,
              disabledForegroundColor: AppColors.voiceLine,
              side: const BorderSide(color: AppColors.voiceLine),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        button('Как надиктовано', Icons.undo, onAsIs),
        const SizedBox(width: 8),
        button('Разобрать заново', Icons.refresh, onRerun),
      ],
    );
  }
}

/// The amber line over an answer that says something the words did not: "AI
/// добавил «3.00», которого не было в тексте — проверь" (F15).
///
/// ## Why a note and not a refusal
///
/// The server used to throw such an answer away, and the check behind it
/// cannot tell an invented deadline from a time the user said in words --
/// "три ноль" is "3.00" either way. Thrown away, the answer took everything
/// else the model fixed with it. Now the answer is shown and this says what to
/// look at; the user, who knows what was said, takes it or goes to "Исходник".
/// The token is marked, because "проверь" is only useful with the thing to
/// check in sight.
class TidyWarningNote extends StatelessWidget {
  const TidyWarningNote(this.warnings, {super.key});

  final List<TidyWarning> warnings;

  @override
  Widget build(BuildContext context) {
    final tokens = <String>[
      for (final warning in warnings)
        if (warning.kind == TidyWarning.inventedDate) warning.token,
    ];
    if (tokens.isEmpty) return const SizedBox.shrink();

    const amber = AppColors.waitingDotOnInk;
    const text = TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 14,
      height: 1.35,
      color: AppColors.voiceInk,
    );
    final mark = text.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.voiceBackground,
      backgroundColor: amber,
    );

    return Container(
      key: const ValueKey<String>('tidy-warning'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        border: Border.all(color: amber),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: 18, color: amber),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: text,
                children: <InlineSpan>[
                  const TextSpan(text: 'AI добавил '),
                  for (var i = 0; i < tokens.length; i++) ...<InlineSpan>[
                    if (i > 0) const TextSpan(text: ', '),
                    TextSpan(text: '«${tokens[i]}»', style: mark),
                  ],
                  TextSpan(
                    text: tokens.length == 1
                        ? ', которого не было в тексте — проверь'
                        : ', которых не было в тексте — проверь',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What [AiTidyScreen] ended with. Null from [openAiTidy] means closed with
/// nothing decided: the caller leaves its text alone.
sealed class TidyOutcome {
  const TidyOutcome(this.source);

  /// The source as it stood on the screen -- including anything the user
  /// corrected by hand in "Исходник".
  final String source;
}

/// "Готово": [result], with whatever the user corrected in it.
final class TidyAccepted extends TidyOutcome {
  const TidyAccepted(
    super.source,
    this.result, {
    this.projectId,
    this.projectName,
  });

  final TidyResult result;

  /// [ParseKind.sandbox] only: the project the line should be filed into
  /// right away -- the suggestion, or the one picked instead. Null keeps it
  /// in the sandbox.
  final String? projectId;
  final String? projectName;
}

/// "Как надиктовано": the source as it is, the answer thrown away.
final class TidyKeptSource extends TidyOutcome {
  const TidyKeptSource(super.source);
}

/// A project the sandbox answer can be sent to instead of the suggested one.
typedef TidyProject = ({String id, String name});

/// Opens [AiTidyScreen] and answers with what it ended with.
Future<TidyOutcome?> openAiTidy(
  BuildContext context, {
  required ParseKind kind,
  required String source,
  String? noteTitle,
  String? destination,
  List<TidyProject> projects = const <TidyProject>[],
}) {
  return Navigator.of(context).push<TidyOutcome>(
    MaterialPageRoute<TidyOutcome>(
      fullscreenDialog: true,
      builder: (_) => AiTidyScreen(
        kind: kind,
        source: source,
        noteTitle: noteTitle,
        destination: destination,
        projects: projects,
      ),
    ),
  );
}

/// "Причесать" for text that is already somewhere: a task, a note, a sandbox
/// line (F15). Starts the parse the moment it opens -- the button that opened
/// it was the request.
///
/// Dark, like the dictation screen, because it is the same moment -- words
/// being turned into something -- and the same pieces: the step card while the
/// model works, then "Результат AI | Исходник", "Как надиктовано", "Разобрать
/// заново" and "Готово". See the note at the top of this file for the rules.
class AiTidyScreen extends ConsumerStatefulWidget {
  const AiTidyScreen({
    required this.kind,
    required this.source,
    this.noteTitle,
    this.destination,
    this.projects = const <TidyProject>[],
    super.key,
  }) : assert(kind != ParseKind.task, 'a new task is the dictation screen');

  /// [ParseKind.taskTidy], [ParseKind.note] or [ParseKind.sandbox].
  final ParseKind kind;

  /// The text as it stands where "Причесать" was pressed.
  final String source;

  /// [ParseKind.note]: the note's title, when it has one.
  final String? noteTitle;

  /// Where the text is, as the chip at the top says it ("Дом"); null for none.
  final String? destination;

  /// [ParseKind.sandbox]: the projects "Другой проект" offers.
  final List<TidyProject> projects;

  @override
  ConsumerState<AiTidyScreen> createState() => _AiTidyScreenState();
}

class _AiTidyScreenState extends ConsumerState<AiTidyScreen> {
  late final TextEditingController _source = TextEditingController(
    text: widget.source,
  );
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  TidyJob? _job;

  /// The step card: the parse under way, or the one that failed.
  TidyProgress? _progress;

  /// Said instead of the card when there is nothing to repeat.
  String? _problem;

  TidyResult? _result;
  bool _showSource = false;

  bool get _running => _progress != null && !_progress!.failed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _job?.cancel();
    _source.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// The model, from the source -- never from [_result].
  void _run() {
    if (!mounted) return;
    final text = _source.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    _job?.cancel();
    late final TidyJob job;
    job = TidyJob.start(
      ref,
      kind: widget.kind,
      text: text,
      noteTitle: widget.noteTitle,
      onProgress: () {
        if (mounted && _job == job) setState(() {});
      },
      onDone: (result) {
        if (!mounted || _job != job) return;
        setState(() {
          _job = null;
          _progress = null;
          _fill(result);
          _showSource = false;
        });
      },
      onFailed: (failure) {
        if (!mounted || _job != job) return;
        setState(() {
          _job = null;
          if (failure.unavailable) {
            _progress = null;
            _problem = failure.message;
          }
        });
      },
    );
    setState(() {
      _job = job;
      _progress = job.progress;
      _problem = null;
    });
  }

  void _cancel() {
    _job?.cancel();
    setState(() {
      _job = null;
      _progress = null;
    });
  }

  void _fill(TidyResult result) {
    _result = result;
    switch (result) {
      case TidiedTask(:final title, :final description):
        _title.text = title;
        _body.text = description ?? '';
      case TidiedNote(:final title, :final content):
        _title.text = title ?? '';
        _body.text = content;
      case TidiedLine(:final text):
        _body.text = text;
      case ParsedDictation():
        break;
    }
  }

  /// The answer with the user's corrections, or null when a required field
  /// was emptied.
  TidyResult? _edited() {
    final body = _body.text.trim();
    switch (_result) {
      case TidiedTask(:final parseId):
        final title = _title.text.trim();
        if (title.isEmpty) return null;
        return TidiedTask(
          title: title,
          description: body.isEmpty ? null : body,
          parseId: parseId,
        );
      case TidiedNote(:final title, :final parseId):
        if (body.isEmpty) return null;
        final edited = _title.text.trim();
        return TidiedNote(
          title: title == null || edited.isEmpty ? null : edited,
          content: _body.text.trim(),
          parseId: parseId,
        );
      case final TidiedLine line:
        if (body.isEmpty) return null;
        return line.edited(body);
      case ParsedDictation() || null:
        return null;
    }
  }

  void _accept({String? projectId, String? projectName}) {
    final result = _edited();
    if (result == null) return;
    Navigator.of(context).pop(
      TidyAccepted(
        _source.text.trim(),
        result,
        projectId: projectId,
        projectName: projectName,
      ),
    );
  }

  void _asIs() {
    _job?.cancel();
    Navigator.of(context).pop(TidyKeptSource(_source.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final showSource = result == null || _showSource;

    return Theme(
      data: voiceTheme,
      child: Scaffold(
        backgroundColor: AppColors.voiceBackground,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _header(),
              if (result != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: TidySegment(
                    showSource: _showSource,
                    onChanged: (value) => setState(() => _showSource = value),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  children: showSource ? _sourceView() : _resultView(result),
                ),
              ),
              _buttons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final destination = widget.destination;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 16, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 22),
            color: AppColors.voiceMuted,
          ),
          const Icon(
            Icons.auto_awesome_outlined,
            size: 18,
            color: AppColors.voiceBright,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(switch (widget.kind) {
              ParseKind.note => 'Причесать заметку',
              ParseKind.sandbox => 'Причесать строку',
              _ => 'Причесать задачу',
            }, style: AppText.voiceStage),
          ),
          if (destination != null)
            Container(
              constraints: const BoxConstraints(maxWidth: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.voiceBright,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                destination,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppColors.voiceBackground,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _sourceView() {
    final progress = _progress;
    final problem = _problem;
    return <Widget>[
      const TidyLabel('ИСХОДНИК'),
      TidyTextField(
        fieldKey: const ValueKey<String>('tidy-source'),
        controller: _source,
        style: AppText.dictated.copyWith(fontSize: 17),
        hint: 'Текста нет',
      ),
      const SizedBox(height: 8),
      Text(tidySourceHint, style: AppText.voiceNote.copyWith(fontSize: 12)),
      if (progress != null) ...<Widget>[
        const SizedBox(height: 16),
        TidyProgressCard(progress: progress, onCancel: _cancel, onRetry: _run),
      ],
      if (problem != null) ...<Widget>[
        const SizedBox(height: 16),
        Text(problem, style: AppText.voiceNote),
      ],
    ];
  }

  List<Widget> _resultView(TidyResult? result) {
    final heading = AppText.dictated.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w600,
    );
    final body = AppText.dictated.copyWith(fontSize: 16);

    return <Widget>[
      if (result != null && result.warnings.isNotEmpty) ...<Widget>[
        TidyWarningNote(result.warnings),
        const SizedBox(height: 16),
      ],
      ..._resultFields(result, heading: heading, body: body),
    ];
  }

  List<Widget> _resultFields(
    TidyResult? result, {
    required TextStyle heading,
    required TextStyle body,
  }) {
    return switch (result) {
      TidiedTask() => <Widget>[
        const TidyLabel('НАЗВАНИЕ'),
        TidyTextField(controller: _title, style: heading, hint: 'Что сделать'),
        const SizedBox(height: 20),
        const TidyLabel('ОПИСАНИЕ'),
        TidyTextField(controller: _body, style: body, hint: 'Нет описания'),
      ],
      TidiedNote(:final title) => <Widget>[
        if (title != null) ...<Widget>[
          const TidyLabel('ЗАГОЛОВОК'),
          TidyTextField(controller: _title, style: heading, hint: 'Заголовок'),
          const SizedBox(height: 20),
        ],
        const TidyLabel('ТЕКСТ'),
        TidyTextField(controller: _body, style: body, hint: 'Текст заметки'),
      ],
      TidiedLine(:final projectId, :final projectName) => <Widget>[
        const TidyLabel('СТРОКА'),
        TidyTextField(controller: _body, style: body, hint: 'Что не забыть'),
        const SizedBox(height: 20),
        const TidyLabel('ПРОЕКТ'),
        _projectChoice(projectId, projectName),
      ],
      ParsedDictation() || null => const <Widget>[],
    };
  }

  /// The suggested project, taken with one tap, and "Другой проект" beside it.
  Widget _projectChoice(String? projectId, String? projectName) {
    final name =
        projectName ??
        widget.projects
            .where((project) => project.id == projectId)
            .map((project) => project.name)
            .firstOrNull;
    final others = widget.projects.where((p) => p.id != projectId).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (projectId != null && name != null)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.voiceBright,
              foregroundColor: AppColors.voiceBackground,
              minimumSize: const Size(0, Targets.minimum),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.row),
              ),
            ),
            onPressed: () => _accept(projectId: projectId, projectName: name),
            icon: const Icon(Icons.folder_outlined, size: 18),
            label: Text('В «$name»'),
          )
        else
          Text('Проект не угадан', style: AppText.voiceNote),
        if (others.isNotEmpty)
          PopupMenuButton<TidyProject>(
            tooltip: 'Другой проект',
            position: PopupMenuPosition.under,
            onSelected: (project) =>
                _accept(projectId: project.id, projectName: project.name),
            itemBuilder: (_) => <PopupMenuEntry<TidyProject>>[
              for (final project in others)
                PopupMenuItem<TidyProject>(
                  value: project,
                  child: Text(project.name),
                ),
            ],
            child: Container(
              height: Targets.minimum,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.voiceLine),
                borderRadius: BorderRadius.circular(Radii.row),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Другой проект',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.voiceBright,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: AppColors.voiceBright,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buttons() {
    final ready = _result != null && !_running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TidyActions(onAsIs: _asIs, onRerun: _running ? null : _run),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: AppColors.voiceBackground,
                disabledBackgroundColor: AppColors.voiceLine,
                disabledForegroundColor: AppColors.voiceMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.row),
                ),
                textStyle: AppText.action.copyWith(fontWeight: FontWeight.w700),
              ),
              onPressed: ready ? _accept : null,
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Готово'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark palette, as a theme, so Material's own bits (the popup menu, the
/// text selection handles, the snackbar) land on it too. Shared by the
/// dictation screen and [AiTidyScreen].
final ThemeData voiceTheme = buildAppTheme().copyWith(
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
