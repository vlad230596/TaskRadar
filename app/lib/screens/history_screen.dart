import 'package:flutter/material.dart';

import 'work_screen.dart';

/// The history mode: what has been closed, and what has been hanging around.
///
/// ## Why this is empty in F12
///
/// Same reason as the work mode, and a sharper one. "Закрыто на этой неделе" is
/// answerable from `updatedAt` alone and would look right; "висит дольше всего"
/// is not -- it needs the event journal (`task_events`) that F11 adds, because
/// the two timestamps a task carries cannot say how long it spent *blocked*.
///
/// Drawing half of the mode from the data that exists would be the worst of the
/// three options: a screen that is right about the easy half and quietly wrong
/// about the half the mode exists for. The task screen's "жизнь задачи" takes
/// the other approach -- it draws only what is derivable and is shaped so the
/// journal drops into it -- because there it is one section of a screen that is
/// useful without it. Here it would be the whole screen.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModeNotYet(
      icon: Icons.bar_chart,
      title: 'Итогов пока нет',
      body:
          'Здесь будет неделя столбиками, что закрыто и что висит дольше '
          'всего. Последнее считается по журналу переходов задачи — пока его '
          'нет, показывать было бы нечестно.',
    );
  }
}
