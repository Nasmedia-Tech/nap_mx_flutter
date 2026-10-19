import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'configuration.dart';
import 'events.dart';
import 'nap_mx.dart';

/// Controls one platform-rendered banner, native, or inline-video view.
final class NapMxAdViewController {
  NapMxAdViewController._(this.viewId) {
    _channel = MethodChannel('nap_mx_flutter/view/$viewId');
    _subscription =
        NapMx.events.where((event) => event.viewId == viewId).listen((event) {
      if (!_disposed) _events.add(event);
    });
  }

  final int viewId;
  late final MethodChannel _channel;
  late final StreamSubscription<NapMxEvent> _subscription;
  final StreamController<NapMxEvent> _events = StreamController.broadcast();
  bool _disposed = false;
  Future<void>? _disposing;

  /// Events filtered to this PlatformView's [viewId].
  Stream<NapMxEvent> get events => _events.stream;

  /// Starts one native ad load for this view.
  Future<void> load() => _invoke('load');

  /// Cancels the current native load while keeping the view reusable.
  Future<void> cancel() => _invoke('cancel');

  /// Releases native views, callbacks, and the filtered event stream.
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    try {
      await _channel.invokeMethod<void>('dispose');
    } on PlatformException catch (error) {
      throw NapMxError.fromPlatformException(error);
    } finally {
      await _subscription.cancel();
      await _events.close();
    }
  }

  Future<void> _invoke(String method) async {
    if (_disposed) throw StateError('The ad view controller is disposed.');
    if (!NapMx.isInitialized) {
      throw StateError('Call NapMx.initialize before loading an ad view.');
    }
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (error) {
      throw NapMxError.fromPlatformException(error);
    }
  }

  Future<void> _autoLoad(NapMxAdFormat format, String adUnitId) async {
    try {
      await load();
    } on NapMxError catch (error) {
      if (!_disposed) {
        _events.add(NapMxEvent(
          type: NapMxEventType.loadFailed,
          timestamp: DateTime.now(),
          viewId: viewId,
          format: format,
          adUnitId: adUnitId.trim(),
          error: error,
        ));
      }
    }
  }
}

/// Hosts an actual SDK native view; no ad assets are rebuilt in Flutter.
class NapMxAdView extends StatelessWidget {
  const NapMxAdView({
    required this.format,
    required this.adUnitId,
    required this.onViewCreated,
    this.width,
    this.height,
    this.autoLoad = false,
    this.muted = true,
    super.key,
  }) : assert(
          format == NapMxAdFormat.banner ||
              format == NapMxAdFormat.native ||
              format == NapMxAdFormat.inlineVideo,
        );

  final NapMxAdFormat format;

  /// Android accepts arbitrary SDK string IDs; iOS requires decimal digits.
  /// Register this placement in the initialization configuration first.
  /// Multiple views of the same format may use different registered IDs.
  final String adUnitId;

  /// Called once the underlying PlatformView and controller are ready.
  final ValueChanged<NapMxAdViewController> onViewCreated;

  /// Optional slot width. Defaults to all available horizontal space.
  final double? width;

  /// Optional slot height; use a bounded value that preserves ad assets.
  final double? height;

  /// Whether to load after [onViewCreated] can subscribe to events.
  final bool autoLoad;

  /// Requested initial mute state for video formats when supported by the SDK.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (autoLoad && !NapMx.isInitialized) {
      throw StateError('Call NapMx.initialize before loading an ad view.');
    }
    final defaultSize = switch (format) {
      NapMxAdFormat.banner => const Size(320, 50),
      NapMxAdFormat.native => const Size(320, 360),
      NapMxAdFormat.inlineVideo => const Size(320, 180),
      _ => Size.zero,
    };
    final params = <String, Object?>{
      'format': format.wireName,
      'adUnitId': adUnitId.trim(),
      // Native creation precedes the controller and its event subscription.
      'autoLoad': false,
      'muted': muted,
    };
    final view = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidView(
          viewType: 'nap_mx_flutter/ad_view',
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _created,
        ),
      TargetPlatform.iOS => UiKitView(
          viewType: 'nap_mx_flutter/ad_view',
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _created,
        ),
      _ => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: const Center(
            child: Text('nap mx is supported on Android and iOS.'),
          ),
        ),
    };
    return SizedBox(
      width: width ?? double.infinity,
      height: height ?? defaultSize.height,
      child: ClipRect(child: view),
    );
  }

  void _created(int id) {
    final controller = NapMxAdViewController._(id);
    onViewCreated(controller);
    if (autoLoad && !controller._disposed) {
      unawaited(controller._autoLoad(format, adUnitId));
    }
  }
}
