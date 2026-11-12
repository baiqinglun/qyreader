/// integration_test 驱动：把设备端 `reportData` 打回宿主机 stdout。
library;

import 'dart:convert';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data != null && data['perf'] != null) {
          // ignore: avoid_print
          print('PERF_RESULT ${jsonEncode(data['perf'])}');
        }
      },
    );
