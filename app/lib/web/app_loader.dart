/// Removes the HTML loader that `web/index.html` shows while the engine
/// downloads. A no-op everywhere but the browser.
///
/// The loader sits in the page before Flutter exists, so nothing in the widget
/// tree can cover it reliably -- it has to be taken out of the DOM once the
/// first frame is on screen. Split by conditional import so the Android and
/// Windows builds never see `dart:js_interop`.
library;

export 'app_loader_stub.dart'
    if (dart.library.js_interop) 'app_loader_web.dart';
