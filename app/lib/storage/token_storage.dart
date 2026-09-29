import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence for the session JWT.
///
/// `flutter_secure_storage` rather than `SharedPreferences`: the token is a
/// 30-day bearer credential for the whole account, and there is no session table
/// on the server to revoke it with -- the only kill switch is rotating
/// `JWT_SECRET`, which logs out every device. That makes it worth the Android
/// Keystore / Windows DPAPI round trip.
///
/// Reads are expected to be rare (once at startup); [ApiClient] keeps the token
/// in memory for the requests themselves.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  /// Namespaced so it cannot collide with anything a future feature stores.
  static const String tokenKey = 'taskradar.session_token';

  /// Which user the on-device data (board snapshot, capture queue, selected
  /// scope) belongs to. Deliberately separate from the token and *not* removed by
  /// [clear]: it has to outlive a sign-out, otherwise the next sign-in could not
  /// tell "the same person again" from "somebody else".
  static const String lastUserIdKey = 'taskradar.last_user_id';

  final FlutterSecureStorage _storage;

  /// Returns the stored token, or null if there is none.
  ///
  /// Swallows platform failures and treats them as "no token", deliberately.
  /// Secure storage genuinely can fail to decrypt on Android -- after an
  /// app-data restore onto a different device, or when the Keystore entry is
  /// invalidated by a lock-screen change -- and it does so by throwing, not by
  /// returning null. Crashing on launch because of that would leave the user
  /// with an app that cannot even reach the login screen to fix itself, whereas
  /// "you are logged out, log in again" is a recoverable, understandable state.
  /// The entry is wiped on the way out so the next launch is clean.
  Future<String?> read() async {
    try {
      final token = await _storage.read(key: tokenKey);
      return (token == null || token.isEmpty) ? null : token;
    } catch (error, stackTrace) {
      debugPrint('TokenStorage.read failed, treating as signed out: $error');
      debugPrintStack(stackTrace: stackTrace);
      await clear();
      return null;
    }
  }

  Future<void> write(String token) {
    return _storage.write(key: tokenKey, value: token);
  }

  /// Removes the token. Safe to call when there is nothing stored, and safe to
  /// call on a broken store -- logout must never be the thing that throws.
  Future<void> clear() async {
    try {
      await _storage.delete(key: tokenKey);
    } catch (error) {
      debugPrint('TokenStorage.clear failed: $error');
    }
  }

  /// The id of the user the local data belongs to, or null if unknown (a fresh
  /// install, or one from before this was tracked). Like [read], a platform
  /// failure reads as null: unknown makes the caller wipe, which is the safe side.
  Future<String?> readLastUserId() async {
    try {
      final id = await _storage.read(key: lastUserIdKey);
      return (id == null || id.isEmpty) ? null : id;
    } catch (error) {
      debugPrint('TokenStorage.readLastUserId failed: $error');
      return null;
    }
  }

  Future<void> writeLastUserId(String userId) {
    return _storage.write(key: lastUserIdKey, value: userId);
  }
}
