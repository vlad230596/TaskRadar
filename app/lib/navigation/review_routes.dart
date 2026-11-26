import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/outbox_providers.dart';
import '../providers/shell_providers.dart';
import 'app_routes.dart';

/// The two tabs of «История» (`design/today-history-spec.md` §9.1). Always
/// opens on «Сделано»; the review's «Пересмотр записан · Недели» switches to
/// «Недели».
enum HistoryTab { done, weeks }

class HistoryTabChoice extends Notifier<HistoryTab> {
  @override
  HistoryTab build() => HistoryTab.done;

  void select(HistoryTab tab) {
    if (state != tab) state = tab;
  }
}

final NotifierProvider<HistoryTabChoice, HistoryTab> historyTabProvider =
    NotifierProvider<HistoryTabChoice, HistoryTab>(HistoryTabChoice.new);

/// Where a review left off when it was closed before «Записать» (§10.1, 6):
/// the step and the steps skipped. Kept for this run of the app, until the
/// review is recorded -- the actions taken in the steps are real edits and
/// already saved, only the place in the flow is remembered.
class ReviewProgress {
  const ReviewProgress({this.step = 0, this.skipped = const <int>{}});

  final int step;
  final Set<int> skipped;
}

class ReviewProgressState extends Notifier<ReviewProgress> {
  @override
  ReviewProgress build() => const ReviewProgress();

  void save(ReviewProgress progress) => state = progress;

  void clear() => state = const ReviewProgress();
}

final NotifierProvider<ReviewProgressState, ReviewProgress>
reviewProgressProvider = NotifierProvider<ReviewProgressState, ReviewProgress>(
  ReviewProgressState.new,
);

/// The review push was tapped: «История» on «Сделано», where the card is
/// (§10.8 -- not the flow itself: the push may be opened on the go).
void openReviewCard(ProviderContainer container) {
  // Back to the shell first: the push may come over a project or the editor.
  appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  container.read(historyTabProvider.notifier).select(HistoryTab.done);
  container.read(historyShowsOutboxProvider.notifier).show(false);
  unawaited(container.read(shellModeProvider.notifier).select(AppMode.history));
}
