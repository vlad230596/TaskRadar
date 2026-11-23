import 'package:flutter/material.dart';

/// One goal. Placeholder.
class GoalScreen extends StatelessWidget {
  const GoalScreen({
    this.goalId,
    this.newInContourId,
    this.initialTitle,
    super.key,
  });

  final String? goalId;
  final String? newInContourId;
  final String? initialTitle;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Цель')));
}
