import 'package:taskradar/storage/token_storage.dart';

/// In-memory [TokenStorage].
///
/// The real one reaches for the Android Keystore / Windows credential store
/// through a platform channel, which does not exist in the `flutter test` VM.
/// Implementing the interface (rather than faking `FlutterSecureStorage` under
/// it) also keeps the tests focused on the session logic instead of on the
/// plugin's method names.
class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage([this.token]);

  String? token;

  int readCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<String?> read() async {
    readCount++;
    return token;
  }

  @override
  Future<void> write(String token) async {
    writeCount++;
    this.token = token;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    token = null;
  }
}
