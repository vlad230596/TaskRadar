// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'focus_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Роуты набора. Здесь, а не в `dependencies.dart`, по той же причине, по какой
/// `FocusApi` вообще отдельный класс: это один режим, и его зависимости удобнее
/// читать рядом с ним.

@ProviderFor(focusApi)
final focusApiProvider = FocusApiProvider._();

/// Роуты набора. Здесь, а не в `dependencies.dart`, по той же причине, по какой
/// `FocusApi` вообще отдельный класс: это один режим, и его зависимости удобнее
/// читать рядом с ним.

final class FocusApiProvider
    extends $FunctionalProvider<FocusApi, FocusApi, FocusApi>
    with $Provider<FocusApi> {
  /// Роуты набора. Здесь, а не в `dependencies.dart`, по той же причине, по какой
  /// `FocusApi` вообще отдельный класс: это один режим, и его зависимости удобнее
  /// читать рядом с ним.
  FocusApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'focusApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$focusApiHash();

  @$internal
  @override
  $ProviderElement<FocusApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FocusApi create(Ref ref) {
    return focusApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FocusApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FocusApi>(value),
    );
  }
}

String _$focusApiHash() => r'27a1a35c2e54d31f2f4db70adc902c5a37b6cbb5';

/// Сам набор: `GET /focus`, и три записи, которые его меняют.
///
/// `keepAlive`, потому что набор смотрят сразу два места — режим работы и
/// полоска «В работе» на планировании, — и они живут в `IndexedStack`
/// одновременно. Автодиспоуз здесь означал бы перезапрос на каждое переключение
/// режима.
///
/// Автоповтор выключен ([noAutomaticRetry]) ровно по тем же причинам, что у
/// доски: у пользователя есть явный повтор, а невидимый на 38 секунд делает
/// видимый похожим на сломанный.

@ProviderFor(FocusSet)
final focusSetProvider = FocusSetProvider._();

/// Сам набор: `GET /focus`, и три записи, которые его меняют.
///
/// `keepAlive`, потому что набор смотрят сразу два места — режим работы и
/// полоска «В работе» на планировании, — и они живут в `IndexedStack`
/// одновременно. Автодиспоуз здесь означал бы перезапрос на каждое переключение
/// режима.
///
/// Автоповтор выключен ([noAutomaticRetry]) ровно по тем же причинам, что у
/// доски: у пользователя есть явный повтор, а невидимый на 38 секунд делает
/// видимый похожим на сломанный.
final class FocusSetProvider
    extends $AsyncNotifierProvider<FocusSet, List<FocusTask>> {
  /// Сам набор: `GET /focus`, и три записи, которые его меняют.
  ///
  /// `keepAlive`, потому что набор смотрят сразу два места — режим работы и
  /// полоска «В работе» на планировании, — и они живут в `IndexedStack`
  /// одновременно. Автодиспоуз здесь означал бы перезапрос на каждое переключение
  /// режима.
  ///
  /// Автоповтор выключен ([noAutomaticRetry]) ровно по тем же причинам, что у
  /// доски: у пользователя есть явный повтор, а невидимый на 38 секунд делает
  /// видимый похожим на сломанный.
  FocusSetProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'focusSetProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$focusSetHash();

  @$internal
  @override
  FocusSet create() => FocusSet();
}

String _$focusSetHash() => r'402b61708850ecba89c7ae12042bb2f1d6e93c5c';

/// Сам набор: `GET /focus`, и три записи, которые его меняют.
///
/// `keepAlive`, потому что набор смотрят сразу два места — режим работы и
/// полоска «В работе» на планировании, — и они живут в `IndexedStack`
/// одновременно. Автодиспоуз здесь означал бы перезапрос на каждое переключение
/// режима.
///
/// Автоповтор выключен ([noAutomaticRetry]) ровно по тем же причинам, что у
/// доски: у пользователя есть явный повтор, а невидимый на 38 секунд делает
/// видимый похожим на сломанный.

abstract class _$FocusSet extends $AsyncNotifier<List<FocusTask>> {
  FutureOr<List<FocusTask>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<FocusTask>>, List<FocusTask>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<FocusTask>>, List<FocusTask>>,
              AsyncValue<List<FocusTask>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Id задач, которые сейчас в наборе.
///
/// Отдельный провайдер, потому что строке задачи в проекте нужен ровно этот
/// вопрос — «я в наборе?» — и ничего больше. Пока набор не загружен, множество
/// пустое: это честнее, чем показывать кнопку «взять в работу» нажатой на
/// основании того, чего мы ещё не знаем.
///
/// Это набор **активного** контура: задача из набора другого контура для
/// строки проекта «не в работе» — взять её значит перенести сюда.

@ProviderFor(focusedTaskIds)
final focusedTaskIdsProvider = FocusedTaskIdsProvider._();

/// Id задач, которые сейчас в наборе.
///
/// Отдельный провайдер, потому что строке задачи в проекте нужен ровно этот
/// вопрос — «я в наборе?» — и ничего больше. Пока набор не загружен, множество
/// пустое: это честнее, чем показывать кнопку «взять в работу» нажатой на
/// основании того, чего мы ещё не знаем.
///
/// Это набор **активного** контура: задача из набора другого контура для
/// строки проекта «не в работе» — взять её значит перенести сюда.

final class FocusedTaskIdsProvider
    extends $FunctionalProvider<Set<String>, Set<String>, Set<String>>
    with $Provider<Set<String>> {
  /// Id задач, которые сейчас в наборе.
  ///
  /// Отдельный провайдер, потому что строке задачи в проекте нужен ровно этот
  /// вопрос — «я в наборе?» — и ничего больше. Пока набор не загружен, множество
  /// пустое: это честнее, чем показывать кнопку «взять в работу» нажатой на
  /// основании того, чего мы ещё не знаем.
  ///
  /// Это набор **активного** контура: задача из набора другого контура для
  /// строки проекта «не в работе» — взять её значит перенести сюда.
  FocusedTaskIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'focusedTaskIdsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$focusedTaskIdsHash();

  @$internal
  @override
  $ProviderElement<Set<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Set<String> create(Ref ref) {
    return focusedTaskIds(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$focusedTaskIdsHash() => r'ee5fb0a00b1908bf47c97c7c56d2e5a376dd0dab';

/// Id задач из наборов **всех** контуров — для тёплого возраста: задача в
/// работе остаётся «в работе», в каком бы контуре её ни взяли.

@ProviderFor(anyFocusedTaskIds)
final anyFocusedTaskIdsProvider = AnyFocusedTaskIdsProvider._();

/// Id задач из наборов **всех** контуров — для тёплого возраста: задача в
/// работе остаётся «в работе», в каком бы контуре её ни взяли.

final class AnyFocusedTaskIdsProvider
    extends $FunctionalProvider<Set<String>, Set<String>, Set<String>>
    with $Provider<Set<String>> {
  /// Id задач из наборов **всех** контуров — для тёплого возраста: задача в
  /// работе остаётся «в работе», в каком бы контуре её ни взяли.
  AnyFocusedTaskIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'anyFocusedTaskIdsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$anyFocusedTaskIdsHash();

  @$internal
  @override
  $ProviderElement<Set<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Set<String> create(Ref ref) {
    return anyFocusedTaskIds(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$anyFocusedTaskIdsHash() => r'0268454762a729429c9cd6d5d274ba12adbdedc4';

/// Набор активного контура (`design/goals-ideas-contract.md`: «у каждого
/// контура свой рабочий набор»).
///
/// `GET /focus` читается целиком (все контуры), а делится здесь: переключение
/// контура тогда не стоит запроса, и строка без контура (взятая старым
/// сервером) попадает в набор контура по умолчанию — как и на сервере.
/// Контуры неизвестны — весь набор, как до контуров.

@ProviderFor(activeFocusSet)
final activeFocusSetProvider = ActiveFocusSetProvider._();

/// Набор активного контура (`design/goals-ideas-contract.md`: «у каждого
/// контура свой рабочий набор»).
///
/// `GET /focus` читается целиком (все контуры), а делится здесь: переключение
/// контура тогда не стоит запроса, и строка без контура (взятая старым
/// сервером) попадает в набор контура по умолчанию — как и на сервере.
/// Контуры неизвестны — весь набор, как до контуров.

final class ActiveFocusSetProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FocusTask>>,
          AsyncValue<List<FocusTask>>,
          AsyncValue<List<FocusTask>>
        >
    with $Provider<AsyncValue<List<FocusTask>>> {
  /// Набор активного контура (`design/goals-ideas-contract.md`: «у каждого
  /// контура свой рабочий набор»).
  ///
  /// `GET /focus` читается целиком (все контуры), а делится здесь: переключение
  /// контура тогда не стоит запроса, и строка без контура (взятая старым
  /// сервером) попадает в набор контура по умолчанию — как и на сервере.
  /// Контуры неизвестны — весь набор, как до контуров.
  ActiveFocusSetProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeFocusSetProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeFocusSetHash();

  @$internal
  @override
  $ProviderElement<AsyncValue<List<FocusTask>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<List<FocusTask>> create(Ref ref) {
    return activeFocusSet(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<List<FocusTask>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<List<FocusTask>>>(value),
    );
  }
}

String _$activeFocusSetHash() => r'5390ad701b495811f067f69b11dbe633d97a3625';
