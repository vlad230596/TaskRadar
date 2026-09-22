// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Данные режима «История» и журнал одной задачи (F13).
///
/// ## Почему здесь нет кеша на диске, в отличие от доски
///
/// Доска — это то, ради чего приложение открывают без сети: снимок на диске
/// существует, чтобы в лифте было видно, что надо сделать. История — это ответ
/// на «как оно шло», и он никогда не бывает срочным. Показывать вчерашние
/// столбики как сегодняшние ради экрана, который смотрят раз в неделю, — это
/// вся сложность снимка (схема, версия, устаревание) ради единственного
/// результата: неверных чисел без предупреждения.
///
/// ## Почему обёртки API объявлены здесь, а не в `dependencies.dart`
///
/// Только чтобы не трогать общий файл: в дереве параллельно идёт вторая
/// итерация. По смыслу им место рядом с `projectApi` — это такие же
/// `keepAlive`-обёртки над общим `ApiClient`, — и переезд туда ничего не меняет
/// ни в одном вызывающем.

@ProviderFor(historyApi)
final historyApiProvider = HistoryApiProvider._();

/// Данные режима «История» и журнал одной задачи (F13).
///
/// ## Почему здесь нет кеша на диске, в отличие от доски
///
/// Доска — это то, ради чего приложение открывают без сети: снимок на диске
/// существует, чтобы в лифте было видно, что надо сделать. История — это ответ
/// на «как оно шло», и он никогда не бывает срочным. Показывать вчерашние
/// столбики как сегодняшние ради экрана, который смотрят раз в неделю, — это
/// вся сложность снимка (схема, версия, устаревание) ради единственного
/// результата: неверных чисел без предупреждения.
///
/// ## Почему обёртки API объявлены здесь, а не в `dependencies.dart`
///
/// Только чтобы не трогать общий файл: в дереве параллельно идёт вторая
/// итерация. По смыслу им место рядом с `projectApi` — это такие же
/// `keepAlive`-обёртки над общим `ApiClient`, — и переезд туда ничего не меняет
/// ни в одном вызывающем.

final class HistoryApiProvider
    extends $FunctionalProvider<HistoryApi, HistoryApi, HistoryApi>
    with $Provider<HistoryApi> {
  /// Данные режима «История» и журнал одной задачи (F13).
  ///
  /// ## Почему здесь нет кеша на диске, в отличие от доски
  ///
  /// Доска — это то, ради чего приложение открывают без сети: снимок на диске
  /// существует, чтобы в лифте было видно, что надо сделать. История — это ответ
  /// на «как оно шло», и он никогда не бывает срочным. Показывать вчерашние
  /// столбики как сегодняшние ради экрана, который смотрят раз в неделю, — это
  /// вся сложность снимка (схема, версия, устаревание) ради единственного
  /// результата: неверных чисел без предупреждения.
  ///
  /// ## Почему обёртки API объявлены здесь, а не в `dependencies.dart`
  ///
  /// Только чтобы не трогать общий файл: в дереве параллельно идёт вторая
  /// итерация. По смыслу им место рядом с `projectApi` — это такие же
  /// `keepAlive`-обёртки над общим `ApiClient`, — и переезд туда ничего не меняет
  /// ни в одном вызывающем.
  HistoryApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'historyApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyApiHash();

  @$internal
  @override
  $ProviderElement<HistoryApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HistoryApi create(Ref ref) {
    return historyApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HistoryApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HistoryApi>(value),
    );
  }
}

String _$historyApiHash() => r'1c796a443fadccd9d0b6175194436a160bfa429b';

@ProviderFor(taskEventsApi)
final taskEventsApiProvider = TaskEventsApiProvider._();

final class TaskEventsApiProvider
    extends $FunctionalProvider<TaskEventsApi, TaskEventsApi, TaskEventsApi>
    with $Provider<TaskEventsApi> {
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

/// Выбранный диапазон: неделя, месяц, всё время.
///
/// Неделя по умолчанию, хотя сервер по умолчанию отдаёт месяц. Это не разнобой:
/// умолчание схемы — для curl, а экран открывают с вопросом «как прошла эта
/// неделя», и эталон (`design/reference/History.html`) подписывает кнопку «7
/// дней». Клиент всегда присылает `range` явно, так что серверное умолчание с
/// этим выбором и не встречается.
///
/// Выбор живёт до конца запуска и не пишется в настройки: в отличие от
/// «списком/плитками» это не то, как человеку удобно смотреть, а вопрос, с
/// которым он сюда пришёл сегодня.

@ProviderFor(HistoryRangeChoice)
final historyRangeChoiceProvider = HistoryRangeChoiceProvider._();

/// Выбранный диапазон: неделя, месяц, всё время.
///
/// Неделя по умолчанию, хотя сервер по умолчанию отдаёт месяц. Это не разнобой:
/// умолчание схемы — для curl, а экран открывают с вопросом «как прошла эта
/// неделя», и эталон (`design/reference/History.html`) подписывает кнопку «7
/// дней». Клиент всегда присылает `range` явно, так что серверное умолчание с
/// этим выбором и не встречается.
///
/// Выбор живёт до конца запуска и не пишется в настройки: в отличие от
/// «списком/плитками» это не то, как человеку удобно смотреть, а вопрос, с
/// которым он сюда пришёл сегодня.
final class HistoryRangeChoiceProvider
    extends $NotifierProvider<HistoryRangeChoice, HistoryRange> {
  /// Выбранный диапазон: неделя, месяц, всё время.
  ///
  /// Неделя по умолчанию, хотя сервер по умолчанию отдаёт месяц. Это не разнобой:
  /// умолчание схемы — для curl, а экран открывают с вопросом «как прошла эта
  /// неделя», и эталон (`design/reference/History.html`) подписывает кнопку «7
  /// дней». Клиент всегда присылает `range` явно, так что серверное умолчание с
  /// этим выбором и не встречается.
  ///
  /// Выбор живёт до конца запуска и не пишется в настройки: в отличие от
  /// «списком/плитками» это не то, как человеку удобно смотреть, а вопрос, с
  /// которым он сюда пришёл сегодня.
  HistoryRangeChoiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'historyRangeChoiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyRangeChoiceHash();

  @$internal
  @override
  HistoryRangeChoice create() => HistoryRangeChoice();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HistoryRange value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HistoryRange>(value),
    );
  }
}

String _$historyRangeChoiceHash() =>
    r'834b2dac214fd6c6ae6ce041ddfcb5eaeb89cd91';

/// Выбранный диапазон: неделя, месяц, всё время.
///
/// Неделя по умолчанию, хотя сервер по умолчанию отдаёт месяц. Это не разнобой:
/// умолчание схемы — для curl, а экран открывают с вопросом «как прошла эта
/// неделя», и эталон (`design/reference/History.html`) подписывает кнопку «7
/// дней». Клиент всегда присылает `range` явно, так что серверное умолчание с
/// этим выбором и не встречается.
///
/// Выбор живёт до конца запуска и не пишется в настройки: в отличие от
/// «списком/плитками» это не то, как человеку удобно смотреть, а вопрос, с
/// которым он сюда пришёл сегодня.

abstract class _$HistoryRangeChoice extends $Notifier<HistoryRange> {
  HistoryRange build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<HistoryRange, HistoryRange>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HistoryRange, HistoryRange>,
              HistoryRange,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// `GET /history` для выбранного диапазона.
///
/// `watch` на диапазон, а не `read`: смена диапазона — это и есть новый
/// запрос, и написать её как «сменить состояние и не забыть перезапросить»
/// значило бы завести второе место, которое обязано об этом помнить.
///
/// Автоповтор выключен ([noAutomaticRetry]) по той же причине, что и у доски:
/// у пользователя есть явный повтор — жест и кнопка, — а невидимый на тридцать
/// восемь секунд поверх него делает видимый похожим на сломанный.

@ProviderFor(HistoryFeed)
final historyFeedProvider = HistoryFeedProvider._();

/// `GET /history` для выбранного диапазона.
///
/// `watch` на диапазон, а не `read`: смена диапазона — это и есть новый
/// запрос, и написать её как «сменить состояние и не забыть перезапросить»
/// значило бы завести второе место, которое обязано об этом помнить.
///
/// Автоповтор выключен ([noAutomaticRetry]) по той же причине, что и у доски:
/// у пользователя есть явный повтор — жест и кнопка, — а невидимый на тридцать
/// восемь секунд поверх него делает видимый похожим на сломанный.
final class HistoryFeedProvider
    extends $AsyncNotifierProvider<HistoryFeed, HistorySnapshot> {
  /// `GET /history` для выбранного диапазона.
  ///
  /// `watch` на диапазон, а не `read`: смена диапазона — это и есть новый
  /// запрос, и написать её как «сменить состояние и не забыть перезапросить»
  /// значило бы завести второе место, которое обязано об этом помнить.
  ///
  /// Автоповтор выключен ([noAutomaticRetry]) по той же причине, что и у доски:
  /// у пользователя есть явный повтор — жест и кнопка, — а невидимый на тридцать
  /// восемь секунд поверх него делает видимый похожим на сломанный.
  HistoryFeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'historyFeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyFeedHash();

  @$internal
  @override
  HistoryFeed create() => HistoryFeed();
}

String _$historyFeedHash() => r'09623131b1c270c1d0ec89c0a916ee98eaabcafb';

/// `GET /history` для выбранного диапазона.
///
/// `watch` на диапазон, а не `read`: смена диапазона — это и есть новый
/// запрос, и написать её как «сменить состояние и не забыть перезапросить»
/// значило бы завести второе место, которое обязано об этом помнить.
///
/// Автоповтор выключен ([noAutomaticRetry]) по той же причине, что и у доски:
/// у пользователя есть явный повтор — жест и кнопка, — а невидимый на тридцать
/// восемь секунд поверх него делает видимый похожим на сломанный.

abstract class _$HistoryFeed extends $AsyncNotifier<HistorySnapshot> {
  FutureOr<HistorySnapshot> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<HistorySnapshot>, HistorySnapshot>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<HistorySnapshot>, HistorySnapshot>,
              AsyncValue<HistorySnapshot>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

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
