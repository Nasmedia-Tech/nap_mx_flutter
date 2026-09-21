import 'package:flutter_test/flutter_test.dart';

import 'package:nap_mx_flutter_example/main.dart';

void main() {
  testWidgets('sample exposes demo, settings, and logs', (tester) async {
    await tester.pumpWidget(const NapMxExampleApp());
    expect(find.text('Ad demo'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Logs & guide'), findsOneWidget);
  });
}
