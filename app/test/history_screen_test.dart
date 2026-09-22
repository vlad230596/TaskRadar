import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/history_snapshot.dart';
import 'package:taskradar/models/history_task_event.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/history_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/theme/tokens.dart';
import 'package:taskradar/widgets/history_charts.dart';

import 'support/fake_backend.dart';
import 'support/fake_history_backend.dart';

/// Экран истории (F13).
///
/// Проверки — по видимому тексту и по цвету нарисованного, потому что весь этот
/// режим состоит ровно из этих двух вещей. Отдельная и главная группа — пустые
/// данные: в базе может не быть ни одной закрытой задачи, и «0» на месте итога
/// недели был бы неправдой, которую никак не видно.
void main() {
  late FakeBackend backend;
  late FakeHistoryBackend server;

  setUp(() {
    backend = FakeBackend();
    server = FakeHistoryBackend(backend);
  });

  /// `pumpAndSettle` не годится: индикатор загрузки крутится вечно.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpHistory(WidgetTester tester, {Size? size}) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(backend.client)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: HistoryScreen()),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  /// Цвета всех прямоугольников внутри одного виджета — так проверяется
  /// графика, которой нет текста.
  List<Color> paintedColours(WidgetTester tester, Finder within) {
    return tester
        .widgetList<ColoredBox>(
          find.descendant(of: within, matching: find.byType(ColoredBox)),
        )
        .map((box) => box.color)
        .toList();
  }

  group('состояния', () {
    testWidgets('пока сервер считает — говорит, что считает', (tester) async {
      final inFlight = Completer<ResponseBody>();
      backend.responder = (_) => inFlight.future;

      await pumpHistory(tester);

      expect(find.textContaining('Считаем историю'), findsOneWidget);
      expect(find.text('0'), findsNothing);

      inFlight.complete(jsonResponse(server.history));
      await settle(tester);
    });

    testWidgets('сеть отвалилась — это сказано, и есть «Повторить»', (
      tester,
    ) async {
      backend.alwaysFailToConnect();

      await pumpHistory(tester);

      expect(find.text('Не удалось загрузить историю'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Повторить'), findsOneWidget);
    });

    testWidgets('«Повторить» действительно перезапрашивает', (tester) async {
      backend.alwaysFailToConnect();
      await pumpHistory(tester);

      backend.responder = null;
      server = FakeHistoryBackend(backend);
      await tester.tap(find.widgetWithText(TextButton, 'Повторить'));
      await settle(tester);

      expect(find.text('9'), findsOneWidget);
    });
  });

  group('неделя', () {
    testWidgets('число закрытых, подпись и семь столбиков', (tester) async {
      await pumpHistory(tester);

      expect(find.text('9'), findsOneWidget);
      expect(find.text('сделано'), findsOneWidget);
      expect(find.text('за неделю'), findsOneWidget);

      // Семь подписей дней недели — по столбику на день.
      final labels = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ClosedByDayBars),
              matching: find.byType(Text),
            ),
          )
          .length;
      expect(labels, 7);
    });

    testWidgets('день без закрытий — не зелёный столбик', (tester) async {
      await pumpHistory(tester);

      final bars = find.byType(ClosedByDayBars);
      final painted = tester
          .widgetList<Container>(
            find.descendant(of: bars, matching: find.byType(Container)),
          )
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .whereType<Color>()
          .toList();

      // Два пустых дня в фикстуре, оба нарисованы цветом линии.
      expect(painted.where((c) => c == AppColors.line).length, 2);
      expect(painted.where((c) => c == AppColors.done).length, greaterThan(0));
    });
  });

  group('висит дольше всего', () {
    testWidgets('строки, возраст и заголовок раздела', (tester) async {
      await pumpHistory(tester);

      expect(find.text('ВИСИТ ДОЛЬШЕ ВСЕГО'), findsOneWidget);
      expect(
        find.textContaining('Посмотреть, почему не работает вентилятор'),
        findsOneWidget,
      );
      expect(find.text('8 д'), findsOneWidget);
    });

    testWidgets('возраст блокера — тёплый, а взятой в работу — нет', (
      tester,
    ) async {
      await pumpHistory(tester);

      Color colourOf(String age) =>
          tester.widget<Text>(find.text(age)).style!.color!;

      // Восьмидневный блокер, которого никто не взял, — жалоба.
      expect(colourOf('8 д'), AppColors.waitingInk);

      // Пятидневная, но уже в наборе: висит столько же, но это не претензия.
      final inWork = find.ancestor(
        of: find.text('Потестить диктовку на телефоне'),
        matching: find.byType(Row),
      );
      final age = tester.widget<Text>(
        find.descendant(of: inWork.first, matching: find.text('5 д')),
      );
      expect(age.style!.color, AppColors.muted);
    });

    testWidgets('полоска показывает, куда ушёл возраст', (tester) async {
      await pumpHistory(tester);

      final vent = find.ancestor(
        of: find.textContaining('вентилятор'),
        matching: find.byType(StaleSpanBar),
      );
      // Строка и полоска — соседи в колонке, а не предки друг друга, поэтому
      // ищется полоска в той же карточке по порядку.
      final bars = tester.widgetList<StaleSpanBar>(find.byType(StaleSpanBar));
      expect(vent, findsNothing);
      expect(bars.length, 5);

      final first = find.byType(StaleSpanBar).first;
      final colours = paintedColours(tester, first);
      expect(colours, contains(AppColors.lineStrong));
      expect(
        colours,
        contains(AppColors.waitingDot),
        reason: 'четыре дня в блокере — янтарный сегмент',
      );
    });

    testWidgets('в работе рисуется индиговым сегментом', (tester) async {
      await pumpHistory(tester);

      final bars = find.byType(StaleSpanBar);
      final colours = paintedColours(tester, bars.at(3));
      expect(colours, contains(AppColors.indigoLink));
    });
  });

  group('движение по проектам', () {
    testWidgets('строка проекта со счётом и полоской', (tester) async {
      await pumpHistory(tester);

      expect(find.text('ДВИЖЕНИЕ ПО ПРОЕКТАМ'), findsOneWidget);
      expect(find.text('Дом'), findsOneWidget);
      expect(find.text('6 открыто · 2 закрыто'), findsOneWidget);
      // У проекта, где только заводили, второй половины фразы нет.
      expect(find.text('1 открыто'), findsOneWidget);
    });
  });

  group('пустые данные', () {
    testWidgets('в базе ничего нет — экран говорит это словами', (
      tester,
    ) async {
      server.history = server.emptyWeek();
      await pumpHistory(tester);

      expect(find.text('Итогов пока нет'), findsOneWidget);
      expect(find.textContaining('журнал переходов ведётся'), findsOneWidget);

      // Главное: никакого «0» как результата недели.
      expect(find.text('0'), findsNothing);
      expect(find.text('сделано'), findsNothing);
    });

    testWidgets('ноль закрытых при живых долгожителях — не ноль, а фраза', (
      tester,
    ) async {
      server.history = server.historyJson(
        closedByDay: const <int>[0, 0, 0, 0, 0, 0, 0],
        stale: <Map<String, dynamic>>[
          server.staleJson(
            id: 't2',
            title: 'Купить лампочки',
            projectName: 'Дом',
            ageDays: 5,
            pendingDays: 5,
          ),
        ],
      );
      await pumpHistory(tester);

      expect(
        find.text('Ни одной закрытой задачи за неделю.'),
        findsOneWidget,
      );
      expect(find.text('0'), findsNothing);
      // А сами долгожители на месте: пустая неделя их не отменяет.
      expect(find.text('Купить лампочки'), findsOneWidget);
    });
  });

  group('диапазон', () {
    testWidgets('первый запрос — неделя и настоящее смещение пояса', (
      tester,
    ) async {
      await pumpHistory(tester);

      final query = server.lastHistoryRequest!.queryParameters;
      expect(query['range'], '7d');
      expect(query['staleLimit'], 50);
      expect(
        query['tzOffsetMinutes'],
        DateTime.now().timeZoneOffset.inMinutes,
        reason: 'ноль здесь — это столбики недели, посчитанные по UTC',
      );
    });

    testWidgets('выбор месяца перезапрашивает и меняет подпись', (
      tester,
    ) async {
      await pumpHistory(tester);
      expect(find.text('7 дней'), findsOneWidget);

      server.history = server.historyJson(
        range: '30d',
        closedByDay: List<int>.filled(30, 1),
      );

      await tester.tap(find.text('7 дней'));
      await settle(tester);
      await tester.tap(find.text('30 дней').last);
      await settle(tester);

      expect(server.lastHistoryRequest!.queryParameters['range'], '30d');
      expect(find.text('30'), findsOneWidget);
      expect(find.text('за месяц'), findsOneWidget);
    });
  });

  group('широкое окно', () {
    testWidgets('три карточки сверху и легенда фаз', (tester) async {
      await pumpHistory(tester, size: const Size(1440, 900));

      expect(find.text('закрыто за неделю'), findsOneWidget);
      expect(
        find.text('столько в среднем висит открытая задача'),
        findsOneWidget,
      );
      expect(
        find.textContaining('висят дольше недели'),
        findsOneWidget,
      );
      expect(find.byType(PhaseLegend), findsOneWidget);
      // Переключатель тут тремя кнопками, а не меню.
      expect(find.text('всё время'), findsOneWidget);
    });

    testWidgets('средний возраст считается по всем присланным строкам', (
      tester,
    ) async {
      server.history = server.historyJson(
        stale: <Map<String, dynamic>>[
          server.staleJson(
            id: 'a',
            title: 'a',
            projectName: 'Дом',
            ageDays: 2,
            pendingDays: 2,
          ),
          server.staleJson(
            id: 'b',
            title: 'b',
            projectName: 'Дом',
            ageDays: 5,
            pendingDays: 5,
          ),
        ],
      );
      await pumpHistory(tester, size: const Size(1440, 900));

      expect(find.textContaining('3,5'), findsOneWidget);
    });
  });

  group('фазы', () {
    test('у каждой фазы свой цвет и своя подпись', () {
      final colours = <Color>{
        for (final phase in TaskLifePhase.values) phaseColour(phase),
      };
      expect(colours, hasLength(TaskLifePhase.values.length));

      expect(phaseColour(TaskLifePhase.blocked), AppColors.waitingDot);
      expect(phaseColour(TaskLifePhase.working), AppColors.indigoLink);
      expect(phaseShortLabel(TaskLifePhase.working), 'в работе');
    });

    test('меньше суток — это «<1 д», а не «0 д»', () {
      expect(formatSpanShort(Duration.millisecondsPerDay ~/ 3), '<1 д');
      expect(formatSpanShort(2 * Duration.millisecondsPerDay), '2 д');
      expect(formatSpanLong(5 * Duration.millisecondsPerDay), '5 дней');
      expect(formatSpanLong(1000), 'меньше дня');
    });
  });

  group('диапазоны', () {
    test('подписи и значения на проводе', () {
      expect(HistoryRange.week.wire, '7d');
      expect(HistoryRange.month.wire, '30d');
      expect(HistoryRange.all.wire, 'all');
      expect(HistoryRange.all.caption, 'за всё время');
    });
  });
}
