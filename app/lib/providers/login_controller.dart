import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_exception.dart';
import 'session_provider.dart';

part 'login_controller.g.dart';

/// Submission state for the login form: idle / in flight / failed.
///
/// Kept separate from [Session] on purpose. The session is a long-lived fact
/// about the app; a failed login attempt is transient UI state that belongs to
/// one screen and should disappear with it. Folding "wrong password" into the
/// session's `AsyncValue` would make the session look like it was in an error
/// state when it is simply, correctly, signed out.
@riverpod
class LoginController extends _$LoginController {
  @override
  Future<void> build() async {}

  /// Attempts a login. Never throws -- the outcome lands in [state], which the
  /// form renders as a spinner or an inline error.
  Future<void> submit({required String email, required String password}) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard<void>(
      () => ref
          .read(sessionProvider.notifier)
          .signIn(email: email.trim(), password: password),
    );
  }
}

/// Maps a login failure to the message shown under the form.
///
/// Wording copied from `frontend/src/pages/LoginPage.tsx` so the two clients say
/// the same thing while they coexist. The distinction that matters is the one
/// the user can act on: a rejected password is their problem to fix, an
/// unreachable server is not -- and on a phone, "wrong password" shown for what
/// is actually a dead Wi-Fi connection sends people off resetting credentials
/// they never got wrong.
String loginErrorMessage(Object error) {
  if (error is UnauthorizedException) {
    return 'Неверный email или пароль';
  }
  if (error is NetworkException) {
    return 'Не удалось подключиться к серверу. Попробуйте ещё раз.';
  }
  if (error is ApiException) {
    return 'Сервер ответил ошибкой: ${error.message}';
  }
  return 'Не удалось войти. Попробуйте ещё раз.';
}
