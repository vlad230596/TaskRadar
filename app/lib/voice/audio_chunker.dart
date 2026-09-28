import 'dart:math' as math;
import 'dart:typed_data';

/// Cutting a long recording into pieces the recogniser can take one at a time.
///
/// ## Why the audio is cut at all
///
/// GigaAM is a CTC model trained on utterances of up to about half a minute.
/// Handed ten minutes in one piece it does not fail, it does something worse:
/// it takes a very long time, holds all of it in memory at once, and says
/// nothing until the very end -- which on a phone is a screen reading
/// "Распознаю" for a minute with no way to tell it from a hang. In pieces of
/// 20-30 s each one is inside what the model was trained on, the memory peak is
/// one piece rather than the whole recording, and every finished piece is a
/// step the screen can show.
///
/// ## Why the cut goes into a pause
///
/// A word cut in half is two half-words the model will guess at, one on each
/// side of the seam. People breathe between phrases, so within a few seconds of
/// any target length there is almost always a quiet stretch; the cut goes into
/// the quietest one in the allowed range, with a slight preference for the one
/// nearest the target so the pieces stay roughly even.
///
/// Everything here is plain arithmetic over samples: it runs in the recogniser's
/// isolate, and it is tested without a model or a device.

/// A piece of the recording, as sample offsets: `[start, end)`.
class AudioChunk {
  const AudioChunk(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is AudioChunk && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'AudioChunk($start, $end)';
}

/// Splits [samples] (mono, at [sampleRate]) into consecutive chunks.
///
/// - A recording no longer than [maxLength] is one chunk.
/// - Otherwise every cut lands between [minLength] and [maxLength] after the
///   previous one, in the quietest [window] of that range, ties going to the
///   one nearest [targetLength].
/// - No chunk is ever shorter than [minTail]. A cut that would leave a sliver
///   at the end is not allowed to be made: the search range is pulled back so
///   the remainder is at least that long. A second of audio decoded on its own
///   is where a CTC model is at its worst -- no context, and often just a
///   breath it will turn into a word.
///
/// The chunks cover the input exactly, with no gaps and no overlap.
List<AudioChunk> splitIntoChunks(
  Float32List samples, {
  int sampleRate = 16000,
  Duration targetLength = const Duration(seconds: 25),
  Duration minLength = const Duration(seconds: 15),
  Duration maxLength = const Duration(seconds: 30),
  Duration minTail = const Duration(seconds: 3),
  Duration window = const Duration(milliseconds: 50),
}) {
  assert(minLength <= targetLength && targetLength <= maxLength);
  assert(minLength + minTail <= maxLength);

  int toSamples(Duration d) => d.inMicroseconds * sampleRate ~/ 1000000;

  final total = samples.length;
  if (total == 0) return const <AudioChunk>[];

  final max = toSamples(maxLength);
  if (total <= max) return <AudioChunk>[AudioChunk(0, total)];

  final min = toSamples(minLength);
  final target = toSamples(targetLength);
  final tail = toSamples(minTail);
  final frame = math.max(1, toSamples(window));

  // Energy per frame, computed once. Mean square rather than RMS: only the
  // ordering matters, and the square root is 190 000 of them for ten minutes.
  final frames = (total + frame - 1) ~/ frame;
  final energy = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    final from = f * frame;
    final to = math.min(from + frame, total);
    var sum = 0.0;
    for (var i = from; i < to; i++) {
      final s = samples[i];
      sum += s * s;
    }
    energy[f] = sum / (to - from);
  }

  // A pause is a few quiet frames in a row, not one: the closure of a "п" or
  // a "т" is a single silent frame in the middle of a word. So a frame is
  // judged together with its neighbours.
  double quietness(int f) {
    var sum = 0.0;
    var n = 0;
    for (var g = f - 1; g <= f + 1; g++) {
      if (g < 0 || g >= frames) continue;
      sum += energy[g];
      n++;
    }
    return sum / n;
  }

  final chunks = <AudioChunk>[];
  var start = 0;
  while (total - start > max) {
    final lowest = start + min;
    // Pulled back from the far end so what is left afterwards is never a
    // sliver -- see the note on [minTail].
    final highest = math.min(start + max, total - tail);

    final firstFrame = (lowest + frame - 1) ~/ frame;
    final lastFrame = math.max(firstFrame, highest ~/ frame - 1);
    final range = math.max(1, highest - lowest);

    var best = -1;
    var bestScore = double.infinity;
    for (var f = firstFrame; f <= lastFrame; f++) {
      final centre = f * frame + frame ~/ 2;
      final distance = (centre - (start + target)).abs() / range;
      // Silence against speech is two orders of magnitude, so a penalty of at
      // most half again only decides between pauses that are about as quiet
      // as each other -- which is exactly when "nearer the target" should win.
      // The tiny additive term does the same for pauses that are *exactly*
      // equal, digital silence being zero times any penalty.
      final score = quietness(f) * (1 + 0.5 * distance) + 1e-12 * distance;
      if (score < bestScore) {
        bestScore = score;
        best = f;
      }
    }

    final cut = (best * frame + frame ~/ 2).clamp(lowest, highest);
    chunks.add(AudioChunk(start, cut));
    start = cut;
  }
  chunks.add(AudioChunk(start, total));
  return chunks;
}

/// Joins what the recogniser said about each chunk into one text.
///
/// The punctuating model sees each chunk as a whole utterance, so the seams
/// show: a chunk may end on a full stop that the next one repeats, or start
/// with a comma that belongs to the sentence before it. Those are folded into
/// one; everything else is joined with a single space. Capitals are left as
/// the model wrote them -- a sentence that really did start at the seam would
/// lose its capital to a lowercasing rule, and a capital too many is the
/// cheaper mistake.
String joinChunkTexts(Iterable<String> parts) {
  const punctuation = '.,!?;:…';
  final out = StringBuffer();
  for (final raw in parts) {
    var part = raw.trim();
    if (part.isEmpty) continue;
    if (out.isEmpty) {
      out.write(part);
      continue;
    }
    final soFar = out.toString();
    final endsWithMark = punctuation.contains(soFar[soFar.length - 1]);
    if (endsWithMark) {
      // "…кабель." + ". Потом…" -> one full stop, not two.
      var i = 0;
      while (i < part.length && punctuation.contains(part[i])) {
        i++;
      }
      part = part.substring(i).trimLeft();
      if (part.isEmpty) continue;
      out.write(' ');
    } else if (!punctuation.contains(part[0])) {
      out.write(' ');
    }
    out.write(part);
  }
  return out.toString();
}
