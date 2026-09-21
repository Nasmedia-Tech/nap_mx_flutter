// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:nap_mx_flutter/nap_mx_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native plugin reports SDK information', (
    WidgetTester tester,
  ) async {
    final NapMxSdkInfo info = await NapMx.getSdkInfo();
    expect(info.platform, anyOf('android', 'ios'));
    expect(info.pluginVersion, isNotEmpty);
  });
}
