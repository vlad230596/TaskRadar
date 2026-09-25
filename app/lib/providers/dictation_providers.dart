import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/dictation_api.dart';
import 'board_providers.dart' show noAutomaticRetry;
import 'dependencies.dart';

part 'dictation_providers.g.dart';

/// The model the server parses dictation with (F14), for the settings screen.
///
/// Not kept alive: it is read when the settings screen opens and nowhere else,
/// and a value cached from an hour ago would be exactly the stale answer a
/// settings screen must not give.
@Riverpod(retry: noAutomaticRetry)
class DictationModelSetting extends _$DictationModelSetting {
  @override
  Future<DictationModel> build() =>
      ref.watch(dictationApiProvider).fetchModel();

  /// Saves [model], or goes back to the server's default for null. The screen
  /// shows the server's answer, not the value typed: the server normalises it
  /// (trims it, stores the default by name as "no choice").
  Future<void> choose(String? model) async {
    final saved = await ref.read(dictationApiProvider).setModel(model);
    if (ref.mounted) state = AsyncData(saved);
  }
}
