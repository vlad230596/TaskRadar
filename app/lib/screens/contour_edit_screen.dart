import 'package:flutter/material.dart';

/// One contour (`design/reference/Contour-Edit.html`). Placeholder.
class ContourEditScreen extends StatelessWidget {
  const ContourEditScreen({this.contourId, super.key});

  /// Null for a new contour.
  final String? contourId;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Контур')));
}
