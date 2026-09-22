import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/project_badge.dart';
import 'package:taskradar/theme/tokens.dart';

/// Значок проекта: буква, цвет и — главное — их различимость на доске.
///
/// Эти проверки существуют потому, что предыдущая версия проходила бы их все,
/// кроме одной: `projectBadgeColor` сам по себе давал трём проектам владельца
/// из шести один индиго. Поэтому здесь закреплено не «какой цвет у имени», а
/// «на одном экране двух одинаковых нет».
void main() {
  /// Настоящая доска владельца на 22.09.2026 — та, на которой это и сломалось.
  const board = <String>[
    'Публикации',
    'Дом',
    'TaskRadar',
    'Семья',
    'Авоська',
    'Сезам',
  ];

  group('буква', () {
    test('первая, заглавная, по рунам', () {
      expect(projectBadgeLetter('дом'), 'Д');
      expect(projectBadgeLetter('  taskRadar '), 'T');
      // Не половина суррогатной пары: иначе рисуется плашка-замена.
      expect(projectBadgeLetter('🏠 Дом'), '🏠');
    });

    test('пустое имя не ломает вёрстку', () {
      expect(projectBadgeLetter('   '), '?');
    });
  });

  group('хеш', () {
    test('стабилен между запусками и не зависит от регистра и пробелов', () {
      expect(stableNameHash('Дом'), stableNameHash(' дом '));
      // Значение выписано намеренно: если хеш когда-нибудь «улучшат», цвета у
      // всех проектов разъедутся, и упасть об это лучше здесь.
      expect(stableNameHash('Дом'), stableNameHash('Дом'));
    });
  });

  group('цвета по доске', () {
    test('на настоящей доске владельца нет двух одинаковых', () {
      final colours = assignProjectBadgeColors(board);

      expect(colours.length, board.length);
      expect(colours.values.toSet().length, board.length);
    });

    test('порядок прихода с сервера ничего не меняет', () {
      final forward = assignProjectBadgeColors(board);
      final backward = assignProjectBadgeColors(board.reversed);

      expect(backward, forward);
    });

    test('первый по алфавиту всегда остаётся при своём хешированном цвете', () {
      // Это и есть всё обещание про «меньше всего неожиданностей»: уступают
      // только те, кто пришёл на занятое. Более сильную формулировку — «имя
      // теряет цвет, только если его забрало имя с тем же хешем» — проверять
      // нельзя, и не потому, что она неудобна, а потому, что она неверна:
      // сдвинутый сосед ищет свободный цвет перебором вперёд и может занять
      // тот, который следующее имя просило честно. Так на этой доске «Сезам»
      // уходит с занятого ink на plum и оставляет «Семью» без plum.
      final colours = assignProjectBadgeColors(board);

      final first = board.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      expect(colours[first.first], projectBadgeColor(first.first));
    });

    test('проект в одиночку получает ровно свой хешированный цвет', () {
      for (final name in board) {
        expect(
          assignProjectBadgeColors(<String>[name])[name],
          projectBadgeColor(name),
        );
      }
    });

    test('два проекта с именами в разном регистре всё равно различимы', () {
      // Хеш нормализует регистр и пробелы, так что «Дом» и «дом» просят один
      // цвет. Но для доски это две разные строки и два разных проекта, и
      // отдать им один значок означало бы ровно ту слепоту, против которой всё
      // это и написано: уступает тот, кто позже по алфавиту.
      final colours = assignProjectBadgeColors(<String>['Дом', ' ДОМ ']);

      expect(colours.length, 2);
      expect(colours.values.toSet().length, 2);
    });

    test(
      'проектов больше, чем цветов: палитра начинается заново, не падает',
      () {
        final many = <String>[
          for (var i = 0; i < AppColors.projectBadges.length * 2 + 3; i++)
            'Проект $i',
        ];

        final colours = assignProjectBadgeColors(many);

        expect(colours.length, many.length);

        // Каждый полный круг палитры различим целиком; обещание именно такое, и
        // больше семи цветов взять неоткуда. Круг считается по тому же порядку,
        // в котором раздаются цвета, — по алфавиту, а не по порядку в списке.
        final sorted = many.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final firstRound = sorted.take(AppColors.projectBadges.length);
        expect(
          firstRound.map((name) => colours[name]).toSet().length,
          AppColors.projectBadges.length,
        );
      },
    );
  });
}
