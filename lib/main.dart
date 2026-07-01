import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app/bootstrap.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    await bootstrap();
  }, (error, stack) {
    debugPrint('[Uncaught] $error\n$stack');
  });
}
