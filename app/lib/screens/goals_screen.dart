import 'package:flutter/material.dart';

/// The goals screen. Placeholder.
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({this.contourId, super.key});

  final String? contourId;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Цели')));
}
