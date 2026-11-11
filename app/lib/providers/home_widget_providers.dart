import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home_widget/home_widget_gateway.dart';

/// The home-screen widget's gateway: the real channel on Android, a no-op
/// everywhere else (Windows, web).
///
/// A plain provider rather than a generated one: it has no arguments and no
/// state, and it is the one thing tests override.
final homeWidgetGatewayProvider = Provider<HomeWidgetGateway>(
  (ref) =>
      debugHomeWidgetGatewayFactory?.call() ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? MethodChannelHomeWidgetGateway()
          : const UnsupportedHomeWidgetGateway()),
);

/// Set by `test/flutter_test_config.dart` for every test file at once.
///
/// `flutter test` reports `defaultTargetPlatform` as Android, so without this
/// every widget test that pumps the signed-in app would talk to a channel that
/// does not exist. Tests that are *about* the widget override the provider.
@visibleForTesting
HomeWidgetGateway Function()? debugHomeWidgetGatewayFactory;
