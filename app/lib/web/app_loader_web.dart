import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void removeAppLoader() {
  final document = globalContext['document'] as JSObject?;
  final loader = document?.callMethod<JSObject?>(
    'getElementById'.toJS,
    'app-loader'.toJS,
  );
  loader?.callMethod<JSAny?>('remove'.toJS);
}
