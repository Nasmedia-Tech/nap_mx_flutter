import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nap_mx_flutter/nap_mx_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('nap_mx_flutter/methods');
  const events = MethodChannel('nap_mx_flutter/events');
  final calls = <MethodCall>[];
  final config = NapMxConfiguration(
    mediaKey: '123',
    adUnitIds: const {
      NapMxAdFormat.interstitial: '456',
      NapMxAdFormat.rewarded: '789',
    },
  );

  // Delivers one event the way the native EventChannel would.
  Future<void> emitNative(Map<String, Object?> event) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'nap_mx_flutter/events',
        const StandardMethodCodec().encodeSuccessEnvelope(event),
        (_) {},
      );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'getSdkInfo') {
        return <String, Object?>{
          'platform': 'test',
          'pluginVersion': '0.1.2',
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

  test('platform failures use the typed no-fill and timeout flags', () {
    final androidNoFill = NapMxError.fromPlatformException(
      PlatformException(
        code: 'load_failed',
        message: 'No ads',
        details: -2147483640,
      ),
    );
    final iosNoFill = NapMxError.fromPlatformException(
      PlatformException(code: 'load_failed', details: -1),
    );
    final androidTimeout = NapMxError.fromPlatformException(
      PlatformException(code: 'load_failed', details: -2147483644),
    );
    final pluginTimeout = NapMxError.fromPlatformException(
      PlatformException(
        code: 'timeout',
        message: 'Timed out',
        details: -8,
      ),
    );

    expect(androidNoFill.isNoFill, isTrue);
    expect(iosNoFill.isNoFill, isTrue);
    expect(androidTimeout.isTimeout, isTrue);
    expect(pluginTimeout.isNoFill, isFalse);
    expect(pluginTimeout.isTimeout, isTrue);
  });

  test('concurrent initialization is once and controller enforces order',
      () async {
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

  test('a reward reported after close still reaches the controller', () async {
    await NapMx.initialize(config);
    final controller = NapMxFullscreenAdController(
      format: NapMxAdFormat.rewarded,
      adUnitId: '789',
    );
    final received = <NapMxEvent>[];
    final subscription = controller.events.listen(received.add);
    await pumpEventQueue();

    await emitNative(<String, Object?>{
      'type': 'closed',
      'timestampMs': 1,
      'requestId': controller.requestId,
      'format': 'rewarded',
    });
    await emitNative(<String, Object?>{
      'type': 'rewarded',
      'timestampMs': 2,
      'requestId': controller.requestId,
      'format': 'rewarded',
      'reward': <String, Object?>{'transactionId': 'tx-late'},
    });
    await pumpEventQueue();

    expect(
      received.map((event) => event.type),
      <NapMxEventType>[NapMxEventType.closed, NapMxEventType.rewarded],
    );
    expect(received.last.reward?.transactionId, 'tx-late');
    // `closed` must not dispose the controller, or the late reward is lost.
    expect(controller.state, NapMxAdState.idle);

    await subscription.cancel();
    await controller.dispose();
  });

  test('events for one request never reach another controller', () async {
    await NapMx.initialize(config);
    final rewarded = NapMxFullscreenAdController(
      format: NapMxAdFormat.rewarded,
      adUnitId: '789',
    );
    final interstitial = NapMxFullscreenAdController(
      format: NapMxAdFormat.interstitial,
      adUnitId: '456',
    );
    final leaked = <NapMxEvent>[];
    final subscription = interstitial.events.listen(leaked.add);
    await pumpEventQueue();

    await emitNative(<String, Object?>{
      'type': 'rewarded',
      'timestampMs': 3,
      'requestId': rewarded.requestId,
      'format': 'rewarded',
      'reward': <String, Object?>{'transactionId': 'tx-other'},
    });
    await pumpEventQueue();

    expect(leaked, isEmpty);
    expect(rewarded.requestId, isNot(interstitial.requestId));

    await subscription.cancel();
    await rewarded.dispose();
    await interstitial.dispose();
  });
}
