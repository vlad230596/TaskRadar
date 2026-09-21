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

/// The badge's colour: [AppColors.projectBadges] indexed by [stableNameHash].
Color projectBadgeColor(String name) {
  final palette = AppColors.projectBadges;
  return palette[stableNameHash(name) % palette.length];
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
