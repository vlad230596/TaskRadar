import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The web shell (`web/index.html`) has to show something on its own.
///
/// Between the HTML arriving and Flutter's first frame the browser downloads
/// CanvasKit (~2.2 MB), `main.dart.js` (~1.3 MB) and the fonts. On the VDS that
/// was measured at ~14 s, and with an empty `<body>` all of it was a white page
/// that looked exactly like a dead site. So the shell carries a loader drawn by
/// the browser itself, and these tests pin the properties it needs to work
/// behind the site's Content-Security-Policy (`script-src 'self'`, no inline
/// scripts) and without the network (no external stylesheets, fonts or images
/// other than files in the bundle).
void main() {
  final html = File('web/index.html').readAsStringSync();
  final body = RegExp(
    r'<body[^>]*>([\s\S]*)</body>',
  ).firstMatch(html)!.group(1)!;
  final bodyWithoutComments = body.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  test('the body has a loader with visible text before the engine boots', () {
    final loaderAt = bodyWithoutComments.indexOf('id="app-loader"');
    final bootstrapAt = bodyWithoutComments.indexOf('flutter_bootstrap.js');
    expect(loaderAt, isNot(-1), reason: 'no #app-loader in <body>');
    expect(
      loaderAt,
      lessThan(bootstrapAt),
      reason: 'the loader must be parsed before the engine script',
    );

    final text = bodyWithoutComments
        .substring(loaderAt, bootstrapAt)
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    expect(text, contains('TaskRadar'));
    expect(text, contains('Загрузка'));
  });

  test(
    'the loader is styled inline, so it renders before any other request',
    () {
      expect(html, contains('<style>'));
      expect(html, contains('#app-loader'));
      expect(html, isNot(contains('rel="stylesheet"')));
    },
  );

  test('the shell has no inline script, which the CSP would refuse', () {
    for (final script in RegExp(
      r'<script([^>]*)>([\s\S]*?)</script>',
    ).allMatches(html)) {
      expect(
        script.group(1),
        contains('src='),
        reason: 'inline <script> is blocked by script-src',
      );
      expect(script.group(2)!.trim(), isEmpty);
    }
  });
}
