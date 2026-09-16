import 'package:flutter/widgets.dart';

/// The one number that decides between the phone layout and the desktop one
/// (F6).
///
/// ## Why a single breakpoint, and why 840
///
/// `../../../flutter-migration-plan.md` asks for two layouts and exactly two:
/// the original product sketch ("колонка = проект, линия задач сверху вниз") on
/// a wide screen, and F2's vertical list of cards on a narrow one. So this is a
/// boolean, not a set of size classes -- there is no third layout for a tablet
/// to fall into, and inventing one would be inventing work.
///
/// 840 is Material 3's "expanded" boundary, which is the number the rest of the
/// framework already uses to mean "there is room for more than one pane". Two
/// things follow from it that are worth stating, because both are the point
/// rather than a side effect:
///
/// - **A landscape phone stays on the phone layout.** A typical handset is
///   ~850x390 logical pixels on its side: wide enough to lay out three columns
///   and far too short to read them, and the thumb that is holding it still
///   wants the vertical list. The old React client drew the same line at 680px
///   and, being a browser, never had to think about it again; a Flutter app on
///   a foldable does.
/// - **A narrowed desktop window stays on the desktop layout only while it
///   earns it.** The window is resizable, the layout follows it, and a window
///   dragged down to half a screen becomes the phone layout rather than three
///   unreadably thin columns.
///
/// It deliberately reads the *window*, not the widget it is called from. Both
/// callers (`../screens/board_screen.dart`, `../screens/project_screen.dart`)
/// are full screens, and asking the window means a nested `LayoutBuilder` in
/// some parent cannot quietly flip one screen into the other layout.
const double kWideLayoutBreakpoint = 840;

/// True when there is room for the desktop layout. See
/// [kWideLayoutBreakpoint].
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
