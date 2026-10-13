/// How hard the model may work a text over (backend `src/domain/aiLevels.ts`).
///
/// An integer on the wire and on disk, not an enum: three stops today, and
/// more is a matter of adding names here and rules on the server.
const int aiLevelMin = 1;
const int aiLevelMax = 3;

/// What the app sent before levels existed: the middle stop.
const int aiLevelDefault = 2;

/// The levels that exist, weakest first.
const List<int> aiLevels = <int>[1, 2, 3];

/// The stop's name, as the switch and the settings show it.
String aiLevelName(int level) => switch (level) {
  1 => 'Лёгкая',
  2 => 'Обычная',
  3 => 'Сильная',
  _ => 'Уровень $level',
};

/// One line on what the stop does, for the settings screen.
String aiLevelHint(int level) => switch (level) {
  1 => 'Убрать слова-паразиты и явные ошибки, формулировки не трогать.',
  2 => 'Причесать: паразиты, ошибки, гладкие фразы — без пересказа.',
  3 => 'Переформулировать и сократить, сохранив каждый факт.',
  _ => '',
};

/// [level] if it is a stop that exists, otherwise the default.
int validAiLevel(int? level) =>
    level != null && level >= aiLevelMin && level <= aiLevelMax
    ? level
    : aiLevelDefault;
