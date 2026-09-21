import 'package:flutter/foundation.dart';

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

  final String code;
  final String message;
  final int? nativeCode;
  final bool isNoFill;
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

  final NapMxEventType type;
  final DateTime timestamp;
  final NapMxAdFormat? format;
  final String? requestId;
  final int? viewId;
  final String? adUnitId;
  final String? network;
  final int? elapsedMilliseconds;
  final NapMxError? error;
  final NapMxReward? reward;
}
