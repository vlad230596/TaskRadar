import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/dictation_api.dart';
import '../domain/ai_level.dart';
import 'board_providers.dart' show noAutomaticRetry;
import 'dependencies.dart';

part 'dictation_providers.g.dart';

/// The server's roster of models (`backend/src/domain/modelRoster.ts`), for
/// the settings.
///
/// Not kept alive: it is read when the screen opens, and health that is an
/// hour old is exactly the stale answer a settings screen must not give.
@Riverpod(retry: noAutomaticRetry)
class AiModelsSetting extends _$AiModelsSetting {
  @override
  Future<AiModels> build() => ref.watch(dictationApiProvider).fetchModels();

  /// Saves the whole list, in this order; the screen shows the server's
  /// answer, health included.
  Future<void> save(List<AiModelEntry> models) async {
    final saved = await ref.read(dictationApiProvider).saveModels(models);
    if (ref.mounted) state = AsyncData(saved);
  }

  Future<void> reenable(String id) async {
    final saved = await ref.read(dictationApiProvider).reenableModel(id);
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

/// "Отправить в несколько" (`backend/src/domain/modelRoster.ts`): parses ask
/// the first two models of the server's list at once, and the answers can be
/// switched between. Remembered between parses, as agreed; off at first.
@Riverpod(keepAlive: true)
class AiMultiSetting extends _$AiMultiSetting {
  @override
  Future<bool> build() async =>
      await ref.watch(settingsStoreProvider).readAiMulti() ?? false;

  Future<void> choose(bool multi) async {
    state = AsyncData(multi);
    await ref.read(settingsStoreProvider).writeAiMulti(multi);
  }
}
