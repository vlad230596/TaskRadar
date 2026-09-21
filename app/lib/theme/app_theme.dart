import 'package:flutter/material.dart';

import 'tokens.dart';

/// The named type styles, and the [ThemeData] that carries them (F12).
///
/// ## Why the styles are constants rather than `Theme.of(context).textTheme`
///
/// Material's text theme has thirteen slots with names describing a *rank*
/// (`titleMedium`, `bodySmall`) rather than a job. The reference pages name
/// jobs: the mode title, a project name, an age chip, the dictated text. Mapping
/// one onto the other means every screen making the same guess -- and the guess
/// is where "15 px, weight 500" quietly becomes "14 px, weight 400" because
/// `bodyMedium` was the closest slot.
///
/// So the screens read [AppText] directly. The `textTheme` below is still filled
/// in, because Material's own widgets (dialogs, snackbars, the date picker) read
/// it and would otherwise fall back to Roboto at Material's sizes -- but it is
/// a translation of these styles, not their source.
abstract final class AppText {
  /// Numbers never move. An age counting 9 д -> 10 д, a clock at 0:09 -> 0:10
  /// and a sandbox badge all sit next to something else, and proportional
  /// digits make the whole row twitch as they change.
  static const List<FontFeature> _figures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  // -- Display: the mode name, the screen title, and big numbers ------------

  /// "Планирование" at the top of a mode. 21/700 Unbounded.
  static const TextStyle mode = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 21,
    letterSpacing: -0.21,
    color: AppColors.ink,
  );

  /// The same thing on the desktop, where there is room for one more point.
  static const TextStyle modeWide = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    letterSpacing: -0.22,
    color: AppColors.ink,
  );

  /// A sub-screen's title: "Песочница", "Дом". 18/600 Unbounded.
  static const TextStyle screen = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w600,
    fontSize: 18,
    color: AppColors.ink,
  );

  /// The task screen's title, which is one word and sits between two 44 px
  /// buttons. 16/600 Unbounded.
  static const TextStyle screenTight = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    color: AppColors.ink,
  );

  /// A number that is the point of the thing it is in: a sandbox backlog, a
  /// project's task count, "8 дней" over the task's life bar.
  static const TextStyle number = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    height: 1.1,
    color: AppColors.ink,
    fontFeatures: _figures,
  );

  /// The same number where it is a heading rather than a headline -- 17 px.
  static const TextStyle numberSmall = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 17,
    color: AppColors.ink,
    fontFeatures: _figures,
  );

  /// The letter inside a project badge.
  static const TextStyle badge = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 16,
    color: AppColors.onInk,
  );

  // -- Interface -----------------------------------------------------------

  /// A project's name in the list. 17/600.
  static const TextStyle projectName = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w600,
    fontSize: 17,
    color: AppColors.ink,
  );

  /// A button's label, a tile's name, a section heading inside a card. 15/600.
  static const TextStyle action = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    color: AppColors.ink,
  );

  /// The current task under a project name; the label of a filing button.
  /// 15/500.
  static const TextStyle body = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w500,
    fontSize: 15,
    height: 1.35,
    color: AppColors.inkSoft,
  );

  /// A task row's title. 15.5/500, because a row is 56-66 px and this is what
  /// fits two lines into it.
  static const TextStyle taskTitle = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w500,
    fontSize: 15.5,
    height: 1.3,
    color: AppColors.ink,
  );

  /// The same row when it is *the* row -- the project's current task.
  static const TextStyle taskTitleCurrent = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w600,
    fontSize: 15.5,
    height: 1.3,
    color: AppColors.ink,
  );

  /// A line waiting in the sandbox. 16.5/500 -- a touch larger than a task,
  /// because it is unsorted prose and the screen's job is reading it.
  static const TextStyle sandboxLine = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w500,
    fontSize: 16.5,
    height: 1.35,
    color: AppColors.ink,
  );

  /// The task screen's text area. **20/500** -- the direct answer to complaint
  /// number one. See [Targets.taskField] for its height.
  static const TextStyle taskField = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w500,
    fontSize: 20,
    height: 1.42,
    color: AppColors.ink,
  );

  /// The sandbox's editable line: 19/500, one point down from the task field
  /// because several of them are on screen at once.
  static const TextStyle sandboxField = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w500,
    fontSize: 19,
    height: 1.4,
    color: AppColors.ink,
  );

  /// What the microphone just heard. 25/500 on the dark screen, half a screen
  /// of it, correctable on the spot.
  static const TextStyle dictated = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w500,
    fontSize: 25,
    height: 1.38,
    color: Color(0xFFFFFFFF),
  );

  // -- Small print ---------------------------------------------------------

  /// A chip: an age, a count, a status. 12/600, and it never wraps.
  static const TextStyle chip = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    color: AppColors.muted,
    fontFeatures: _figures,
  );

  /// A caption under a line: "записано 3 дня назад". 12/600.
  static const TextStyle caption = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    color: AppColors.muted,
  );

  /// A hint sentence, set in prose rather than as a label. 13/500.
  static const TextStyle hint = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 1.35,
    color: AppColors.muted,
  );

  /// The heading inside a card: "ЖИЗНЬ ЗАДАЧИ". 13/700, upper case, tracked
  /// out.
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    letterSpacing: 0.26,
    color: AppColors.muted,
  );

  /// A bottom-bar label. 11/700 when the item is the one you are on, /600 when
  /// it is not -- the weight is the second signal after the fill, and on a
  /// phone in sunlight the fill alone is not enough.
  static const TextStyle navActive = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w700,
    fontSize: 11,
  );

  static const TextStyle navIdle = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w600,
    fontSize: 11,
  );

  /// A rail label, which has 56 px of width rather than a third of a phone.
  static const TextStyle railActive = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w700,
    fontSize: 9.5,
  );

  static const TextStyle railIdle = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w600,
    fontSize: 9.5,
  );

  /// The dictation clock and the "Слушаю" beside it.
  static const TextStyle voiceClock = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w600,
    fontSize: 17,
    color: AppColors.voiceRecordingSoft,
    fontFeatures: _figures,
  );

  static const TextStyle voiceStage = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w700,
    fontSize: 17,
    color: AppColors.voiceInk,
  );

  /// Second-plane text on the dark screen.
  static const TextStyle voiceNote = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    color: AppColors.voiceMuted,
  );
}

/// The app's one theme.
///
/// ## Why there is no dark theme any more
///
/// There never was one anybody designed: `app.dart` asked
/// `ColorScheme.fromSeed(brightness: dark)` to invent one from a seed colour,
/// and the result was a set of greys Material chose. This palette comes from the
/// app's icon and from a reference that specifies every hex; inverting it
/// automatically would produce a second, unspecified skin that nobody has
/// checked against anything, on a personal tool used by one person who has now
/// stated what it should look like.
///
/// The one dark surface in the product is the dictation screen, and it is dark
/// *on purpose and always* -- see `AppColors.voiceBackground`. It is a property
/// of that screen, not of a mode the system can flip.
ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    // `primary` is the ink, not the indigo, and that is the whole point of the
    // spec's rule: a `FilledButton` anywhere in the app picks up `primary`, and
    // if that were indigo then every filled button in the app would be painted
    // the microphone's colour. The microphone sets its own.
    primary: AppColors.ink,
    onPrimary: AppColors.onInk,
    primaryContainer: AppColors.indigoFill,
    onPrimaryContainer: AppColors.indigoInk,
    secondary: AppColors.indigo,
    onSecondary: AppColors.onInk,
    secondaryContainer: AppColors.indigoFill,
    onSecondaryContainer: AppColors.indigoInk,
    tertiary: AppColors.waitingInk,
    onTertiary: AppColors.onInk,
    tertiaryContainer: AppColors.waitingChip,
    onTertiaryContainer: AppColors.waitingInk,
    error: AppColors.alarm,
    onError: AppColors.onInk,
    errorContainer: Color(0xFFFBE7E3),
    onErrorContainer: AppColors.alarm,
    surface: AppColors.card,
    onSurface: AppColors.ink,
    surfaceContainerLowest: AppColors.card,
    surfaceContainerLow: AppColors.card,
    surfaceContainer: AppColors.background,
    surfaceContainerHigh: AppColors.background,
    surfaceContainerHighest: AppColors.background,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.lineStrong,
    outlineVariant: AppColors.line,
    shadow: Color(0x141B2050),
    scrim: Color(0x801B2050),
    inverseSurface: AppColors.ink,
    onInverseSurface: AppColors.onInk,
    inversePrimary: AppColors.indigoFill,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppFonts.text,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    dividerColor: AppColors.line,

    // Material's default is a ripple that spreads across a whole card. These
    // rows are 56 px tall and packed 10 px apart; a splash that overshoots the
    // rounded corner reads as the wrong row lighting up.
    splashFactory: InkSparkle.splashFactory,

    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 1,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.card,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.screen,
    ),

    textTheme: _textTheme,

    iconTheme: const IconThemeData(color: AppColors.muted, size: 21),

    cardTheme: CardThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: AppColors.line),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.onInk,
        // The floor, applied once here so no screen has to remember it.
        minimumSize: const Size(0, Targets.minimum),
        textStyle: AppText.action,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.row),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.card,
        minimumSize: const Size(0, Targets.minimum),
        textStyle: AppText.action,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.row),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.indigoLink,
        minimumSize: const Size(0, Targets.minimum),
        textStyle: AppText.action,
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.muted,
        minimumSize: const Size(Targets.minimum, Targets.minimum),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      hintStyle: AppText.body.copyWith(color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.row),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.row),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.row),
        borderSide: const BorderSide(color: AppColors.indigoLink, width: 1.5),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: AppText.body.copyWith(color: AppColors.onInk),
      actionTextColor: AppColors.voiceBright,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.row),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: AppText.screenTight,
      contentTextStyle: AppText.body,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.panel),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      textStyle: AppText.body.copyWith(color: AppColors.ink),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.row),
        side: const BorderSide(color: AppColors.line),
      ),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.indigo,
      linearTrackColor: AppColors.indigoFill,
      circularTrackColor: AppColors.indigoFill,
    ),

    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.muted,
      textColor: AppColors.ink,
      titleTextStyle: AppText.body,
    ),
  );
}

/// [AppText] mapped onto Material's thirteen slots, for the widgets that read
/// the slots rather than the names -- dialogs, the date picker, snackbars.
const TextTheme _textTheme = TextTheme(
  displayLarge: AppText.mode,
  displayMedium: AppText.mode,
  displaySmall: AppText.modeWide,
  headlineLarge: AppText.mode,
  headlineMedium: AppText.screen,
  headlineSmall: AppText.screenTight,
  titleLarge: AppText.screen,
  titleMedium: AppText.projectName,
  titleSmall: AppText.action,
  bodyLarge: AppText.taskTitle,
  bodyMedium: AppText.body,
  bodySmall: AppText.hint,
  labelLarge: AppText.action,
  labelMedium: AppText.chip,
  labelSmall: AppText.caption,
);
