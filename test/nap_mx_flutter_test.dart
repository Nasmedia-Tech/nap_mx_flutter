import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nap_mx_flutter/nap_mx_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('nap_mx_flutter/methods');
  const events = MethodChannel('nap_mx_flutter/events');
  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall)? handleCall;
  final config = NapMxConfiguration(
    mediaKey: '123',
    adUnitIds: const {
      NapMxAdFormat.interstitial: '456',
      NapMxAdFormat.rewarded: '789',
    },
    additionalAdUnitIds: const ['790'],
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
      if (handleCall != null) return handleCall!(call);
      if (call.method == 'getSdkInfo') {
        return <String, Object?>{
          'platform': 'test',
          'pluginVersion': '0.1.8',
          'sdkVersion': '2.4.0',
        };
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (_) async => null);
  });

  tearDown(() {
    handleCall = null;
    debugDefaultTargetPlatformOverride = null;
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

  test('additional placements support list-only registration and snapshots',
      () {
    final ids = [' 789 ', '790', '790'];
    final configuration = NapMxConfiguration(
      mediaKey: '123',
      additionalAdUnitIds: ids,
    );
    ids.clear();
    expect(configuration.toMap()['adUnitIds'], isEmpty);
    expect(configuration.toMap()['additionalAdUnitIds'], ['789', '790']);
    expect(() => configuration.additionalAdUnitIds.add('791'),
        throwsUnsupportedError);
    expect(configuration.adUnitIdFor(NapMxAdFormat.rewarded), isNull);
  });

  test('empty registration and blank additional IDs are rejected', () {
    expect(() => NapMxConfiguration(mediaKey: '123'), throwsArgumentError);
    expect(
      () => NapMxConfiguration(
        mediaKey: '123',
        adUnitIds: const {NapMxAdFormat.rewarded: '789'},
        additionalAdUnitIds: const [' '],
      ),
      throwsArgumentError,
    );
  });

  // Must run before any test initializes the process-wide SDK.
  testWidgets('auto-load before initialization reports instead of throwing',
      (tester) async {
    expect(NapMx.isInitialized, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('nap_mx_flutter/view/44');
    final viewCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      viewCalls.add(call.method);
      return null;
    });
    await tester.pumpWidget(const SizedBox());
    final received = <NapMxEvent>[];
    NapMxAdViewController? controller;
    final widget = NapMxAdView(
        format: NapMxAdFormat.banner,
        adUnitId: '456',
        autoLoad: true,
        onViewCreated: (value) {
          controller = value;
          value.events.listen(received.add);
        });
    final box = widget.build(tester.element(find.byType(SizedBox))) as SizedBox;
    final platform = (box.child! as ClipRect).child! as AndroidView;
    await tester.runAsync(() async {
      platform.onPlatformViewCreated!(44);
      await pumpEventQueue();
      expect(received.single.type, NapMxEventType.loadFailed);
      expect(received.single.error?.code, 'not_initialized');
      expect(viewCalls, isEmpty);
      await controller!.dispose();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('additional placement changes cannot bypass initialization guard',
      () async {
    await NapMx.initialize(config);
    await NapMx.initialize(NapMxConfiguration(
      mediaKey: '123',
      adUnitIds: config.adUnitIds,
      additionalAdUnitIds: const ['790', '790'],
    ));
    await expectLater(
      NapMx.initialize(NapMxConfiguration(
        mediaKey: '123',
        adUnitIds: config.adUnitIds,
        additionalAdUnitIds: const ['791'],
      )),
      throwsStateError,
    );
    final initialization =
        calls.singleWhere((call) => call.method == 'initialize');
    expect((initialization.arguments as Map)['additionalAdUnitIds'], ['790']);
    final controller = NapMxFullscreenAdController(
      format: NapMxAdFormat.rewarded,
      adUnitId: '790',
    );
    await controller.load();
    final load = calls.lastWhere((call) => call.method == 'loadFullscreen');
    expect((load.arguments as Map)['adUnitId'], '790');
    await controller.dispose();
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

  for (final format
      in NapMxAdFormat.values.where((format) => format.isFullscreen)) {
    test('${format.name} forwards its ID and request parameters', () async {
      await NapMx.initialize(config);
      final controller =
          NapMxFullscreenAdController(format: format, adUnitId: '790');
      await controller.load(customParams: {'user_id': 'test-member'});
      final load = calls.lastWhere((call) => call.method == 'loadFullscreen');
      expect(load.arguments, {
        'requestId': controller.requestId,
        'format': format.wireName,
        'adUnitId': '790',
        'timeoutMs': 30000,
        'customParams': {'user_id': 'test-member'},
      });
      await controller.show();
      await expectLater(controller.load(), throwsStateError);
      await emitNative({'type': 'loaded', 'requestId': controller.requestId});
      await pumpEventQueue();
      expect(controller.state, NapMxAdState.showing);
      await controller.dispose();
    });
  }

  for (final operation in ['loadFullscreen', 'showFullscreen']) {
    test('disposing during $operation stays disposed after cancellation',
        () async {
      await NapMx.initialize(config);
      final pending = Completer<Object?>();
      final controller = NapMxFullscreenAdController(
          format: NapMxAdFormat.interstitial, adUnitId: '456');
      if (operation == 'showFullscreen') await controller.load();
      handleCall = (call) async {
        if (call.method == operation) return pending.future;
        return null;
      };
      final action =
          operation == 'loadFullscreen' ? controller.load() : controller.show();
      final failure = expectLater(action, throwsA(isA<NapMxError>()));
      await controller.dispose();
      pending.completeError(PlatformException(code: 'cancelled'));
      await failure;
      expect(controller.state, NapMxAdState.disposed);
      await expectLater(controller.load(), throwsStateError);
    });
  }

  test('every native event preserves its attribution and type', () async {
    await NapMx.initialize(config);
    final controller = NapMxFullscreenAdController(
        format: NapMxAdFormat.rewarded, adUnitId: '789');
    final received = <NapMxEvent>[];
    final subscription = controller.events.listen(received.add);
    await pumpEventQueue();
    final types = NapMxEventType.values.where((type) =>
        type != NapMxEventType.disposed && type != NapMxEventType.unknown);
    for (final type in types) {
      await emitNative({
        'type': type.name,
        'requestId': controller.requestId,
        'format': 'rewarded',
        'adUnitId': '789',
        'network': 'AdMixer',
        'timestampMs': 1000,
        'elapsedMs': 25,
      });
    }
    await pumpEventQueue();
    expect(received.map((event) => event.type), types);
    expect(
        received.every((event) =>
            event.adUnitId == '789' &&
            event.network == 'AdMixer' &&
            event.elapsedMilliseconds == 25),
        isTrue);
    await subscription.cancel();
    await controller.dispose();
  });

  for (final format in [
    NapMxAdFormat.banner,
    NapMxAdFormat.native,
    NapMxAdFormat.inlineVideo
  ]) {
    testWidgets('${format.name} auto-load starts after the event subscription',
        (tester) async {
      await NapMx.initialize(config);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const viewMethods = MethodChannel('nap_mx_flutter/view/42');
      final received = <NapMxEvent>[];
      NapMxAdViewController? controller;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(viewMethods, (call) async {
        if (call.method == 'load') {
          await emitNative({'type': 'loadStarted', 'viewId': 42});
          await emitNative({'type': 'loaded', 'viewId': 42});
        }
        return null;
      });
      await tester.pumpWidget(const SizedBox());
      final widget = NapMxAdView(
          format: format,
          adUnitId: '456',
          autoLoad: true,
          onViewCreated: (value) {
            controller = value;
            value.events.listen(received.add);
          });
      final box =
          widget.build(tester.element(find.byType(SizedBox))) as SizedBox;
      final platform = (box.child! as ClipRect).child! as AndroidView;
      expect((platform.creationParams as Map)['autoLoad'], isFalse);
      await tester.runAsync(() async {
        platform.onPlatformViewCreated!(42);
        await pumpEventQueue();
        expect(received.map((event) => event.type),
            [NapMxEventType.loadStarted, NapMxEventType.loaded]);
        await controller!.dispose();
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(viewMethods, null);
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets('auto-load reports immediate platform errors to its subscriber',
      (tester) async {
    await NapMx.initialize(config);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('nap_mx_flutter/view/43');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'load') {
        throw PlatformException(code: 'invalid_request', message: 'Invalid ID');
      }
      return null;
    });
    await tester.pumpWidget(const SizedBox());
    final received = <NapMxEvent>[];
    NapMxAdViewController? controller;
    final widget = NapMxAdView(
        format: NapMxAdFormat.banner,
        adUnitId: ' 456 ',
        autoLoad: true,
        onViewCreated: (value) {
          controller = value;
          value.events.listen(received.add);
        });
    final box = widget.build(tester.element(find.byType(SizedBox))) as SizedBox;
    final platform = (box.child! as ClipRect).child! as AndroidView;
    await tester.runAsync(() async {
      platform.onPlatformViewCreated!(43);
      await pumpEventQueue();
      expect(received.single.type, NapMxEventType.loadFailed);
      expect(received.single.error?.code, 'invalid_request');
      expect(received.single.format, NapMxAdFormat.banner);
      expect(received.single.adUnitId, '456');
      expect(received.single.viewId, 43);
      await controller!.dispose();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('a host load in onViewCreated replaces auto-load',
      (tester) async {
    await NapMx.initialize(config);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('nap_mx_flutter/view/45');
    final viewCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      viewCalls.add(call.method);
      return null;
    });
    await tester.pumpWidget(const SizedBox());
    final received = <NapMxEvent>[];
    NapMxAdViewController? controller;
    final widget = NapMxAdView(
        format: NapMxAdFormat.banner,
        adUnitId: '456',
        autoLoad: true,
        onViewCreated: (value) {
          controller = value;
          value.events.listen(received.add);
          unawaited(value.load());
        });
    final box = widget.build(tester.element(find.byType(SizedBox))) as SizedBox;
    final platform = (box.child! as ClipRect).child! as AndroidView;
    await tester.runAsync(() async {
      platform.onPlatformViewCreated!(45);
      await pumpEventQueue();
      expect(viewCalls, ['load']);
      expect(received, isEmpty);
      await controller!.dispose();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('a show rejected before presenting keeps the ad retryable', () async {
    await NapMx.initialize(config);
    var rejectShow = true;
    handleCall = (call) async {
      if (call.method == 'showFullscreen' && rejectShow) {
        throw PlatformException(code: 'no_activity', message: 'No Activity');
      }
      return null;
    };
    final controller = NapMxFullscreenAdController(
      format: NapMxAdFormat.rewarded,
      adUnitId: '789',
    );
    await controller.load();
    await expectLater(controller.show(), throwsA(isA<NapMxError>()));
    expect(controller.state, NapMxAdState.loaded);
    rejectShow = false;
    await controller.show();
    expect(controller.state, NapMxAdState.showing);
    await controller.dispose();
  });

  test('a repeated dispose after a native failure completes', () async {
    await NapMx.initialize(config);
    handleCall = (call) async {
      if (call.method == 'disposeFullscreen') {
        throw PlatformException(code: 'detached', message: 'Engine detached');
      }
      return null;
    };
    final controller = NapMxFullscreenAdController(
      format: NapMxAdFormat.interstitial,
      adUnitId: '456',
    );
    await expectLater(controller.dispose(), throwsA(isA<NapMxError>()));
    await controller.dispose();
    expect(controller.state, NapMxAdState.disposed);
  });
}
