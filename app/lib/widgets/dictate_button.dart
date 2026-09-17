import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/voice_providers.dart';

/// Hold to dictate (F9).
///
/// ## The gesture
///
/// Press, speak, release. Not tap-to-start / tap-to-stop, because the thing
/// being replaced is typing while walking: a hold has an unmistakable end (the
/// finger comes up), whereas a toggle leaves a microphone running when somebody
/// is distracted mid-sentence -- which is both a battery and a privacy
/// accident. Sliding the finger off cancels, which is the standard escape
/// hatch for a press-and-hold and costs nothing to support: the tap gesture
/// loses the arena and reports a cancel.
///
/// A press shorter than [_minimumHold] is treated as an accident rather than an
/// empty phrase. Without it, brushing the button produces "ничего не
/// расслышали", which reads as a broken feature instead of a missed tap.
///
/// ## Why it is not on screen when the model is missing
///
/// A microphone button that answers "сначала скачайте 163 МБ" is a button that
/// lies about what it does. The composer says the line instead, and the
/// download lives in Settings, where a quarter of a gigabyte can be presented
/// as something to agree to.
class DictateButton extends ConsumerStatefulWidget {
  const DictateButton({required this.onText, super.key});

  /// Called with the recognised text, so the field it belongs to can insert it.
  final void Function(String text) onText;

  @override
  ConsumerState<DictateButton> createState() => _DictateButtonState();
}

class _DictateButtonState extends ConsumerState<DictateButton> {
  static const Duration _minimumHold = Duration(milliseconds: 350);

  /// Set by a timer rather than by comparing two `DateTime.now()` readings.
  ///
  /// Not a style choice: a timer runs on the same clock the rest of the
  /// framework schedules on, which means a widget test can hold the button for
  /// two seconds with `pump(Duration(seconds: 2))`. Wall-clock arithmetic would
  /// see a few microseconds there and call every dictation in the test suite an
  /// accidental brush -- and the bug would only ever show up as tests that pass
  /// for the wrong reason.
  Timer? _holdTimer;
  bool _heldLongEnough = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  Future<void> _down() async {
    _heldLongEnough = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(_minimumHold, () => _heldLongEnough = true);

    await ref.read(voiceDictationProvider.notifier).start();
  }

  Future<void> _up() async {
    _holdTimer?.cancel();

    if (!_heldLongEnough) {
      await ref.read(voiceDictationProvider.notifier).cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Держите кнопку, пока говорите.')),
      );
      return;
    }

    final text = await ref
        .read(voiceDictationProvider.notifier)
        .stopAndTranscribe();
    if (text != null && mounted) widget.onText(text);
  }

  Future<void> _cancel() async {
    _holdTimer?.cancel();
    _heldLongEnough = false;
    await ref.read(voiceDictationProvider.notifier).cancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(voiceDictationProvider);

    // A failure is said once, when it happens, and then forgotten -- the button
    // itself goes back to normal. A microphone stuck in a red error state is
    // something the user has to dismiss for no reason.
    ref.listen<DictationState>(voiceDictationProvider, (previous, next) {
      if (next is! DictationFailed) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(next.message)));
      ref.read(voiceDictationProvider.notifier).acknowledge();
    });

    if (state is DictationRecognising) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final recording = state is DictationRecording;

    return GestureDetector(
      // `behavior: opaque` so the padding around the icon is part of the
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
        message: recording ? 'Отпустите, чтобы распознать' : 'Продиктовать',
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            recording ? Icons.mic : Icons.mic_none,
            color: recording ? theme.colorScheme.error : null,
          ),
        ),
      ),
    );
  }
}
