import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/project.dart';
import 'package:taskradar/screens/plan_screen.dart';
import 'package:taskradar/widgets/today/rhythm_sheet.dart';

/// The rhythm on the plan (today-history-spec §6.1): a quiet label, only
/// with a signal.
void main() {
  group('rhythmSignalText', () {
    test('silence counts whole weeks, zero says just «тишина»', () {
      expect(
        rhythmSignalText(
          const ProjectRhythm(silentWeeks: 3, signal: RhythmSignal.silence),
        ),
        'тишина 3 нед',
      );
      expect(
        rhythmSignalText(const ProjectRhythm(signal: RhythmSignal.silence)),
        'тишина',
      );
    });

    test('overflow is open over the ceiling', () {
      expect(
        rhythmSignalText(
          const ProjectRhythm(
            maxOpen: 20,
            open: 24,
            signal: RhythmSignal.overflow,
          ),
        ),
        'перебор 24/20',
      );
    });

    test('no signal, or no rhythm: nothing', () {
      expect(rhythmSignalText(const ProjectRhythm(closedPerWeek: 2)), isNull);
      expect(rhythmSignalText(null), isNull);
    });
  });

  testWidgets('RhythmMark draws the label, or nothing without a signal', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: Column(
            children: <Widget>[
              RhythmMark(
                rhythm: ProjectRhythm(
                  maxOpen: 20,
                  open: 24,
                  signal: RhythmSignal.overflow,
                ),
              ),
              RhythmMark(rhythm: ProjectRhythm(closedPerWeek: 2)),
            ],
          ),
        ),
      ),
    );
    expect(find.text('перебор 24/20'), findsOneWidget);
    expect(find.textContaining('тишина'), findsNothing);
  });
}
