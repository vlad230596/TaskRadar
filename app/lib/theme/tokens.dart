/// Every colour, size and type style the redesigned client is allowed to use
/// (F12).
///
/// ## Why the numbers live in one file instead of next to the widgets
///
/// The reference for this redesign is not a picture, it is
/// `design/reference/*.html` -- static pages with exact `px` and `hex` on every
/// element. Acceptance is a literal side-by-side comparison against them. A
/// `Color(0xFF4A56BE)` written inline in six widgets is six places for the
/// comparison to drift, and five of them will be found by eye rather than by a
/// test. Named once, the same drift is one edit.
///
/// The second reason is the rule the spec states above the pixels: *"микрофон
/// живёт в одном месте"*, *"мишень не меньше 44 px"*, *"плашка возраста не
/// переносится"*. Those are invariants, and an invariant with a name
/// ([Targets.minimum], [Targets.microphone]) is one a reviewer can check;
/// spelled as a bare `44` it is a number somebody will round down to 40 to make
/// a row fit.
///
/// Nothing here is derived from `ColorScheme`. Material's scheme is generated
/// from a seed and quietly re-tints everything it touches, which is exactly
/// what must not happen to a palette taken from the app's own icon. The theme
/// in `app_theme.dart` maps these into a `ColorScheme` for the widgets that
/// insist on one, and the direction of that mapping is deliberate: tokens are
/// the source, the scheme is the copy.
library;

import 'dart:ui';

/// The palette, straight from `design/three-modes-spec.md`, which took it from
/// `design/icon/taskradar-icon.svg`.
abstract final class AppColors {
  // -- Surfaces -------------------------------------------------------------

  /// The page behind everything.
  static const Color background = Color(0xFFF3F3F7);

  /// A card, a field, a row.
  static const Color card = Color(0xFFFFFFFF);

  /// The hairline between things that are both cards.
  static const Color line = Color(0xFFDEDEE8);

  /// A heavier line: the border of a row that is *the* row, and of the dashed
  /// "add" targets. Also the empty status dot.
  static const Color lineStrong = Color(0xFFC3C6DE);

  /// The faintest rule there is -- inside a card, between two halves of it.
  static const Color lineFaint = Color(0xFFEDEDF3);

  // -- Ink ------------------------------------------------------------------

  /// Text, and the primary button.
  static const Color ink = Color(0xFF1B2050);

  /// Body text that is not a heading: a task title inside a project row.
  static const Color inkSoft = Color(0xFF3A3C5C);

  /// Second-plane text: counters, ages, captions.
  static const Color muted = Color(0xFF61637E);

  /// Text on [ink] and on [indigo].
  static const Color onInk = Color(0xFFFFFFFF);

  // -- Indigo: selection, and the voice --------------------------------------

  /// The one accent. **The only button in the app painted with it is the
  /// microphone** -- see the rule in the spec. Anything else that needs to look
  /// chosen uses [indigoFill].
  static const Color indigo = Color(0xFF4A56BE);

  /// The wash behind an active tab, a project chip, a selected pill.
  static const Color indigoFill = Color(0xFFE6E8F7);

  /// Text and icons drawn on [indigoFill].
  static const Color indigoInk = Color(0xFF2C3480);

  /// A link, and the border of the field that has focus.
  static const Color indigoLink = Color(0xFF3F4AA8);

  // -- Status ---------------------------------------------------------------

  /// "Сделано".
  static const Color done = Color(0xFF2A6B4E);

  /// "Ждёт" / "залежалось": the text.
  static const Color waitingInk = Color(0xFF8A5A0B);

  /// The wash behind a blocked row.
  static const Color waitingFill = Color(0xFFFDF7EE);

  /// The border of a blocked row, and the chip behind an age that has gone too
  /// far.
  static const Color waitingLine = Color(0xFFEBD5B0);

  /// The chip fill for an age that has gone too far. Warmer than
  /// [waitingFill], which is a whole-row wash and has to stay quiet.
  static const Color waitingChip = Color(0xFFFBEFDD);

  /// The dot. Not the text colour: a 10 px circle needs more saturation than a
  /// 12 px word to read as the same thing.
  static const Color waitingDot = Color(0xFFE0A03C);

  /// The same dot where it sits on [ink] -- on the dark "В работе" bar and on
  /// the dark sandbox tile, where [waitingDot] goes muddy.
  static const Color waitingDotOnInk = Color(0xFFF0A33C);

  /// The sandbox counter, and "выбросить". The one red in the app.
  static const Color alarm = Color(0xFFB3341F);

  // -- Dictation, which is the one dark screen -------------------------------

  /// The dictation screen's background.
  static const Color voiceBackground = Color(0xFF14183C);

  /// Text on it.
  static const Color voiceInk = Color(0xFFEDEEF7);

  /// Second-plane text on it.
  static const Color voiceMuted = Color(0xFFA7AECF);

  /// Text on it that is nearly white but still tinted -- a button's label.
  static const Color voiceBright = Color(0xFFD6DBFF);

  /// The hairline on it.
  static const Color voiceLine = Color(0xFF39407A);

  /// A level-meter bar that is loud.
  static const Color voiceLevelHigh = Color(0xFF6C79E8);

  /// The "recording" dot, and the clock beside it.
  static const Color voiceRecording = Color(0xFFFF6B4A);

  /// The clock, and the peaks of the meter.
  static const Color voiceRecordingSoft = Color(0xFFFF8C70);

  // -- The desktop rail, which is dark for the same reason ------------------

  /// The rail's own background. Same [ink] as the primary button: the rail is
  /// chrome, not content.
  static const Color railBackground = ink;

  /// The rail's active item.
  static const Color railActive = Color(0xFF333A73);

  /// The rail's inactive item.
  static const Color railMuted = voiceMuted;

  /// Six colours for a project's badge, picked by a stable hash of its name.
  ///
  /// Six, and these six, because the spec's answer to "which colour is this
  /// project" is *"поля в базе нет и не будет"* -- a chosen colour would mean a
  /// picker, a migration, and one more decision at the moment a project is
  /// created, which is the exact mental cost the three modes exist to remove.
  ///
  /// The first four are the palette's own status colours reused as identity;
  /// the last two are the only further hues that sit at the same lightness
  /// without colliding with one of them. They are deliberately **not** shades
  /// of indigo: two projects whose badges differ by 8% saturation are two
  /// projects you cannot tell apart at 40 px on a phone, which is the entire
  /// job of the badge.
  static const List<Color> projectBadges = <Color>[
    indigo,
    done,
    waitingInk,
    alarm,
    ink,
    Color(0xFF1F5F73),
  ];
}

/// The two families, and the weights each one is bundled at.
///
/// Both are declared in `pubspec.yaml` against files in `assets/fonts`, never
/// fetched. The web build is the reason this is not negotiable: CanvasKit
/// rasterises text itself and has no system fonts, and the site policy's
/// `connect-src 'self'` refuses fonts.gstatic.com -- which produces not a
/// fallback face but *no text at all*. The same rule already put Roboto and
/// CanvasKit on our own origin.
abstract final class AppFonts {
  /// The interface face. 400/500/600/700.
  static const String text = 'Golos Text';

  /// Large numbers, mode names and screen titles only. 600/700.
  ///
  /// Used sparingly on purpose: Unbounded is a display face with very open
  /// counters, and a paragraph set in it is slower to read than the same
  /// paragraph in Golos. It is here to make the four or five numbers on a
  /// screen -- an age, a count, a sandbox backlog -- legible at a glance from
  /// arm's length.
  static const String display = 'Unbounded';
}

/// Corner radii, named by what they belong to rather than by their value, so a
/// card and a chip cannot drift apart by one pixel each release.
abstract final class Radii {
  /// A project card, a sandbox line, the big task field.
  static const double card = 16;

  /// The wider cards: a tile, the task text area, a sandbox section.
  static const double panel = 20;

  /// A row inside a list, a segmented button, a small action square.
  static const double row = 14;

  /// A chip, a pill, a status badge. Half of its own height in practice.
  static const double chip = 11;

  /// A bottom-bar item, a rail item, the "Готово" button.
  static const double stub = 18;

  /// The one thing that is properly round: the dictation "Готово".
  static const double large = 24;
}

/// Touch targets. The spec states the floor once and it is not a suggestion:
/// every one of these screens is used one-handed, while walking, without
/// looking.
abstract final class Targets {
  /// Nothing tappable is smaller than this. Material asks for 48 in some places
  /// and 40 in others; the smaller of those is below what a thumb finds.
  static const double minimum = 44;

  /// A task row, a status button, a project row's hit area.
  static const double row = 56;

  /// The microphone, everywhere it is not the bottom bar: a 56x56 indigo square
  /// in the bottom-right corner of a sub-screen, and the bottom of the desktop
  /// rail.
  static const double microphone = 56;

  /// "Готово" on the dictation screen. Bigger than everything else in the app
  /// because it is pressed while not looking at it, and because pressing the
  /// wrong thing there loses a sentence.
  static const double finishDictation = 76;

  /// One item of the phone's bottom bar.
  static const double navItem = 54;

  /// The bottom bar itself, including the strip of padding above the items.
  static const double navBar = 82;

  /// The fixed width of the "Голос" item, which does not stretch with the other
  /// three -- it has to be in the same place on every screen.
  static const double navVoiceWidth = 84;

  /// One item of the desktop rail.
  static const double railItem = 56;

  /// The desktop rail.
  static const double railWidth = 76;

  /// The task text area on the task screen. **The** number of this iteration:
  /// the answer to "в композере видно два-три слова".
  static const double taskField = 252;
}

/// Standard gaps. Only the ones that repeat; a one-off distance stays a literal
/// at its use site, where it is easier to compare against the reference page
/// than it is to look up.
abstract final class Insets {
  /// The side gutter of every phone screen.
  static const double gutter = 16;

  /// Between two cards in a list.
  static const double gap = 10;

  /// Inside a card.
  static const double card = 14;
}
