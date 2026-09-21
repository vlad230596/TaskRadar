import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The work mode: the two-to-five tasks actually in hand, one of them large.
///
/// ## Why this is empty in F12 and that is the plan rather than an omission
///
/// The set is a server-side fact -- `Task.focusedAt`, added by F11 -- because
/// it is assembled on the desktop and worked through from the phone. There is
/// no honest way to draw this mode from what the client has today: deriving "in
/// work" from the current task of every project would invent a set nobody
/// chose, and it would be a different set tomorrow.
///
/// So the mode exists, is reachable, and says what it is waiting for. That is
/// deliberately not nothing: the navigation, the remembered mode and the shell
/// are the parts of F12 that F13 builds on, and they are only testable if all
/// three buttons lead somewhere.
class WorkScreen extends StatelessWidget {
  const WorkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _NotYet(
      icon: Icons.adjust,
      title: 'Набор ещё не собирается',
      body:
          'Здесь будут 2–5 задач, взятых в работу: одна крупно, остальные '
          'следом. Набор живёт на сервере — он собирается за столом и '
          'отрабатывается с телефона, — и появится вместе с ним.',
    );
  }
}

/// The shared "this mode is waiting for its data" panel.
class _NotYet extends StatelessWidget {
  const _NotYet({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: AppColors.lineStrong),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: AppText.projectName),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: AppText.hint),
          ],
        ),
      ),
    );
  }
}

/// Reused by the history mode, which is waiting for the same iteration.
class ModeNotYet extends StatelessWidget {
  const ModeNotYet({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) =>
      _NotYet(icon: icon, title: title, body: body);
}
