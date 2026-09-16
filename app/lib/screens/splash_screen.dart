import 'package:flutter/material.dart';

/// Shown for the duration of the startup session probe.
///
/// Deliberately not a branded splash: the native launch screen already covered
/// the process start, and this only has to fill the gap while `GET /auth/me`
/// is in flight -- usually a few hundred milliseconds. Anything more elaborate
/// would flash.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
