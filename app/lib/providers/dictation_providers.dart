import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/dictation_api.dart';
import '../domain/ai_level.dart';
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

/// The level AI processing starts at (`domain/ai_level.dart`), chosen in the
/// settings. Each parse screen starts from it and may move away from it for
/// one text -- "сильнее", "слабее" -- without changing it.
///
/// Like [ReminderSettings], the state is set before the write and kept if
/// the write fails: the choice holds for this session either way.
@Riverpod(keepAlive: true)
class AiLevelSetting extends _$AiLevelSetting {
  @override
  Future<int> build() async =>
      validAiLevel(await ref.watch(settingsStoreProvider).readAiLevel());

  Future<void> choose(int level) async {
    final valid = validAiLevel(level);
    state = AsyncData(valid);
    await ref.read(settingsStoreProvider).writeAiLevel(valid);
  }
}
