import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The name of a mode at the top of its screen: "Планирование", "Работа",
/// "История".
///
/// ## Why this is a widget and not just `Text(..., style: AppText.mode)`
///
/// Each of these names is one word, and a `Text` that is given less width than
/// its one word breaks *inside* it -- "Планировани/е" on a 375 px phone, next
/// to the header's buttons. A mode name that wraps is worse than a smaller one:
/// the second line pushes the whole screen down and the word stops being read
/// as a name. So it never wraps; when it does not fit, it scales down to the
/// width it has, left-aligned where the full-size one would have stood.
///
/// Give it bounded width -- `Expanded`/`Flexible` in a `Row` -- or it has
/// nothing to scale against and will simply be its natural size.
class ModeTitle extends StatelessWidget {
  const ModeTitle(this.title, {this.style = AppText.mode, super.key});

  final String title;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(title, maxLines: 1, softWrap: false, style: style),
    );
  }
}
