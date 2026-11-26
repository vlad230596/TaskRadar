import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/shell_providers.dart';
import 'app_routes.dart';

/// Opens «История» with the review card on top (`design/today-history-spec.md`
/// §10.8): the review push lands here, not straight in the flow -- the owner
/// may have opened the notification on the go.
void openReviewCard(ProviderContainer container) {
  // Back to the shell first: the push may come over a project or the editor.
  appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  unawaited(container.read(shellModeProvider.notifier).select(AppMode.history));
}
