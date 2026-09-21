import 'package:flutter/material.dart';

import '../providers/shell_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Switching between the three modes: a bar at the bottom of a phone, a rail
/// down the left of a desktop window (F12).
///
/// ## The rule these two share, and why it is a rule
///
/// *"Микрофон живёт в одном месте."* On a phone that place is the fourth item
/// of the bar, at the right-hand end, painted indigo; on the desktop it is the
/// bottom of the rail, painted the same indigo. Nothing else in the app is
/// indigo, so "the indigo thing is the microphone" is learnable in one use and
/// then never has to be looked for again.
///
/// Two consequences follow, and both are deliberate:
///
/// - **The voice item does not stretch with the other three.** It is a fixed
///   [Targets.navVoiceWidth] on the right, so adding or removing a mode cannot
///   move it. The three modes share whatever is left.
/// - **It is always there, even with no speech model installed.** A navigation
///   item that sometimes does not exist is a navigation bar whose other items
///   move -- and it used to be missing for the first frames of every cold start
///   while a disk probe ran, which is half of "запускается не с первого раза".
///   Pressing it with no model opens the dictation screen, which says so.

/// What each mode is called and drawn as in the bar.
///
/// The label differs between the two layouts for the history mode ("История" on
/// a phone, "Итоги" on the rail) because the rail gives a label 56 px and
/// "История" does not fit at 9.5 px without being squeezed. The reference pages
/// make the same choice.
extension AppModeChrome on AppMode {
  IconData get icon => switch (this) {
    // Concentric rings with a sweep line -- the app's own icon, and the one
    // Material glyph that is literally a radar.
    AppMode.plan => Icons.radar,
    // A ring with a dot in the middle: one thing, in the centre, being aimed
    // at.
    AppMode.work => Icons.adjust,
    AppMode.history => Icons.bar_chart,
  };

  String get label => switch (this) {
    AppMode.plan => 'План',
    AppMode.work => 'Работа',
    AppMode.history => 'История',
  };

  /// The rail's shorter label. See the note above.
  String get railLabel => switch (this) {
    AppMode.history => 'Итоги',
    _ => label,
  };

  /// The heading at the top of the mode itself.
  String get title => switch (this) {
    AppMode.plan => 'Планирование',
    AppMode.work => 'Работа',
    AppMode.history => 'История',
  };
}

/// The phone's bottom bar.
class ModeBar extends StatelessWidget {
  const ModeBar({
    required this.current,
    required this.onSelect,
    required this.onDictate,
    super.key,
  });

  final AppMode current;
  final ValueChanged<AppMode> onSelect;
  final VoidCallback onDictate;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: Targets.navBar,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final mode in AppMode.values) ...<Widget>[
            Expanded(
              child: _BarItem(
                icon: mode.icon,
                label: mode.label,
                active: mode == current,
                onTap: () => onSelect(mode),
              ),
            ),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: Targets.navVoiceWidth,
            child: _BarItem(
              icon: Icons.mic_none,
              label: 'Голос',
              active: true,
              voice: true,
              onTap: onDictate,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.voice = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool voice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = voice
        ? AppColors.indigo
        : active
        ? AppColors.indigoFill
        : Colors.transparent;
    final foreground = voice
        ? AppColors.onInk
        : active
        ? AppColors.indigoInk
        : AppColors.muted;

    return Semantics(
      button: true,
      selected: active && !voice,
      label: label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.card),
          child: SizedBox(
            height: Targets.navItem,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: voice ? 22 : 21, color: foreground),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: (active ? AppText.navActive : AppText.navIdle)
                      .copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The desktop's left rail.
///
/// Dark where the bar is light, because on a 1440 px window the navigation is
/// chrome around a page rather than a strip at the bottom of one -- and a white
/// rail against a white header has nothing to separate it from the content
/// except a hairline.
class ModeRail extends StatelessWidget {
  const ModeRail({
    required this.current,
    required this.onSelect,
    required this.onDictate,
    required this.onSettings,
    super.key,
  });

  final AppMode current;
  final ValueChanged<AppMode> onSelect;
  final VoidCallback onDictate;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: Targets.railWidth,
      color: AppColors.railBackground,
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 16),
      child: Column(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.indigo,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.radar,
              size: 22,
              color: AppColors.voiceBright,
            ),
          ),
          const SizedBox(height: 20),
          for (final mode in AppMode.values) ...<Widget>[
            _RailItem(
              icon: mode.icon,
              label: mode.railLabel,
              active: mode == current,
              onTap: () => onSelect(mode),
            ),
            const SizedBox(height: 10),
          ],
          const Spacer(),
          _RailItem(
            icon: Icons.mic_none,
            label: 'Голос',
            active: true,
            voice: true,
            onTap: onDictate,
          ),
          const SizedBox(height: 6),
          IconButton(
            tooltip: 'Настройки',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined, size: 21),
            color: AppColors.railMuted,
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.voice = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool voice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = voice
        ? AppColors.indigo
        : active
        ? AppColors.railActive
        : Colors.transparent;
    final foreground = voice || active ? AppColors.onInk : AppColors.railMuted;

    return Semantics(
      button: true,
      selected: active && !voice,
      label: label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(Radii.stub),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.stub),
          child: SizedBox(
            width: Targets.railItem,
            height: Targets.railItem,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 22, color: foreground),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: (active ? AppText.railActive : AppText.railIdle)
                      .copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The microphone on a sub-screen: a 56x56 indigo square in the bottom-right
/// corner.
///
/// Same colour and same corner on the task screen, the sandbox and a project,
/// so the thumb finds it without the eye. It is a square rather than Material's
/// round FAB because the rest of this language is squares with 14-20 px corners
/// and a circle would read as borrowed from another app.
class MicrophoneSquare extends StatelessWidget {
  const MicrophoneSquare({
    required this.onPressed,
    this.tooltip = 'Продиктовать',
    super.key,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(Radii.stub),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Radii.stub),
          child: const SizedBox(
            width: Targets.microphone,
            height: Targets.microphone,
            child: Icon(Icons.mic_none, size: 25, color: AppColors.onInk),
          ),
        ),
      ),
    );
  }
}
