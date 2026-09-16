/// Build-time configuration.
///
/// The API base URL is a compile-time constant rather than a runtime setting on
/// purpose: there is exactly one backend per build (dev laptop, later the VPS
/// from F5), and a settings screen for it would be one more thing to get wrong
/// on the phone. Override it at build/run time:
///
///     flutter run --dart-define=TASKRADAR_API_URL=http://192.168.1.42:3001
///
/// `String.fromEnvironment` only works with a `const` context, which is why this
/// is a `static const` and not a getter.
library;

class AppConfig {
  const AppConfig._();

  /// Name of the `--dart-define` key, kept next to its use so the two cannot
  /// drift apart when someone greps for it.
  static const String apiBaseUrlKey = 'TASKRADAR_API_URL';

  /// Base URL of the TaskRadar backend.
  ///
  /// The default targets the Windows desktop target running against a backend
  /// started with `npm run dev` in `backend/`. It is deliberately *not* useful
  /// on a phone, and that is not an oversight worth "fixing" with a smarter
  /// default:
  ///
  /// - on a physical Android device `localhost` is the phone itself, so the
  ///   request cannot reach the laptop at all -- the LAN IP has to be passed in;
  /// - on the Android emulator the host machine is `10.0.2.2`, not `localhost`.
  ///
  /// Either way the phone needs an explicit `--dart-define`, so the default only
  /// has to serve the desktop case, where it is right every time.
  static const String apiBaseUrl = String.fromEnvironment(
    apiBaseUrlKey,
    defaultValue: 'http://localhost:3001',
  );
}
