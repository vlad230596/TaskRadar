import 'package:flutter/material.dart';

import '../screens/contour_edit_screen.dart';
import '../screens/contours_screen.dart';
import '../screens/goal_screen.dart';
import '../screens/goals_screen.dart';

/// Where goals and contours live (`design/goals-ideas-spec.md`, пп. 5, 9).
/// Plain pushes rather than named routes: nothing outside the app links here.

/// The goals screen, on the tab of [contourId] (the active contour when null).
Future<void> openGoals(BuildContext context, {String? contourId}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GoalsScreen(contourId: contourId),
      ),
    );

/// One goal (`Goal-Edit.html`).
Future<void> openGoal(BuildContext context, String goalId) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => GoalScreen(goalId: goalId)),
    );

/// A new goal in [contourId], with the title in focus.
Future<void> openNewGoal(
  BuildContext context, {
  required String contourId,
  String? title,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => GoalScreen(newInContourId: contourId, initialTitle: title),
  ),
);

/// Settings → Contours.
Future<void> openContours(BuildContext context) => Navigator.of(context)
    .push<void>(MaterialPageRoute<void>(builder: (_) => const ContoursScreen()));

/// One contour, or a new one when [contourId] is null.
Future<void> openContour(BuildContext context, {String? contourId}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ContourEditScreen(contourId: contourId),
      ),
    );
