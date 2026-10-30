// Host side of integration_test/composer_keystroke_perf_test.dart: writes
// the device's keystroke summary to build/composer_keystroke_perf.json,
// also when the run fails its budget, so a failing run keeps its numbers.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final file = File('build/composer_keystroke_perf.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
