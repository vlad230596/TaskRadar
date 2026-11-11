import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/smart_tokens.dart';

/// The inline token parser (task-editor spec, section 2). Every case stands on
/// a fixed wall clock: Wednesday 11 November 2026, 15:00, unless it says
/// otherwise. `now` is a plain local `DateTime` and the parser reads only its
/// fields, so these hold in any zone the suite runs in.
void main() {
  final wed15 = DateTime(2026, 11, 11, 15, 0);
  const none = SmartContext();

  SmartToken? dateIn(String text, {DateTime? now, SmartContext ctx = none}) {
    final tokens = parseSmartTokens(text, now: now ?? wed15, ctx: ctx);
    final dates = tokens.where((t) => t.kind == TokenKind.date).toList();
    expect(dates.length, lessThanOrEqualTo(1), reason: 'rule 8: one date');
    return dates.isEmpty ? null : dates.single;
  }

  /// `"YYYY-MM-DD HH:MM"` / `"YYYY-MM-DD"` / null, plus the recognised text.
  (String?, String?) read(String text, {DateTime? now}) {
    final t = dateIn(text, now: now);
    if (t == null) return (null, null);
    final value = t.remindTime == null
        ? t.remindAt!
        : '${t.remindAt} ${t.remindTime}';
    return (value, text.substring(t.start, t.end));
  }

  void table(Map<String, (String?, String?)> cases, {DateTime? now}) {
    cases.forEach((text, expected) {
      expect(read(text, now: now), expected, reason: text);
    });
  }

  group('rule 1: сегодня / завтра / послезавтра', () {
    test('day words', () {
      table({
        'сегодня': ('2026-11-11', 'сегодня'),
        'Купить корм завтра': ('2026-11-12', 'завтра'),
        'послезавтра забрать посылку': ('2026-11-13', 'послезавтра'),
      });
    });

    test('only whole words', () {
      table({
        'назавтра': (null, null),
        'завтрак с Машей': (null, null),
        'сегодняшний отчёт': (null, null),
      });
    });
  });

  group('rule 2: weekdays', () {
    test('nearest such day, today included when no time', () {
      table({
        'в четверг': ('2026-11-12', 'в четверг'),
        'в пятницу': ('2026-11-13', 'в пятницу'),
        'в субботу': ('2026-11-14', 'в субботу'),
        'в воскресенье': ('2026-11-15', 'в воскресенье'),
        'в понедельник': ('2026-11-16', 'в понедельник'),
        'во вторник': ('2026-11-17', 'во вторник'),
        'в среду': ('2026-11-11', 'в среду'),
        'понедельник': ('2026-11-16', 'понедельник'),
        'пятница: сдать отчёт': ('2026-11-13', 'пятница'),
      });
    });

    test('today only while the time is still ahead', () {
      table({
        'в среду в 18': ('2026-11-11 18:00', 'в среду в 18'),
        'в среду в 10': ('2026-11-18 10:00', 'в среду в 10'),
        'в среду в 15:00': ('2026-11-18 15:00', 'в среду в 15:00'),
      });
    });

    test('«следующий» is the day on next week', () {
      table({
        'в следующую пятницу': ('2026-11-20', 'в следующую пятницу'),
        'в следующий понедельник': ('2026-11-16', 'в следующий понедельник'),
        'в следующую среду': ('2026-11-18', 'в следующую среду'),
        'следующее воскресенье': ('2026-11-22', 'следующее воскресенье'),
      });
    });

    test('abbreviations need в/во or a time next to them', () {
      table({
        'в пт': ('2026-11-13', 'в пт'),
        'во вт': ('2026-11-17', 'во вт'),
        'в чт в 9:30': ('2026-11-12 09:30', 'в чт в 9:30'),
        'пт в 18:00': ('2026-11-13 18:00', 'пт в 18:00'),
        'пт 18:00': (null, null),
        'вс': (null, null),
        'купить пн и вт': (null, null),
      });
    });

    test('«среда» as a noun is not a date without a preposition', () {
      table({
        'настроить среду разработки': (null, null),
        'рабочая среда': (null, null),
        'в среду': ('2026-11-11', 'в среду'),
      });
    });
  });

  group('rule 3: calendar dates', () {
    test('forms', () {
      table({
        '15 ноября': ('2026-11-15', '15 ноября'),
        '15 ноя': ('2026-11-15', '15 ноя'),
        '15 ноя.': ('2026-11-15', '15 ноя'),
        '15.11': ('2026-11-15', '15.11'),
        '15.11.2026': ('2026-11-15', '15.11.2026'),
        '15/11': ('2026-11-15', '15/11'),
        '3 января': ('2027-01-03', '3 января'),
        '1 мая': ('2027-05-01', '1 мая'),
        '15 ноября 2027': ('2027-11-15', '15 ноября 2027'),
        '05.12': ('2026-12-05', '05.12'),
      });
    });

    test('к / до mean the same date and are part of the token', () {
      table({
        'Сдать отчёт к 15 ноября': ('2026-11-15', 'к 15 ноября'),
        'до 20.11': ('2026-11-20', 'до 20.11'),
        'до пятницы': ('2026-11-13', 'до пятницы'),
        'к пятнице': ('2026-11-13', 'к пятнице'),
        'к понедельнику': ('2026-11-16', 'к понедельнику'),
        'до следующей среды': ('2026-11-18', 'до следующей среды'),
        'до воскресенья': ('2026-11-15', 'до воскресенья'),
      });
    });

    test('without a year: past this year means next year; today is today', () {
      table({
        '1 ноября': ('2027-11-01', '1 ноября'),
        '10.11': ('2027-11-10', '10.11'),
        '11 ноября': ('2026-11-11', '11 ноября'),
        '29 февраля': ('2028-02-29', '29 февраля'),
      });
      expect(dateIn('1 ноября')!.past, isFalse);
    });

    test('an explicit past year is kept and marked past', () {
      final t = dateIn('15.11.2025')!;
      expect(t.remindAt, '2025-11-15');
      expect(t.past, isTrue);
    });

    test('impossible dates and prose numbers are not dates', () {
      table({
        '31.02': (null, null),
        '32 января': (null, null),
        '15.13': (null, null),
        'версия 1.2': (null, null),
        'версия 1.15.11': (null, null),
        '15.11.3': (null, null),
        'купить 15 яблок': (null, null),
        '3/4 работы': (null, null),
      });
    });
  });

  group('rule 4: times', () {
    test('forms (15:00 now: earlier hours go to tomorrow)', () {
      table({
        'в 16': ('2026-11-11 16:00', 'в 16'),
        'в 10': ('2026-11-12 10:00', 'в 10'),
        'в 10:30': ('2026-11-12 10:30', 'в 10:30'),
        'в 10.30': ('2026-11-12 10:30', 'в 10.30'),
        'к 10': ('2026-11-12 10:00', 'к 10'),
        'в 9 утра': ('2026-11-12 09:00', 'в 9 утра'),
        'в 12 дня': ('2026-11-12 12:00', 'в 12 дня'),
        'в 2 дня': ('2026-11-12 14:00', 'в 2 дня'),
        'в 6 вечера': ('2026-11-11 18:00', 'в 6 вечера'),
        'в 2 ночи': ('2026-11-12 02:00', 'в 2 ночи'),
        'в полдень': ('2026-11-12 12:00', 'в полдень'),
        'в 10 ч': ('2026-11-12 10:00', 'в 10 ч'),
        'в 10ч': ('2026-11-12 10:00', 'в 10ч'),
        'в 10 часов': ('2026-11-12 10:00', 'в 10 часов'),
        'в 10 часов утра': ('2026-11-12 10:00', 'в 10 часов утра'),
        'в 20 часов': ('2026-11-11 20:00', 'в 20 часов'),
      });
    });

    test('1–7 without утра/ночи is the evening; 8–23 as said', () {
      table({
        'в 1': ('2026-11-12 13:00', 'в 1'),
        'в 5': ('2026-11-11 17:00', 'в 5'),
        'в 7': ('2026-11-11 19:00', 'в 7'),
        'в 8': ('2026-11-12 08:00', 'в 8'),
        'в 5 утра': ('2026-11-12 05:00', 'в 5 утра'),
        'в 23': ('2026-11-11 23:00', 'в 23'),
      });
    });

    test('a bare «в N» is a time only at a clause end or next to a day', () {
      table({
        'позвонить в 5, потом поесть': ('2026-11-11 17:00', 'в 5'),
        'позвонить в 5.': ('2026-11-11 17:00', 'в 5'),
        'позвонить в 5\nи ещё': ('2026-11-11 17:00', 'в 5'),
        'завтра в 2 этапа': ('2026-11-12 14:00', 'завтра в 2'),
      });
    });

    test('negatives', () {
      table({
        'сделать в 2 этапа': (null, null),
        'напечатать в 3 экземплярах': (null, null),
        'в 10 раз больше': (null, null),
        'в 24': (null, null),
        'в 10:75': (null, null),
        'в 5-6 местах': (null, null),
        'в 10,5 литрах': (null, null),
        'счёт 2:1': (null, null),
        'в 2 частях': (null, null),
      });
    });
  });

  group('rule 5: only a time', () {
    test('today if still ahead, else tomorrow (the same minute is gone)', () {
      table({
        'в 15:01': ('2026-11-11 15:01', 'в 15:01'),
        'в 15': ('2026-11-12 15:00', 'в 15'),
        'в 14:59': ('2026-11-12 14:59', 'в 14:59'),
      });
      expect(dateIn('в 15')!.past, isFalse);
    });
  });

  group('rule 6: relative', () {
    test('minutes and hours give a date and a time', () {
      table({
        'через 2 часа': ('2026-11-11 17:00', 'через 2 часа'),
        'через 30 минут': ('2026-11-11 15:30', 'через 30 минут'),
        'через 15 мин': ('2026-11-11 15:15', 'через 15 мин'),
        'через 1 минуту': ('2026-11-11 15:01', 'через 1 минуту'),
        'через 3 ч': ('2026-11-11 18:00', 'через 3 ч'),
        'через час': ('2026-11-11 16:00', 'через час'),
        'через полчаса': ('2026-11-11 15:30', 'через полчаса'),
        'через пару часов': ('2026-11-11 17:00', 'через пару часов'),
        'через пять минут': ('2026-11-11 15:05', 'через пять минут'),
        'через десять часов': ('2026-11-12 01:00', 'через десять часов'),
      });
    });

    test('days, weeks and months give only a date', () {
      table({
        'через 2 дня': ('2026-11-13', 'через 2 дня'),
        'через 5 дней': ('2026-11-16', 'через 5 дней'),
        'через два дня': ('2026-11-13', 'через два дня'),
        'через день': ('2026-11-12', 'через день'),
        'через неделю': ('2026-11-18', 'через неделю'),
        'через 3 недели': ('2026-12-02', 'через 3 недели'),
        'через месяц': ('2026-12-11', 'через месяц'),
        'через 2 месяца': ('2027-01-11', 'через 2 месяца'),
        'через одну неделю': ('2026-11-18', 'через одну неделю'),
      });
    });

    test('a month from 31 January is the end of February', () {
      table({
        'через месяц': ('2027-02-28', 'через месяц'),
      }, now: DateTime(2027, 1, 31, 9));
    });

    test('«через 3 часа» at 23:00 crosses midnight on the wall clock', () {
      table({
        'через 3 часа': ('2026-11-12 02:00', 'через 3 часа'),
        'через 45 минут': ('2026-11-11 23:45', 'через 45 минут'),
        'через 90 минут': ('2026-11-12 00:30', 'через 90 минут'),
      }, now: DateTime(2026, 11, 11, 23, 0));
    });

    test('not relative', () {
      table({
        'через': (null, null),
        'через 5': (null, null),
        'через 5 полчаса': (null, null),
        'через дорогу': (null, null),
        'через часы': (null, null),
      });
    });
  });

  group('rule 7: combinations in any order, one token', () {
    test('spaces only between the parts', () {
      table({
        'Купить корм коту завтра в 10': ('2026-11-12 10:00', 'завтра в 10'),
        'в 10 завтра': ('2026-11-12 10:00', 'в 10 завтра'),
        'в 18 в пятницу': ('2026-11-13 18:00', 'в 18 в пятницу'),
        'в пятницу в 18': ('2026-11-13 18:00', 'в пятницу в 18'),
        '15 ноября в 9:30': ('2026-11-15 09:30', '15 ноября в 9:30'),
        'в 9:30 15 ноября': ('2026-11-15 09:30', 'в 9:30 15 ноября'),
        'в 15 ноября': ('2026-11-15', '15 ноября'),
        'завтра 10:30': ('2026-11-12 10:30', 'завтра 10:30'),
        'через 2 дня в 10': ('2026-11-13 10:00', 'через 2 дня в 10'),
        'к пятнице к 12': ('2026-11-13 12:00', 'к пятнице к 12'),
        'сегодня в 6 вечера': ('2026-11-11 18:00', 'сегодня в 6 вечера'),
      });
    });

    test('punctuation splits; two days do not merge', () {
      table({
        'завтра, в 10': ('2026-11-12', 'завтра'),
        'завтра в пятницу': ('2026-11-12', 'завтра'),
        'через 2 часа завтра': ('2026-11-11 17:00', 'через 2 часа'),
      });
    });
  });

  group('rule 8: only the first date expression', () {
    test('later ones stay text', () {
      table({
        'перенести с пятницы на понедельник': ('2026-11-16', 'понедельник'),
        'в пятницу или в субботу': ('2026-11-13', 'в пятницу'),
        'завтра, а потом 20 ноября': ('2026-11-12', 'завтра'),
      });
    });
  });

  group('rule 9: result format and past', () {
    test('a moment already gone is allowed and flagged', () {
      final t = dateIn('сегодня в 9')!;
      expect(t.remindAt, '2026-11-11');
      expect(t.remindTime, '09:00');
      expect(t.past, isTrue);
    });

    test('today without a time, and the future, are not past', () {
      expect(dateIn('сегодня')!.past, isFalse);
      expect(dateIn('сегодня в 18')!.past, isFalse);
      expect(dateIn('завтра в 9')!.past, isFalse);
    });

    test('day-only token has a null time; values are zero-padded', () {
      final t = dateIn('5 декабря')!;
      expect(t.remindAt, '2026-12-05');
      expect(t.remindTime, isNull);
      expect(dateIn('в 9:05 завтра')!.remindTime, '09:05');
    });
  });

  group('case, ё, edges of the year and the day', () {
    test('case does not matter', () {
      table({
        'ЗАВТРА В 10': ('2026-11-12 10:00', 'ЗАВТРА В 10'),
        'В Пятницу': ('2026-11-13', 'В Пятницу'),
        '15 Ноября': ('2026-11-15', '15 Ноября'),
      });
    });

    test('31 December rolls into the next year', () {
      table({
        'завтра': ('2027-01-01', 'завтра'),
        'в 10': ('2027-01-01 10:00', 'в 10'),
        'через 3 часа': ('2027-01-01 01:00', 'через 3 часа'),
        '5 января': ('2027-01-05', '5 января'),
        '31 декабря': ('2026-12-31', '31 декабря'),
        'в понедельник': ('2027-01-04', 'в понедельник'),
        'в следующую пятницу': ('2027-01-08', 'в следующую пятницу'),
        'через неделю': ('2027-01-07', 'через неделю'),
      }, now: DateTime(2026, 12, 31, 22, 0));
    });

    test('at midnight every time today is still ahead', () {
      table({
        'в 9 утра': ('2026-11-11 09:00', 'в 9 утра'),
        'через 30 минут': ('2026-11-11 00:30', 'через 30 минут'),
        'сегодня в 0:00': ('2026-11-11 00:00', 'сегодня в 0:00'),
      }, now: DateTime(2026, 11, 11, 0, 0));
      expect(
        dateIn('сегодня в 0:00', now: DateTime(2026, 11, 11, 0, 0))!.past,
        isTrue,
      );
    });

    test('only the wall-clock fields of now are read', () {
      final utc = DateTime.utc(2026, 11, 11, 15, 0);
      expect(dateIn('в 16', now: utc)!.remindAt, '2026-11-11');
      expect(dateIn('в 16', now: utc)!.remindTime, '16:00');
    });
  });

  group('ranges', () {
    test('start/end point at the recognised text, not the whole string', () {
      const text = 'Купить корм коту завтра в 10 обязательно';
      final t = dateIn(text)!;
      expect(t.start, text.indexOf('завтра'));
      expect(t.end, text.indexOf(' обязательно'));
    });

    test('ranges are in UTF-16 units of the original text', () {
      const text = '🐱 корм завтра';
      final t = dateIn(text)!;
      expect(text.substring(t.start, t.end), 'завтра');
    });

    test('several kinds are returned sorted by start', () {
      final ctx = SmartContext(
        projects: const [SmartProject(id: 'p1', name: 'Дом')],
        categories: const [SmartCategory(id: 'c1', name: 'Покупки')],
      );
      const text = '/пок молоко #дом завтра';
      final tokens = parseSmartTokens(text, now: wed15, ctx: ctx);
      expect(tokens.map((t) => t.kind), [
        TokenKind.category,
        TokenKind.project,
        TokenKind.date,
      ]);
      expect(tokens.map((t) => text.substring(t.start, t.end)), [
        '/пок',
        '#дом',
        'завтра',
      ]);
    });
  });

  group('URLs', () {
    test('nothing is recognised inside a link', () {
      table({
        'см. https://site.ru/завтра/15.11?d=в 10': (null, null),
        'www.site.ru/сегодня': (null, null),
        'http://x.ru/#дом/в-пятницу': (null, null),
      });
      final ctx = SmartContext(
        projects: const [SmartProject(id: 'p1', name: 'Дом')],
      );
      expect(
        parseSmartTokens('https://x.ru/#дом', now: wed15, ctx: ctx),
        isEmpty,
      );
    });

    test('text next to a link still counts', () {
      table({
        'прочитать https://site.ru/a завтра в 10': (
          '2026-11-12 10:00',
          'завтра в 10',
        ),
      });
    });

    test('findLinks', () {
      const text =
          'Смотри https://example.com/a?b=1. И www.site.ru, '
          '(http://x.ru/path) и https://ru.wikipedia.org/wiki/Foo_(bar)!';
      final links = findLinks(text);
      expect(links.map((l) => l.url), [
        'https://example.com/a?b=1',
        'https://www.site.ru',
        'http://x.ru/path',
        'https://ru.wikipedia.org/wiki/Foo_(bar)',
      ]);
      for (final l in links) {
        expect(text.substring(l.start, l.end), isNot(endsWith('.')));
      }
      expect(text.substring(links[1].start, links[1].end), 'www.site.ru');
    });

    test('findLinks ignores non-links', () {
      expect(findLinks('купить хлеб'), isEmpty);
      expect(findLinks('awww.ru'), isEmpty);
      expect(findLinks('https://'), isEmpty);
      expect(
        findLinks('HTTPS://EXAMPLE.COM').single.url,
        'HTTPS://EXAMPLE.COM',
      );
    });
  });

  group('dismissed spans', () {
    test('a dismissed date is text, and the next date is recognised', () {
      const text = 'завтра в 10 или в пятницу';
      final first = dateIn(text)!;
      expect(text.substring(first.start, first.end), 'завтра в 10');

      final t = dateIn(text, ctx: SmartContext(dismissed: [first.range]))!;
      expect(text.substring(t.start, t.end), 'в пятницу');
    });

    test('a candidate overlapping a dismissed span stays text', () {
      // «завтра» was dismissed, then « в 10» was typed after it.
      expect(
        dateIn(
          'завтра в 10',
          ctx: const SmartContext(dismissed: [SmartRange(0, 6)]),
        ),
        isNull,
      );
    });

    test('dismissed range elsewhere does not block', () {
      expect(
        dateIn(
          'купить завтра',
          ctx: const SmartContext(dismissed: [SmartRange(0, 6)]),
        )!.remindAt,
        '2026-11-12',
      );
    });

    test('dismissed project and category tokens', () {
      final ctx = SmartContext(
        projects: const [
          SmartProject(id: 'p1', name: 'Дом'),
          SmartProject(id: 'p2', name: 'Работа'),
        ],
        dismissed: const [SmartRange(0, 4)],
      );
      final tokens = parseSmartTokens('#дом и #раб', now: wed15, ctx: ctx);
      expect(tokens.single.projectId, 'p2');
    });

    test('findAllTokenRanges reports every candidate for an existing task', () {
      const text = 'позвонить в пятницу, потом завтра в 10 /пок';
      final ctx = SmartContext(
        categories: const [SmartCategory(id: 'c1', name: 'Покупки')],
        dismissed: const [SmartRange(10, 19)],
      );
      final ranges = findAllTokenRanges(text, now: wed15, ctx: ctx);
      expect(ranges.map((r) => text.substring(r.start, r.end)), [
        'в пятницу',
        'завтра в 10',
        '/пок',
      ]);

      // Dismissing all of them leaves nothing active.
      final tokens = parseSmartTokens(
        text,
        now: wed15,
        ctx: SmartContext(categories: ctx.categories, dismissed: ranges),
      );
      expect(tokens, isEmpty);

      // Text typed later in the session is live again.
      final typed = '$text и через час';
      final live = parseSmartTokens(
        typed,
        now: wed15,
        ctx: SmartContext(categories: ctx.categories, dismissed: ranges),
      );
      expect(live.single.remindTime, '16:00');
    });

    group('shiftRangesForEdit', () {
      const r = SmartRange(7, 13); // «завтра» in «купить завтра утром»

      test('edit before shifts, edit after keeps', () {
        expect(
          shiftRangesForEdit(
            [r],
            'купить завтра утром',
            'ну купить завтра утром',
          ),
          [const SmartRange(10, 16)],
        );
        expect(
          shiftRangesForEdit(
            [r],
            'купить завтра утром',
            'купить завтра утром!',
          ),
          [r],
        );
      });

      test('typing right after the range keeps it', () {
        expect(shiftRangesForEdit([r], 'купить завтра', 'купить завтра в 10'), [
          r,
        ]);
      });

      test('typing right before the range shifts it', () {
        expect(shiftRangesForEdit([r], 'купить завтра', 'купить ну завтра'), [
          const SmartRange(10, 16),
        ]);
      });

      test('an edit inside the range drops it', () {
        expect(
          shiftRangesForEdit([r], 'купить завтра утром', 'купить завра утром'),
          isEmpty,
        );
      });

      test('deleting text before shifts back', () {
        expect(shiftRangesForEdit([r], 'купить завтра', 'ить завтра'), [
          const SmartRange(4, 10),
        ]);
      });

      test('no edit, same list', () {
        expect(shiftRangesForEdit([r], 'a', 'a'), [r]);
      });
    });
  });

  group('#проект', () {
    const projects = [
      SmartProject(id: 'home', name: 'Дом'),
      SmartProject(id: 'homely', name: 'Домашние дела'),
      SmartProject(id: 'work', name: 'Работа'),
      SmartProject(id: 'dacha2', name: 'Дача 2'),
      SmartProject(id: 'dacha', name: 'Дача'),
      SmartProject(id: 'tree', name: 'Ёлка'),
    ];
    const ctx = SmartContext(projects: projects);

    SmartToken? project(String text, {SmartContext c = ctx}) {
      final t = parseSmartTokens(
        text,
        now: wed15,
        ctx: c,
      ).where((t) => t.kind == TokenKind.project).toList();
      return t.isEmpty ? null : t.single;
    }

    test('one prefix match is active', () {
      final t = project('Позвонить #раб')!;
      expect(t.projectId, 'work');
      expect(t.candidates, ['work']);
      expect((t.start, t.end), (10, 14));
      expect(t.isResolved, isTrue);
    });

    test('case-insensitive, ё = е', () {
      expect(project('#РАБОТА')!.projectId, 'work');
      expect(project('#елка')!.projectId, 'tree');
      expect(project('#ёлк')!.projectId, 'tree');
    });

    test('several prefix matches: no id, candidates for the popup', () {
      final t = project('#до')!;
      expect(t.projectId, isNull);
      expect(t.isResolved, isFalse);
      expect(t.candidates, ['home', 'homely']);
    });

    test('an exact name wins over longer prefixes', () {
      final t = project('#дом')!;
      expect(t.projectId, 'home');
      expect(t.candidates, ['home', 'homely']);
    });

    test('names with spaces: following words or quotes', () {
      const text = '#Дача 2 полить';
      final t = project(text)!;
      expect(t.projectId, 'dacha2');
      expect(text.substring(t.start, t.end), '#Дача 2');

      final plain = project('#Дача полить')!;
      expect(plain.projectId, 'dacha');
      expect(plain.end, 5);

      final quoted = project('купить #"Дача 2" доски')!;
      expect(quoted.projectId, 'dacha2');
      expect(quoted.end, 'купить #"Дача 2"'.length);

      expect(project('#домашние дела')!.projectId, 'homely');
    });

    test('zero matches, glued #, empty list: not a token', () {
      expect(project('#xyz'), isNull);
      expect(project('a#дом'), isNull);
      expect(project('#'), isNull);
      expect(project('#""'), isNull);
      expect(project('#дом', c: const SmartContext()), isNull);
    });

    test('only the first matching project is a token', () {
      final t = project('#раб #дом')!;
      expect(t.projectId, 'work');
    });

    test('a project tag is not read as a date', () {
      const c = SmartContext(
        projects: [SmartProject(id: 'z', name: 'Завтра')],
      );
      final tokens = parseSmartTokens('#завтра', now: wed15, ctx: c);
      expect(tokens.single.kind, TokenKind.project);
      expect(dateIn('#завтра'), isNull);
    });
  });

  group('/категория', () {
    const cats = [
      SmartCategory(id: 'buy', name: 'Покупки'),
      SmartCategory(id: 'mail', name: 'Почта'),
    ];
    const ctx = SmartContext(categories: cats);

    SmartToken? category(String text, {SmartContext c = ctx}) {
      final t = parseSmartTokens(
        text,
        now: wed15,
        ctx: c,
      ).where((t) => t.kind == TokenKind.category).toList();
      return t.isEmpty ? null : t.single;
    }

    test('prefix match against the selected project', () {
      final t = category('молоко /пок')!;
      expect(t.categoryId, 'buy');
      expect((t.start, t.end), (7, 11));
    });

    test('ambiguous and missing', () {
      final t = category('/по')!;
      expect(t.categoryId, isNull);
      expect(t.candidates, ['buy', 'mail']);
      // A category that does not exist is not created from text.
      expect(category('/дача'), isNull);
    });

    test('slashes inside words, dates and links are not categories', () {
      expect(category('и/или'), isNull);
      expect(category('15/11'), isNull);
      expect(category('https://x.ru/покупки'), isNull);
    });

    test('a resolved #проект in the same text switches the category list', () {
      const c = SmartContext(
        projects: [
          SmartProject(
            id: 'work',
            name: 'Работа',
            categories: [SmartCategory(id: 'rep', name: 'Отчёты')],
          ),
        ],
        categories: cats,
      );
      expect(category('#раб /отч', c: c)!.categoryId, 'rep');
      expect(category('#раб /пок', c: c), isNull);
      // Without the project token, the selected project's list is used.
      expect(category('/пок', c: c)!.categoryId, 'buy');
    });
  });

  group('stripTokens (title cleanup on save)', () {
    const ctx = SmartContext(
      projects: [SmartProject(id: 'home', name: 'Дом')],
      categories: [SmartCategory(id: 'buy', name: 'Покупки')],
    );

    String strip(String text, {DateTime? now}) =>
        stripTokens(text, parseSmartTokens(text, now: now ?? wed15, ctx: ctx));

    test('cases', () {
      const cases = {
        'Купить корм коту завтра в 10': 'Купить корм коту',
        'Завтра в 10 позвонить маме': 'Позвонить маме',
        'Купить корм на завтра': 'Купить корм',
        'Встреча, завтра в 10, с Петей': 'Встреча, с Петей',
        'Купить хлеб #дом завтра.': 'Купить хлеб.',
        'Сдать отчёт к 15 ноября': 'Сдать отчёт',
        'Позвонить завтра в 10 и купить хлеб': 'Позвонить и купить хлеб',
        'Молоко /пок #дом': 'Молоко',
        'завтра в 10: позвонить': 'позвонить',
        'Позвонить   маме   через час': 'Позвонить маме',
        'Купить хлеб и завтра': 'Купить хлеб',
        'Позвонить (завтра) маме': 'Позвонить маме',
        'Сделать в 2 этапа завтра': 'Сделать в 2 этапа',
        'Строка один\nзавтра в 10 строка два': 'Строка один\nстрока два',
      };
      cases.forEach((input, expected) {
        expect(strip(input), expected, reason: input);
      });
    });

    test('nothing left: the text stays', () {
      expect(strip('завтра в 10'), 'завтра в 10');
      expect(strip('  #дом '), '#дом');
    });

    test('no tokens: only trimmed', () {
      expect(stripTokens('  купить   хлеб ', const []), 'купить   хлеб');
    });

    test('only the given tokens are cut (later dates stay)', () {
      expect(
        strip('Перенести с пятницы на понедельник'),
        'Перенести с пятницы',
      );
    });
  });
}
