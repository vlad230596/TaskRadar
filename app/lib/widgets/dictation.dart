import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/voice_providers.dart';

/// Dictation on screen (F9): the microphone, and the panel that says what it is
/// doing.
///
/// ## What this file is answering
///
/// The first version of this was a 24 dp icon in the sandbox composer that
/// turned red while a finger held it down. Tested on a phone, in the situation
/// the feature exists for -- walking, one hand, not looking -- it failed three
/// ways at once: it was only on that one screen, the finger missed it, and a
/// recoloured icon is not an answer to "am I recording?" when the reason you
/// are dictating is that you are not looking at the screen.
///
/// So there are three pieces here:
///
/// - [DictateButton] -- 56 dp of microphone in a 64 dp target, with a haptic
///   tick on the way in and out. The haptic is the part that matters: it is the
///   only feedback that survives not looking at the screen.
/// - [DictationPanel] -- a full-width strip under the field carrying a
///   pulsing dot, a live level meter, and a running clock. It stays in the same
///   place through recognition and through a failure, because a message that
///   appears somewhere else is a message you have to go and find.
/// - [DictatedField] -- the two of them plus a text field, so that adding
///   dictation to a new screen is one widget rather than a decision.
///
/// ## The gesture
///
/// **Hold** -- press, speak, release -- is unchanged, and sliding the finger off
/// still cancels. What is new is that letting go too early no longer produces
/// "Держите кнопку, пока говорите": a press shorter than [_minimumHold] locks
/// the recording instead, and it runs until "Готово". A tap was always a clear
/// instruction; the only thing it lacked was a way to say when to stop.
///
/// That leaves the one failure mode a held button cannot have -- a microphone
/// left running -- which is what `VoiceDictation.ceiling` is for.

/// Inserts dictated [text] into [controller], after whatever is already there.
///
/// Appending rather than replacing, because dictating twice in a row is normal:
/// two thoughts on the way to the same place. The caret ends up after the
/// inserted text, ready for the hand to correct a misheard word -- which is why
/// the text lands in a field at all instead of being saved outright. A
/// recogniser with no confidence score is obvious on screen and invisible in a
/// pile you read tomorrow.
void appendDictated(
  TextEditingController controller, {
  required String text,
  String separator = ' ',
}) {
  final existing = controller.text.trimRight();
  final combined = existing.isEmpty ? text : '$existing$separator$text';

  controller.value = TextEditingValue(
    text: combined,
    selection: TextSelection.collapsed(offset: combined.length),
  );
}

/// The microphone button.
///
/// [owner] identifies the field this button dictates into, and is the same
/// token the matching [DictationPanel] is given; see `DictationState.owner`.
/// A screen with one microphone can leave both at null.
class DictateButton extends ConsumerStatefulWidget {
  const DictateButton({required this.onText, this.owner, super.key});

  /// Called with the recognised text, so the field it belongs to can insert it.
  final void Function(String text) onText;

  /// Which field this microphone belongs to. Defaults to the button itself,
  /// which is right whenever there is only one on screen.
  final Object? owner;

  @override
  ConsumerState<DictateButton> createState() => _DictateButtonState();
}

class _DictateButtonState extends ConsumerState<DictateButton> {
  /// Below this, the press is read as "start recording and keep going" rather
  /// than as a phrase somebody held the button for.
  ///
  /// Set by a timer rather than by comparing two `DateTime.now()` readings.
  /// Not a style choice: a timer runs on the same clock the rest of the
  /// framework schedules on, which means a widget test can hold the button for
  /// two seconds with `pump(Duration(seconds: 2))`. Wall-clock arithmetic would
  /// see a few microseconds there and call every dictation in the test suite a
  /// tap -- and the bug would only ever show up as tests that pass for the
  /// wrong reason.
  static const Duration _minimumHold = Duration(milliseconds: 350);

  /// The visible circle, and the target around it.
  ///
  /// Material asks for 48; this is aimed at with a thumb, while walking, next
  /// to two other targets, so it gets more.
  static const double _diameter = 56;
  static const double _target = 64;

  Timer? _holdTimer;
  bool _heldLongEnough = false;
  Future<bool>? _starting;

  Object get _owner => widget.owner ?? this;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _down() {
    _heldLongEnough = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(_minimumHold, () => _heldLongEnough = true);

    // Before anything is awaited: this is the answer to "did I hit it", and it
    // has to arrive at the moment of the press, not after a permission check
    // and a platform channel.
    unawaited(HapticFeedback.mediumImpact());

    _starting = ref
        .read(voiceDictationProvider.notifier)
        .start(owner: _owner, sink: widget.onText);
  }

  Future<void> _up() async {
    _holdTimer?.cancel();

    // A release can beat the microphone opening -- `start` asks the platform
    // for permission and for the input device. Waiting for it here is what
    // makes a fast tap land on `lock` instead of on nothing at all.
    final started = await (_starting ?? Future<bool>.value(false));
    if (!mounted || !started) return;

    final dictation = ref.read(voiceDictationProvider.notifier);
    if (_heldLongEnough) {
      unawaited(HapticFeedback.lightImpact());
      await dictation.finish();
    } else {
      unawaited(HapticFeedback.selectionClick());
      dictation.lock();
    }
  }

  Future<void> _cancel() async {
    _holdTimer?.cancel();
    _heldLongEnough = false;
    await (_starting ?? Future<bool>.value(false));
    if (!mounted) return;
    await ref.read(voiceDictationProvider.notifier).cancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(voiceDictationProvider);
    final mine = state.owner == _owner;
    final holding = mine && state is DictationRecording && !state.locked;

    // While the panel has the recording -- locked, or being recognised -- the
    // button stops being the control: "Готово" is, and it is full width. The
    // space is still held so the field beside it does not jump.
    final handedOver =
        mine && (state is DictationRecognising || (state is DictationRecording && state.locked));

    if (handedOver) {
      return const SizedBox(width: _target, height: _target);
    }

    return GestureDetector(
      // `behavior: opaque` so the padding around the circle is part of the
      // target: this is pressed while walking, at the size of a thumb.
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _cancel,
      // Deliberately not an `IconButton`: its own `InkWell` would win the
      // gesture arena and this widget would never see the press. The tooltip
      // and the padding are what the button was providing, so they are kept.
      child: Tooltip(
        // `manual` disables the tooltip's own long-press recogniser, which
        // otherwise wins the gesture arena about half a second into a hold and
        // cancels the press -- i.e. every dictation longer than the tooltip
        // delay would be silently thrown away. Hovering on the desktop still
        // shows it, which is where a tooltip is read anyway.
        triggerMode: TooltipTriggerMode.manual,
        message: holding ? 'Отпустите, чтобы распознать' : 'Продиктовать',
        child: SizedBox(
          width: _target,
          height: _target,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _diameter,
              height: _diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: holding
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              child: Icon(
                holding ? Icons.mic : Icons.mic_none,
                size: 28,
                color: holding
                    ? theme.colorScheme.onError
                    : theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip under the field that says what the microphone is doing.
///
/// One place for all four states -- recording, recognising, heard nothing,
/// could not start -- because the complaint that produced this widget was not
/// "I could not read the message", it was "I did not know it had started". A
/// message that appears in a different corner for each outcome cannot answer
/// that; a strip that is either there or not can.
///
/// Renders nothing at all when its [owner] is not the one dictating, so a
/// screen may hold several without two of them lighting up at once.
class DictationPanel extends ConsumerWidget {
  const DictationPanel({this.owner, super.key});

  /// Show only this field's dictation. Null shows whichever one is running,
  /// which is what a screen with a single microphone wants.
  final Object? owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceDictationProvider);
    if (state is DictationIdle) return const SizedBox.shrink();
    if (owner != null && state.owner != owner) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final dictation = ref.read(voiceDictationProvider.notifier);

    final (Color tint, Widget body) = switch (state) {
      DictationIdle() => (Colors.transparent, const SizedBox.shrink()),
      DictationRecording(:final elapsed, :final locked) => (
        theme.colorScheme.error,
        _Recording(
          elapsed: elapsed,
          locked: locked,
          onFinish: dictation.finish,
          onCancel: dictation.cancel,
        ),
      ),
      DictationRecognising(:final length) => (
        theme.colorScheme.primary,
        _Recognising(length: length),
      ),
      DictationFailed(:final message, :final retryable) => (
        theme.colorScheme.error,
        _Failed(
          message: message,
          onRetry: retryable ? dictation.retry : null,
          onDismiss: dictation.acknowledge,
        ),
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          border: Border.all(color: tint.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: body,
      ),
    );
  }
}

/// `1:07`, and never `67` seconds.
///
/// Tabular figures so the strip does not twitch every second as the digits
/// change width -- the clock sits next to a level meter that is already moving,
/// and two moving things are one too many.
String formatDictationClock(Duration d) {
  final seconds = d.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _Recording extends StatelessWidget {
  const _Recording({
    required this.elapsed,
    required this.locked,
    required this.onFinish,
    required this.onCancel,
  });

  final Duration elapsed;
  final bool locked;
  final Future<void> Function() onFinish;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = VoiceDictation.ceiling - elapsed;
    // The limit is only worth mentioning once it is close: named up front it
    // would be a rule to remember, and half a minute out it is a warning.
    final nearCeiling = remaining <= const Duration(seconds: 30);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const _PulsingDot(),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                locked ? 'Идёт запись' : 'Говорите — отпустите, когда всё',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              nearCeiling
                  ? '−${formatDictationClock(remaining)}'
                  : formatDictationClock(elapsed),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.error,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _LevelMeter(),
        if (locked) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  // 48 tall and the full width of the strip: this is the one
                  // control a locked recording has, and it is pressed by the
                  // same thumb that could not find a 24 dp icon.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: () => unawaited(onFinish()),
                  child: const Text('Готово'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () => unawaited(onCancel()),
                child: const Text('Отменить'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Recognising extends StatelessWidget {
  const _Recognising({required this.length});

  final Duration length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Распознаю…', style: theme.textTheme.titleSmall),
            ),
            Text(
              formatDictationClock(length),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Indeterminate on purpose: sherpa reports nothing until it is done, and
        // a percentage invented here would be a lie about a number the user can
        // check against the clock beside it.
        const LinearProgressIndicator(minHeight: 4),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final Future<void> Function()? onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retry = onRetry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.mic_off_outlined,
              size: 18,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (retry != null)
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: () => unawaited(retry()),
                  child: const Text('Ещё раз'),
                ),
              ),
            if (retry != null) const SizedBox(width: 8),
            if (retry == null) const Spacer(),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onDismiss,
              child: const Text('Понятно'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The red dot, breathing.
///
/// The one piece of ornament in this file, and it earns its place: a static dot
/// is indistinguishable from an icon that is simply drawn red, which is exactly
/// the ambiguity this whole panel exists to remove.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;

    return FadeTransition(
      // Opacity rather than scale: a dot that changes size nudges the row's
      // baseline, and this one sits next to text.
      opacity: Tween<double>(begin: 1, end: 0.3).animate(_controller),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// A live level meter, fed by the microphone.
///
/// This is the part that proves the microphone is hearing *you*. A clock counts
/// up just as happily from inside a pocket; bars that move with the voice are
/// the difference between "it is recording" and "it is recording me".
class _LevelMeter extends ConsumerStatefulWidget {
  const _LevelMeter();

  @override
  ConsumerState<_LevelMeter> createState() => _LevelMeterState();
}

class _LevelMeterState extends ConsumerState<_LevelMeter> {
  static const int _bars = 26;

  final List<double> _history = List<double>.filled(_bars, 0);
  StreamSubscription<double>? _levels;

  @override
  void initState() {
    super.initState();
    // Read, not watch: the recorder is already kept alive by the dictation
    // provider for exactly as long as this panel can be on screen, and this
    // widget has no business rebuilding when that provider does.
    _levels = ref.read(voiceRecorderProvider).levels().listen((level) {
      if (!mounted) return;
      setState(() {
        // Scrolls right to left, newest at the right edge, so the bar under the
        // thumb is the sound being made right now.
        _history.removeAt(0);
        _history.add(level);
      });
    });
  }

  @override
  void dispose() {
    unawaited(_levels?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;

    return SizedBox(
      height: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final level in _history)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  height: 4 + level * 24,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.35 + level * 0.65),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A text field with a microphone beside it and the recording panel under it.
///
/// The whole point of this widget is that giving a new screen dictation is one
/// line rather than a decision: it mints the owner token, puts the button where
/// every other field in the app has it, and drops the panel directly underneath
/// so "идёт запись" always appears in the same relationship to the field being
/// dictated into.
///
/// [field] may be null, for the one case with nothing to sit beside -- a
/// microphone under a text area that already fills the screen.
class DictatedField extends ConsumerStatefulWidget {
  const DictatedField({
    required this.onText,
    this.field,
    this.trailing,
    super.key,
  });

  /// The text field. Laid out as the flexible part of the row.
  final Widget? field;

  /// Called with recognised text. Almost always [appendDictated] against the
  /// field's own controller.
  final void Function(String text) onText;

  /// Whatever the screen already had next to the field -- the "+" button on a
  /// composer, usually. Kept after the microphone so the send action stays at
  /// the edge where the thumb expects it.
  final Widget? trailing;

  @override
  ConsumerState<DictatedField> createState() => _DictatedFieldState();
}

class _DictatedFieldState extends ConsumerState<DictatedField> {
  /// This field's identity for `DictationState.owner`. An `Object` because
  /// nothing ever reads it -- it only has to be different from the other
  /// fields' tokens and stable across rebuilds.
  final Object _token = Object();

  @override
  Widget build(BuildContext context) {
    // The microphone is only on screen when there is a model to dictate with:
    // a button that answers "сначала скачайте 163 МБ" is a button that lies
    // about what it does, and offering the download is Settings' job.
    final canDictate = ref.watch(canDictateProvider);
    final field = widget.field;
    final trailing = widget.trailing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (field != null) Expanded(child: field),
            if (field == null) const Spacer(),
            if (canDictate)
              DictateButton(owner: _token, onText: widget.onText),
            if (trailing != null) ...[const SizedBox(width: 4), trailing],
          ],
        ),
        if (canDictate) DictationPanel(owner: _token),
      ],
    );
  }
}
