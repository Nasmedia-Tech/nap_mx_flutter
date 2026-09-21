import 'dart:async';

import 'package:flutter/services.dart';

import 'configuration.dart';
import 'events.dart';
import 'nap_mx.dart';

enum NapMxAdState { idle, loading, loaded, showing, disposed, failed }

/// Owns one full-screen ad request from load through disposal.
final class NapMxFullscreenAdController {
  NapMxFullscreenAdController({
    required this.format,
    required this.adUnitId,
    this.loadTimeout = const Duration(seconds: 30),
  }) {
    if (!format.isFullscreen) {
      throw ArgumentError.value(
        format,
        'format',
        'must be a full-screen format',
      );
    }
    if (adUnitId.trim().isEmpty) {
      throw ArgumentError.value(adUnitId, 'adUnitId', 'must not be empty');
    }
    _requestId = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    _subscription = NapMx.events
        .where((event) => event.requestId == _requestId)
        .listen(_onEvent);
  }

  static int _sequence = 0;
  late final String _requestId;
  late final StreamSubscription<NapMxEvent> _subscription;

  /// Full-screen format owned by this request.
  final NapMxAdFormat format;

  /// Android string ID or an iOS decimal ID represented as a string.
  final String adUnitId;

  /// Plugin-side upper bound for a native load callback.
  final Duration loadTimeout;
  final StreamController<NapMxEvent> _events = StreamController.broadcast();
  NapMxAdState _state = NapMxAdState.idle;

  /// Unique identifier used to attribute native callbacks to this request.
  String get requestId => _requestId;

  /// Current request state. Check for [NapMxAdState.loaded] before [show].
  NapMxAdState get state => _state;

  /// Events filtered to this controller's [requestId].
  Stream<NapMxEvent> get events => _events.stream;

  /// Loads one ad and completes after native success or failure.
  ///
  /// [customParams] are forwarded by Android. iOS currently ignores them, so
  /// cross-platform behavior must not depend on these values.
  Future<void> load({Map<String, String> customParams = const {}}) async {
    _ensureUsable();
    if (_state == NapMxAdState.loading || _state == NapMxAdState.loaded) {
      throw StateError('This request is already ${_state.name}.');
    }
    _state = NapMxAdState.loading;
    try {
      await NapMx.methods
          .invokeMethod<void>('loadFullscreen', <String, Object?>{
        'requestId': _requestId,
        'format': format.wireName,
        'adUnitId': adUnitId,
        'timeoutMs': loadTimeout.inMilliseconds,
        'customParams': customParams,
      });
      if (_state == NapMxAdState.loading) _state = NapMxAdState.loaded;
    } on PlatformException catch (error) {
      _state = NapMxAdState.failed;
      throw NapMxError.fromPlatformException(error);
    }
  }

  /// Shows the previously loaded ad from the current active Activity/scene.
  Future<void> show() async {
    _ensureUsable();
    if (_state != NapMxAdState.loaded) {
      throw StateError('show() requires a successfully loaded ad.');
    }
    _state = NapMxAdState.showing;
    try {
      await NapMx.methods.invokeMethod<void>(
        'showFullscreen',
        <String, Object?>{'requestId': _requestId},
      );
    } on PlatformException catch (error) {
      _state = NapMxAdState.failed;
      throw NapMxError.fromPlatformException(error);
    }
  }

  /// Releases native ad references and closes the filtered event stream.
  Future<void> dispose() async {
    if (_state == NapMxAdState.disposed) return;
    _state = NapMxAdState.disposed;
    try {
      await NapMx.methods.invokeMethod<void>(
        'disposeFullscreen',
        <String, Object?>{'requestId': _requestId},
      );
    } on PlatformException catch (error) {
      throw NapMxError.fromPlatformException(error);
    } finally {
      await _subscription.cancel();
      await _events.close();
    }
  }

  void _onEvent(NapMxEvent event) {
    if (_state == NapMxAdState.disposed) return;
    switch (event.type) {
      case NapMxEventType.loaded:
        _state = NapMxAdState.loaded;
      case NapMxEventType.loadFailed || NapMxEventType.showFailed:
        _state = NapMxAdState.failed;
      case NapMxEventType.shown:
        _state = NapMxAdState.showing;
      case NapMxEventType.closed || NapMxEventType.cancelled:
        _state = NapMxAdState.idle;
      case NapMxEventType.disposed:
        _state = NapMxAdState.disposed;
      default:
        break;
    }
    _events.add(event);
  }

  void _ensureUsable() {
    if (!NapMx.isInitialized) {
      throw StateError('Call NapMx.initialize before requesting ads.');
    }
    if (_state == NapMxAdState.disposed) {
      throw StateError('This controller is disposed.');
    }
  }
}
