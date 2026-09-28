import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/voice/audio_chunker.dart';

/// Cutting a long dictation into pieces the recogniser can take one at a time.
///
/// The recordings here are synthetic -- noise for speech, zeros for a pause --
/// because what is being tested is where the cuts land, and that depends only
/// on how loud each stretch is. What a real voice sounds like is the model's
/// business.
void main() {
  const rate = 16000;

  int s(double seconds) => (seconds * rate).round();
  double seconds(int samples) => samples / rate;

  /// A recording of [total] seconds of "speech" with silent [pauses], each
  /// given as (start, length) in seconds.
  Float32List recording(
    double total, {
    List<(double, double)> pauses = const <(double, double)>[],
  }) {
    final random = math.Random(7);
    final samples = Float32List(s(total));
    for (var i = 0; i < samples.length; i++) {
      samples[i] = (random.nextDouble() * 2 - 1) * 0.3;
    }
    for (final (start, length) in pauses) {
      samples.fillRange(
        s(start),
        math.min(s(start + length), samples.length),
        0,
      );
    }
    return samples;
  }

  /// Every chunk follows the previous one exactly, and together they are the
  /// whole recording: nothing said is dropped or said twice.
  void expectCovers(List<AudioChunk> chunks, int total) {
    expect(chunks.first.start, 0);
    expect(chunks.last.end, total);
    for (var i = 1; i < chunks.length; i++) {
      expect(chunks[i].start, chunks[i - 1].end);
    }
  }

  group('short recordings', () {
    test('nothing recorded is nothing to recognise', () {
      expect(splitIntoChunks(Float32List(0)), isEmpty);
    });

    test('a phrase is one piece, untouched', () {
      final samples = recording(12);
      expect(splitIntoChunks(samples), <AudioChunk>[
        AudioChunk(0, samples.length),
      ]);
    });

    test('exactly the longest piece is still one piece', () {
      final samples = recording(30);
      expect(splitIntoChunks(samples), hasLength(1));
    });
  });

  group('where the cuts land', () {
    test('in the pause, not in the middle of a word', () {
      // Pauses at 12 s (too early to cut), 24 s, and later ones. The first cut
      // must land in the 24 s pause -- the only one inside 15..30 s.
      final samples = recording(
        70,
        pauses: const <(double, double)>[
          (12, 0.4),
          (24, 0.4),
          (41, 0.4),
          (50, 0.4),
          (62, 0.4),
        ],
      );

      final chunks = splitIntoChunks(samples);

      expectCovers(chunks, samples.length);
      expect(seconds(chunks[0].end), inInclusiveRange(24, 24.4));
    });

    test('of two equally quiet pauses, the one nearer the target', () {
      // After a cut at ~24.2 s the allowed range is ~39..54 s and the target is
      // ~49 s: both pauses qualify, and 50 is the nearer one.
      final samples = recording(
        70,
        pauses: const <(double, double)>[(24, 0.4), (41, 0.4), (50, 0.4)],
      );

      final chunks = splitIntoChunks(samples);

      expect(chunks, hasLength(3));
      expect(seconds(chunks[1].end), inInclusiveRange(50, 50.4));
    });

    test('a pause far from the target beats speech right on it', () {
      // The target is 25 s, but the only quiet moment is at 16 s. A cut
      // through a word at 25 s is worse than a short first piece.
      final samples = recording(
        45,
        pauses: const <(double, double)>[(16, 0.3)],
      );

      final chunks = splitIntoChunks(samples);

      expect(seconds(chunks.first.end), inInclusiveRange(16, 16.3));
    });

    test('a quiet stretch counts, not a single silent frame', () {
      // A plosive's closure is one silent 50 ms frame inside a word. With it at
      // 25 s -- right on the target -- and a real pause at 20 s, the cut still
      // goes into the pause.
      final samples = recording(
        45,
        pauses: const <(double, double)>[(25, 0.05), (20, 0.5)],
      );

      final chunks = splitIntoChunks(samples);

      expect(seconds(chunks.first.end), inInclusiveRange(20, 20.5));
    });
  });

  group('how long the pieces are', () {
    test('never longer than the maximum, even with no pause at all', () {
      // Somebody reading aloud without drawing breath: the cut has to happen
      // anyway, and every piece stays within what the model was trained on.
      final samples = recording(125);

      final chunks = splitIntoChunks(samples);

      expectCovers(chunks, samples.length);
      for (final chunk in chunks) {
        expect(seconds(chunk.length), lessThanOrEqualTo(30));
      }
      for (final chunk in chunks.take(chunks.length - 1)) {
        expect(seconds(chunk.length), greaterThanOrEqualTo(15));
      }
    });

    test('a sliver at the end is not left on its own', () {
      // 31 s with a tempting pause at 29.5 s: cutting there leaves 1.5 s, a
      // breath the model would decode on its own into a word. The tail is
      // kept at three seconds or more instead.
      final samples = recording(
        31,
        pauses: const <(double, double)>[(29.5, 0.4)],
      );

      final chunks = splitIntoChunks(samples);

      expectCovers(chunks, samples.length);
      expect(chunks, hasLength(2));
      expect(seconds(chunks.last.length), greaterThanOrEqualTo(3));
      expect(seconds(chunks.first.length), lessThanOrEqualTo(30));
    });

    test('just over the maximum, with no pause, still has no sliver', () {
      final samples = recording(30.5);

      final chunks = splitIntoChunks(samples);

      expect(chunks, hasLength(2));
      expect(seconds(chunks.last.length), greaterThanOrEqualTo(3));
    });

    test('ten minutes is about twenty pieces, all of them in bounds', () {
      final samples = recording(
        600,
        pauses: <(double, double)>[
          for (var t = 7.0; t < 600; t += 9.3) (t, 0.35),
        ],
      );

      final chunks = splitIntoChunks(samples);

      expectCovers(chunks, samples.length);
      expect(chunks.length, inInclusiveRange(20, 40));
      for (final chunk in chunks) {
        expect(seconds(chunk.length), inInclusiveRange(3, 30));
      }
    });
  });

  group('joining what the pieces said', () {
    test('with one space between them', () {
      expect(
        joinChunkTexts(<String>['Купить кабель', ' и зарядку ']),
        'Купить кабель и зарядку',
      );
    });

    test('a full stop repeated at the seam is said once', () {
      expect(
        joinChunkTexts(<String>['Купить кабель.', '. Потом в сервис.']),
        'Купить кабель. Потом в сервис.',
      );
    });

    test('a comma that starts a piece stays with the sentence before it', () {
      expect(
        joinChunkTexts(<String>['Сначала автомат в щитке', ', второй слева.']),
        'Сначала автомат в щитке, второй слева.',
      );
    });

    test('a piece that heard nothing leaves no double space', () {
      expect(
        joinChunkTexts(<String>['Первое.', '', '   ', 'Второе.']),
        'Первое. Второе.',
      );
      expect(joinChunkTexts(<String>['', '']), '');
    });
  });
}
