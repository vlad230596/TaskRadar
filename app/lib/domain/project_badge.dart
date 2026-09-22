import 'dart:ui' show Color;

import '../theme/tokens.dart';

/// A project's badge: one letter and one colour, both computed from its name
/// (F12).
///
/// ## Why this is computed and not stored
///
/// The spec closes this question rather than leaving it open: *"поля в базе нет
/// и не будет"*. A stored colour is not one column -- it is a colour picker at
/// the moment a project is created, a migration for the eleven that already
/// exist, and a default to choose anyway for the ones created from the sandbox
/// where there is no dialog at all. That is three decisions bought for one
/// cosmetic property, on a screen whose entire purpose is to spend fewer
/// decisions.
///
/// If living with it makes a chosen colour worth having, the field arrives then
/// and [projectBadgeColor] becomes its default. Nothing here has to change for
/// that; the call sites would read `project.color ?? projectBadgeColor(name)`.
///
/// ## Why a hash and not `hashCode`
///
/// `String.hashCode` in Dart is **not stable across runs** -- the VM seeds it
/// randomly. A badge whose colour changes every time the app restarts is worse
/// than no colour at all: the whole value of the badge is that "Дом" is always
/// the indigo one, recognised before the name is read. So the hash is written
/// out here, and it is FNV-1a, which is four lines and has no surprises.

/// FNV-1a over the name's UTF-16 code units.
///
/// 32-bit arithmetic kept inside the range explicitly (`& 0xFFFFFFFF`), because
/// Dart's `int` is 64-bit on the VM and 53-bit-ish in JavaScript -- and this
/// runs on both (the web build is how the reference comparison is done). Left
/// unmasked the two targets would disagree about which colour a project gets.
int stableNameHash(String name) {
  var hash = 0x811C9DC5;
  for (final unit in name.trim().toLowerCase().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// The colour a name would like, before anyone else on the board has a say:
/// [AppColors.projectBadges] indexed by [stableNameHash].
///
/// Use this only where there is no board to consult -- a single project shown
/// on its own. Anywhere several badges are on screen together, use
/// [assignProjectBadgeColors], for the reason below.
Color projectBadgeColor(String name) {
  final palette = AppColors.projectBadges;
  return palette[stableNameHash(name) % palette.length];
}

/// One colour per project, chosen so that **no two projects on the same board
/// share one**.
///
/// ## Why the hash alone was not enough
///
/// A hash into N buckets collides; that is the birthday problem, not a bug in
/// the hash. On the owner's real board -- Публикации, Дом, TaskRadar, Семья,
/// Авоська, Сезам -- six names over six colours put *three* of them on the same
/// indigo. Widening the palette does not fix it either: measured against those
/// same names, seven, eight and ten colours still collide. Nothing that maps
/// each name independently can promise distinctness, however many hues it is
/// given.
///
/// So the promise moves from "this name always has this colour" to "the
/// projects in front of you are always different colours", which is the
/// property the badge was bought for: *"два проекта, которые нельзя различить
/// на 40 px"* is precisely what must not happen.
///
/// ## What that costs
///
/// A project's colour now depends on which other projects exist. Adding one can
/// recolour a neighbour -- the accepted price, and a smaller one than three
/// projects wearing the same badge. Two things keep it from being worse:
///
/// - **Deterministic**, so the same board is always coloured the same way. The
///   names are sorted before anything is assigned, which makes the result
///   independent of the order the server happened to return them in -- without
///   that, a reordered `GET /board` would repaint the tiles.
/// - **Least-surprise**, so most projects keep their hashed colour. Each name
///   asks for [projectBadgeColor] first and only moves if it is taken; the
///   earlier name in the sort keeps what it asked for.
///
/// Past [AppColors.projectBadges].length projects the palette is exhausted and
/// the allocation starts over, so colours repeat -- but the repeats are a whole
/// palette apart in the sorted order rather than adjacent on screen.
Map<String, Color> assignProjectBadgeColors(Iterable<String> names) {
  final palette = AppColors.projectBadges;

  // Sorted by the same key the hash uses (trimmed, lower case) so that two
  // names which want the same colour are also adjacent in the order that hands
  // colours out. A second comparison on the raw name breaks ties without
  // depending on arrival order -- "Дом" and " ДОМ " are two rows on the board
  // and stay two badges, they just cannot both be the colour they asked for.
  final unique = names.toSet().toList()
    ..sort((a, b) {
      final byKey = a.trim().toLowerCase().compareTo(b.trim().toLowerCase());
      return byKey != 0 ? byKey : a.compareTo(b);
    });

  final colours = <String, Color>{};
  final taken = <int>{};

  for (final name in unique) {
    final preferred = stableNameHash(name) % palette.length;

    // Probe forward from the colour this name wants. The loop is bounded by the
    // palette, and `taken` is emptied the moment it is full, so a board with
    // more projects than colours keeps allocating instead of falling off the
    // end with every remaining project on `preferred`.
    var index = preferred;
    for (var step = 0; step < palette.length; step++) {
      final candidate = (preferred + step) % palette.length;
      if (!taken.contains(candidate)) {
        index = candidate;
        break;
      }
    }

    colours[name] = palette[index];
    taken.add(index);
    if (taken.length == palette.length) taken.clear();
  }

  return colours;
}

/// The badge's letter: the first one of the name, upper case.
///
/// Trimmed first, and "first character" means the first *rune* rather than the
/// first code unit -- a name that begins with an emoji is not something this
/// app forbids, and taking half a surrogate pair out of one renders as a
/// replacement box.
///
/// An empty name (which the API forbids, but a cached row from an older schema
/// might carry) gets `?` rather than an empty square, so the layout does not
/// change shape around a row that is already odd.
String projectBadgeLetter(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}
