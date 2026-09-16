import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  // Nothing async happens here on purpose. The startup session probe lives in
  // `Session.build` and is rendered as a loading state, so the first frame is
  // painted immediately instead of after a secure-storage read and a network
  // round trip. On a cold start over mobile data that difference is the gap
  // between "opened instantly" and "hung for two seconds".
  runApp(const ProviderScope(child: TaskRadarApp()));
}
