import 'api_exception.dart';

/// Turns an [ApiException] into something a person can act on.
///
/// Moved here from the board screen in F3, unchanged, because F3 is where the
/// app gained a second and third place that has to say why a request failed --
/// and the distinction being made is worth making identically everywhere.
///
/// That distinction is the one [NetworkException] exists for: "your phone cannot
/// reach the server" and "the server answered with an error" have completely
/// different next steps, and collapsing them into "ошибка" is how people end up
/// rebooting routers over a 500.
///
/// It matters more for writes than for reads. The plan is explicit that there is
/// no offline editing: a write with no network must fail loudly and roll back.
/// The only thing that makes that acceptable rather than baffling is the
/// message saying *which* of the two happened -- "нет связи" means "try again in
/// a minute", and "сервер ответил 409" means "something is actually wrong".
String describeApiError(Object error) => switch (error) {
  NetworkException() => 'Нет связи с сервером.',
  ApiException(:final statusCode, :final message) =>
    'Сервер ответил ошибкой $statusCode: $message',
  _ => error.toString(),
};
