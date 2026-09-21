import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nap_mx_flutter/nap_mx_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('nap_mx_flutter/methods');
  const events = MethodChannel('nap_mx_flutter/events');
  final calls = <MethodCall>[];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'getSdkInfo') {
        return <String, Object?>{
          'platform': 'test',
          'pluginVersion': '0.1.0',
          'sdkVersion': '2.3.0',
        };
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, null);
  });

  test('configuration preserves explicit unspecified privacy state', () {
    final value = NapMxConfiguration(
      mediaKey: '123',
      adUnitIds: const {NapMxAdFormat.banner: '456'},
    ).toMap();
    final privacy = value['privacy']! as Map<String, Object?>;
    expect(privacy['gdprConsent'], 'unspecified');
    expect(privacy['childDirected'], 'unspecified');
  });

  test('empty identifiers are rejected before platform calls', () {
    expect(
      () => NapMxConfiguration(
        mediaKey: '',
        adUnitIds: const {NapMxAdFormat.banner: '1'},
      ),
      throwsArgumentError,
    );
  });

  test('events preserve no-fill and reward transaction metadata', () {
    final event = NapMxEvent.fromMap(<Object?, Object?>{
      'type': 'rewarded',
      'timestampMs': 1,
      'format': 'rewarded',
      'requestId': 'request-1',
      'reward': <Object?, Object?>{'transactionId': 'tx-1'},
      'error': <Object?, Object?>{
        'code': 'load_failed',
        'message': 'No ads',
        'nativeCode': -2147483640,
        'isNoFill': true,
      },
    });
    expect(event.format, NapMxAdFormat.rewarded);
    expect(event.reward?.transactionId, 'tx-1');
    expect(event.error?.isNoFill, isTrue);
  });

  test('concurrent initialization is once and controller enforces order',
      () async {
    final config = NapMxConfiguration(
      mediaKey: '123',
      adUnitIds: const {NapMxAdFormat.interstitial: '456'},
    );
    await Future.wait([NapMx.initialize(config), NapMx.initialize(config)]);
    expect(calls.where((call) => call.method == 'initialize'), hasLength(1));

    final controller = NapMxFullscreenAdController(
      format: NapMxAdFormat.interstitial,
      adUnitId: '456',
    );
    expect(controller.show, throwsStateError);
    await controller.load();
    expect(controller.state, NapMxAdState.loaded);
    await controller.show();
    expect(controller.state, NapMxAdState.showing);
    await controller.dispose();
    expect(controller.state, NapMxAdState.disposed);
  });
}
