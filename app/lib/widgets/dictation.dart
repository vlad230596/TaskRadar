import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/voice_providers.dart';
import '../theme/tokens.dart';

/// The pieces the dictation screen is built from, plus the one function that
/// puts its result into a field.
///
/// ## What used to be here, and why it is gone (F12)
///
/// Three widgets: a microphone button that distinguished a hold from a tap, a
/// panel that appeared under whichever field was being dictated into, and a
/// `DictatedField` that packaged the two so a new screen could get dictation in
/// one line.
///
/// All three were answers to a shape the product no longer has. Dictation used
/// to be *a property of a text field*, so there were several microphones, each
/// needed to say which field it belonged to, and each needed its own panel
/// underneath. Tested on a phone that produced the two complaints this
/// iteration exists to answer: the fields were too small to read a dictated
/// sentence in, and one button meaning two gestures was a button that "не
/// запускается с первого раза".
///
/// Now the microphone is a fixed part of the shell -- one place, always the
/// same place -- and pressing it opens `screens/dictation_screen.dart`, which
/// owns the whole display and where recording has already started. So there is
/// no button here to hold, no panel to place under a field, and no field to
/// place it under.
///
/// What survives is what was never about the gesture: how text is inserted, how
/// the clock is formatted, and the two moving things that prove the microphone
/// is hearing *you*.

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

/// `1:07`, and never `67` seconds.
///
/// Tabular figures where it is drawn (see `AppText.voiceClock`), so the clock
/// does not twitch every second as the digits change width -- it sits next to a
/// level meter that is already moving, and two moving things are one too many.
String formatDictationClock(Duration d) {
  final seconds = d.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// The recording dot: a filled circle inside a soft halo, breathing.
///
/// The one piece of ornament in this file, and it earns its place. A static dot
/// is indistinguishable from an icon that happens to be drawn orange, which is
/// exactly the ambiguity the whole screen exists to remove -- the user is
/// looking for proof that it is recording *now*.
///
/// Opacity rather than scale: a dot that changes size nudges the baseline of
/// the row, and this one sits next to the word "Слушаю".
class RecordingDot extends StatefulWidget {
  const RecordingDot({this.size = 14, super.key});

  final double size;

  @override
  State<RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<RecordingDot>
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
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(_controller),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: AppColors.voiceRecording,
          shape: BoxShape.circle,
          // The halo the reference draws as `box-shadow: 0 0 0 6px rgba(...)`.
          // A spread-only shadow with no blur is the same ring.
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x38FF6B4A),
              spreadRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

/// A live level meter, fed by the microphone.
///
/// This is the part that proves the microphone is hearing *you*. A clock counts
/// up just as happily from inside a pocket; bars that move with the voice are
/// the difference between "it is recording" and "it is recording me".
///
/// Drawn dark, because the only screen it appears on is dark. Colour is a
/// function of the level rather than a constant, so a loud syllable is visible
/// as a colour change as well as a height change -- on a phone held at arm's
/// length while walking, the height alone is a 70 px difference somebody is not
/// looking at.
class VoiceLevelMeter extends ConsumerStatefulWidget {
  const VoiceLevelMeter({this.height = 72, super.key});

  final double height;

  @override
  ConsumerState<VoiceLevelMeter> createState() => _VoiceLevelMeterState();
}

class _VoiceLevelMeterState extends ConsumerState<VoiceLevelMeter> {
  /// As many bars as the reference draws at 390 px wide.
  static const int _bars = 28;

  /// The last [_bars] levels, oldest first.
  ///
  /// `growable: true` is load-bearing, not tidiness: the default from
  /// `List.filled` is **fixed-length**, and a fixed-length list throws
  /// `UnsupportedError` out of `removeAt`. That is the first thing this widget
  /// does with every sample the microphone produces -- so with a real recorder
  /// the meter threw on the first audio frame, roughly 120 ms into every
  /// dictation. It survived F9 only because no test ever fed it a level and the
  /// panel it lived in was small enough that the red error box was taken for
  /// part of the design.
  final List<double> _history = List<double>.filled(_bars, 0, growable: true);
  StreamSubscription<double>? _levels;

  @override
  void initState() {
    super.initState();
    // Read, not watch: the recorder is already kept alive by the dictation
    // provider for exactly as long as this meter can be on screen, and this
    // widget has no business rebuilding when that provider does.
    _levels = ref.read(voiceRecorderProvider).levels().listen((level) {
      if (!mounted) return;
      setState(() {
        // Scrolls right to left, newest at the right edge, so the tallest bar
        // is the sound being made right now.
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

  /// The three colours of the reference's bars, by how loud the bar is.
  Color _colorFor(double level) {
    if (level >= 0.82) return AppColors.voiceRecordingSoft;
    if (level >= 0.45) return AppColors.voiceLevelHigh;
    if (level >= 0.12) return AppColors.indigo;
    return AppColors.voiceLine;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (final level in _history)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  // A floor of 8 px so a silent meter is still a meter rather
                  // than a hairline: "recording, hearing nothing" and "not
                  // recording" must not look the same.
                  height: 8 + level * (widget.height - 8),
                  decoration: BoxDecoration(
                    color: _colorFor(level),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
