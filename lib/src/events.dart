import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'configuration.dart';

enum NapMxEventType {
  initializationSucceeded,
  loadStarted,
  loaded,
  loadFailed,
  shown,
  showFailed,
  clicked,
  closed,
  completed,
  skipped,
  rewarded,
  cancelled,
  disposed,
  unknown,
}

@immutable
final class NapMxError implements Exception {
  const NapMxError({
    required this.code,
    required this.message,
    this.nativeCode,
    this.isNoFill = false,
    this.isTimeout = false,
  });

  factory NapMxError.fromMap(Map<Object?, Object?> map) => NapMxError(
        code: map['code'] as String? ?? 'unknown',
        message: map['message'] as String? ?? 'Unknown nap mx error',
        nativeCode: map['nativeCode'] as int?,
        isNoFill: map['isNoFill'] as bool? ?? false,
        isTimeout: map['isTimeout'] as bool? ?? false,
      );

  /// Converts a platform-channel failure into the public nap mx error model.
  ///
  /// Android uses signed `0x80000008`/`0x80000004` for no-fill/timeout,
  /// while iOS uses `-1`/`-8`. The string code is also checked for a
  /// plugin-generated timeout.
  factory NapMxError.fromPlatformException(PlatformException error) {
    final nativeCode = error.details is int ? error.details as int : null;
    return NapMxError(
      code: error.code,
      message: error.message ?? 'nap mx platform error',
      nativeCode: nativeCode,
      isNoFill: nativeCode == -1 || nativeCode == -2147483640,
      isTimeout: error.code == 'timeout' ||
          nativeCode == -8 ||
          nativeCode == -2147483644,
    );
  }

  /// Stable plugin error category such as `load_failed` or `not_loaded`.
  final String code;

  /// Human-readable diagnostic message. Do not branch business logic on it.
  final String message;

  /// Original native SDK error code when one was reported.
  final int? nativeCode;

  /// Whether the native result means that no ad inventory was available.
  final bool isNoFill;

  /// Whether the plugin or native SDK load timeout elapsed.
  final bool isTimeout;

  @override
  String toString() => 'NapMxError($code, nativeCode: $nativeCode): $message';
}

@immutable
final class NapMxReward {
  const NapMxReward({required this.transactionId});

  /// SDK reward transaction ID. Reward amount/type remain app-owned policy.
  final String transactionId;
}

@immutable
final class NapMxEvent {
  const NapMxEvent({
    required this.type,
    required this.timestamp,
    this.format,
    this.requestId,
    this.viewId,
    this.adUnitId,
    this.network,
    this.elapsedMilliseconds,
    this.error,
    this.reward,
  });

  factory NapMxEvent.fromMap(Map<Object?, Object?> map) {
    final typeName = map['type'] as String? ?? 'unknown';
    final formatName = map['format'] as String?;
    return NapMxEvent(
      type: NapMxEventType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => NapMxEventType.unknown,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestampMs'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      format: formatName == null
          ? null
          : NapMxAdFormat.values.cast<NapMxAdFormat?>().firstWhere(
                (value) => value?.wireName == formatName,
                orElse: () => null,
              ),
      requestId: map['requestId'] as String?,
      viewId: map['viewId'] as int?,
      adUnitId: map['adUnitId'] as String?,
      network: map['network'] as String?,
      elapsedMilliseconds: map['elapsedMs'] as int?,
      error: map['error'] is Map
          ? NapMxError.fromMap((map['error'] as Map).cast<Object?, Object?>())
          : null,
      reward: map['reward'] is Map
          ? NapMxReward(
              transactionId:
                  ((map['reward'] as Map)['transactionId'] as String?) ?? '',
            )
          : null,
    );
  }

  /// Lifecycle event reported by the plugin or native SDK.
  final NapMxEventType type;

  /// Time at which the plugin emitted this event.
  final DateTime timestamp;

  /// Ad format when the event belongs to an ad request.
  final NapMxAdFormat? format;

  /// Full-screen request identifier. Null for view and initialization events.
  final String? requestId;

  /// PlatformView identifier. Null for full-screen requests.
  final int? viewId;

  /// Ad unit used by this request. Treat it as sensitive configuration.
  final String? adUnitId;

  /// Actual network reported by the SDK, or null when it was not reported.
  final String? network;

  /// Time from the request start, when measurable by the plugin.
  final int? elapsedMilliseconds;

  /// Failure details for `loadFailed` and `showFailed` events.
  final NapMxError? error;

  /// Reward details, present only for a real SDK `rewarded` callback.
  ///
  /// The native SDKs define no order between [NapMxEventType.rewarded] and
  /// [NapMxEventType.closed], so a reward can arrive after the ad closed. Do
  /// not dispose the controller on `closed` if you still owe a reward.
  final NapMxReward? reward;
}
