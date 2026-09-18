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

import 'package:flutter/foundation.dart';

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
  ///
  /// ## Why the web build has no address of its own
  ///
  /// The web client is served by the same origin as the API (see
  /// `deploy/Caddyfile.taskradar.example`: the `@api` prefixes go to the
  /// backend, everything else to this bundle). So the right base URL is
  /// whatever origin the page was loaded from -- which is also the only
  /// configuration that needs no CORS on the server, and the reason the same
  /// bundle would work unchanged behind a different hostname.
  ///
  /// The empty default plus [Uri.base] says that explicitly, rather than
  /// relying on the browser to resolve a relative `/board` the way it happens
  /// to: the origin is what ends up in dio's `baseUrl`, and it is what the
  /// login screen prints when a request cannot be made.
  static const String configuredApiBaseUrl = String.fromEnvironment(
    apiBaseUrlKey,
    defaultValue: kIsWeb ? '' : 'http://localhost:3001',
  );

  /// Base URL of the TaskRadar backend, as the running app should use it.
  ///
  /// A getter rather than a `const` because of the web case above; every other
  /// target returns the compile-time constant unchanged. `Uri.base` is only
  /// consulted when the constant is empty, which outside a browser can only
  /// happen if someone passes `--dart-define=TASKRADAR_API_URL=` on purpose --
  /// and there `Uri.base` is the working directory, whose `origin` throws. So
  /// that combination keeps the empty value and fails at the first request with
  /// a message naming the URL, instead of crashing on the first frame.
  static String get apiBaseUrl => (configuredApiBaseUrl.isEmpty && kIsWeb)
      ? Uri.base.origin
      : configuredApiBaseUrl;
}
