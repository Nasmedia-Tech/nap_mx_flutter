import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'configuration.dart';
import 'events.dart';

/// Process-wide nap mx entry point.
final class NapMx {
  NapMx._();

  static const MethodChannel _methods = MethodChannel('nap_mx_flutter/methods');
  static const EventChannel _nativeEvents = EventChannel(
    'nap_mx_flutter/events',
  );
  static Stream<NapMxEvent>? _events;
  static Future<void>? _initializing;
  static NapMxConfiguration? _initializingConfiguration;
  static NapMxConfiguration? _configuration;

  static Stream<NapMxEvent> get events => _events ??= _nativeEvents
      .receiveBroadcastStream()
      .map(
        (dynamic value) =>
            NapMxEvent.fromMap((value as Map).cast<Object?, Object?>()),
      )
      .asBroadcastStream();

  static bool get isInitialized => _configuration != null;

  static NapMxConfiguration get configuration {
    final value = _configuration;
    if (value == null) {
      throw StateError('Call NapMx.initialize before requesting ads.');
    }
    return value;
  }

  /// Initializes the native SDK once. Concurrent callers share one operation.
  static Future<void> initialize(NapMxConfiguration configuration) {
    final existing = _configuration;
    if (existing != null) {
      if (_sameConfiguration(existing, configuration)) {
        return Future<void>.value();
      }
      return Future<void>.error(
        StateError('nap mx is already initialized with another configuration.'),
      );
    }
    final inFlight = _initializing;
    if (inFlight != null) {
      if (_sameConfiguration(_initializingConfiguration!, configuration)) {
        return inFlight;
      }
      return Future<void>.error(
        StateError(
            'nap mx initialization is in progress with another configuration.'),
      );
    }
    _initializingConfiguration = configuration;
    return _initializing = _initialize(configuration);
  }

  static Future<void> _initialize(NapMxConfiguration configuration) async {
    try {
      await _methods.invokeMethod<void>('initialize', configuration.toMap());
      _configuration = configuration;
    } on PlatformException catch (error) {
      throw NapMxError(
        code: error.code,
        message: error.message ?? 'Initialization failed',
        nativeCode: error.details is int ? error.details as int : null,
      );
    } finally {
      _initializing = null;
      _initializingConfiguration = null;
    }
  }

  static Future<NapMxSdkInfo> getSdkInfo() async {
    final value = await _methods.invokeMapMethod<Object?, Object?>(
      'getSdkInfo',
    );
    return NapMxSdkInfo.fromMap(value ?? const <Object?, Object?>{});
  }

  static bool _sameConfiguration(
    NapMxConfiguration left,
    NapMxConfiguration right,
  ) =>
      left.mediaKey == right.mediaKey &&
      mapEquals(left.adUnitIds, right.adUnitIds) &&
      left.logLevel == right.logLevel &&
      left.testMode == right.testMode &&
      listEquals(left.testDeviceIds, right.testDeviceIds) &&
      left.privacy.gdprConsent == right.privacy.gdprConsent &&
      left.privacy.usSaleConsent == right.privacy.usSaleConsent &&
      left.privacy.childDirected == right.privacy.childDirected &&
      left.privacy.underAgeOfConsent == right.privacy.underAgeOfConsent &&
      left.privacy.usPrivacyString == right.privacy.usPrivacyString &&
      left.mediation.length == right.mediation.length &&
      left.mediation.entries.every(
        (entry) => mapEquals(entry.value, right.mediation[entry.key]),
      );

  static MethodChannel get methods => _methods;
}
