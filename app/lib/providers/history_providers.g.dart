// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Журнал одной задачи — для блока «жизнь задачи» в редакторе (F13).
///
/// Сводки режима «История» (`/history/done`, `/history/weeks`, пересмотр)
/// живут в `today_providers.dart`; старый `GET /history` приложение больше
/// не зовёт (сервер держит его для старых версий).

@ProviderFor(taskEventsApi)
final taskEventsApiProvider = TaskEventsApiProvider._();

/// Журнал одной задачи — для блока «жизнь задачи» в редакторе (F13).
///
/// Сводки режима «История» (`/history/done`, `/history/weeks`, пересмотр)
/// живут в `today_providers.dart`; старый `GET /history` приложение больше
/// не зовёт (сервер держит его для старых версий).

final class TaskEventsApiProvider
    extends $FunctionalProvider<TaskEventsApi, TaskEventsApi, TaskEventsApi>
    with $Provider<TaskEventsApi> {
  /// Журнал одной задачи — для блока «жизнь задачи» в редакторе (F13).
  ///
  /// Сводки режима «История» (`/history/done`, `/history/weeks`, пересмотр)
  /// живут в `today_providers.dart`; старый `GET /history` приложение больше
  /// не зовёт (сервер держит его для старых версий).
  TaskEventsApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'taskEventsApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$taskEventsApiHash();

  @$internal
  @override
  $ProviderElement<TaskEventsApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TaskEventsApi create(Ref ref) {
    return taskEventsApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TaskEventsApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TaskEventsApi>(value),
    );
  }
}

String _$taskEventsApiHash() => r'e08e68dbfad9f524b851e6075720e1c0fadc2379';

/// Журнал одной задачи для блока «жизнь задачи».
///
/// Семейство и **не** `keepAlive`: журнал нужен, пока открыт экран этой задачи,
/// и держать в памяти историю каждой задачи, которую за день открыли, — это
/// кеш без единого читателя. Пере-открытие задачи стоит одного запроса к
/// роуту, который отдаёт десяток строк по индексу `[taskId, at]`.
///
/// Автоповтор выключен по той же причине, что и у [HistoryFeed]: блок сам
/// говорит, что журнал не прочитался, и остальной экран задачи при этом
/// полностью рабочий.

@ProviderFor(taskEvents)
final taskEventsProvider = TaskEventsFamily._();

/// Журнал одной задачи для блока «жизнь задачи».
///
/// Семейство и **не** `keepAlive`: журнал нужен, пока открыт экран этой задачи,
/// и держать в памяти историю каждой задачи, которую за день открыли, — это
/// кеш без единого читателя. Пере-открытие задачи стоит одного запроса к
/// роуту, который отдаёт десяток строк по индексу `[taskId, at]`.
///
/// Автоповтор выключен по той же причине, что и у [HistoryFeed]: блок сам
/// говорит, что журнал не прочитался, и остальной экран задачи при этом
/// полностью рабочий.

final class TaskEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TaskEvent>>,
          List<TaskEvent>,
          FutureOr<List<TaskEvent>>
        >
    with $FutureModifier<List<TaskEvent>>, $FutureProvider<List<TaskEvent>> {
  /// Журнал одной задачи для блока «жизнь задачи».
  ///
  /// Семейство и **не** `keepAlive`: журнал нужен, пока открыт экран этой задачи,
  /// и держать в памяти историю каждой задачи, которую за день открыли, — это
  /// кеш без единого читателя. Пере-открытие задачи стоит одного запроса к
  /// роуту, который отдаёт десяток строк по индексу `[taskId, at]`.
  ///
  /// Автоповтор выключен по той же причине, что и у [HistoryFeed]: блок сам
  /// говорит, что журнал не прочитался, и остальной экран задачи при этом
  /// полностью рабочий.
  TaskEventsProvider._({
    required TaskEventsFamily super.from,
    required String super.argument,
  }) : super(
         retry: noAutomaticRetry,
         name: r'taskEventsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$taskEventsHash();

  @override
  String toString() {
    return r'taskEventsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<TaskEvent>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<TaskEvent>> create(Ref ref) {
    final argument = this.argument as String;
    return taskEvents(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TaskEventsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$taskEventsHash() => r'e5c520ff1980d787963ceb3bcccdecb3a9aeaa69';

/// Журнал одной задачи для блока «жизнь задачи».
///
/// Семейство и **не** `keepAlive`: журнал нужен, пока открыт экран этой задачи,
/// и держать в памяти историю каждой задачи, которую за день открыли, — это
/// кеш без единого читателя. Пере-открытие задачи стоит одного запроса к
/// роуту, который отдаёт десяток строк по индексу `[taskId, at]`.
///
/// Автоповтор выключен по той же причине, что и у [HistoryFeed]: блок сам
/// говорит, что журнал не прочитался, и остальной экран задачи при этом
/// полностью рабочий.

final class TaskEventsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<TaskEvent>>, String> {
  TaskEventsFamily._()
    : super(
        retry: noAutomaticRetry,
        name: r'taskEventsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Журнал одной задачи для блока «жизнь задачи».
  ///
  /// Семейство и **не** `keepAlive`: журнал нужен, пока открыт экран этой задачи,
  /// и держать в памяти историю каждой задачи, которую за день открыли, — это
  /// кеш без единого читателя. Пере-открытие задачи стоит одного запроса к
  /// роуту, который отдаёт десяток строк по индексу `[taskId, at]`.
  ///
  /// Автоповтор выключен по той же причине, что и у [HistoryFeed]: блок сам
  /// говорит, что журнал не прочитался, и остальной экран задачи при этом
  /// полностью рабочий.

  TaskEventsProvider call(String taskId) =>
      TaskEventsProvider._(argument: taskId, from: this);

  @override
  String toString() => r'taskEventsProvider';
}
