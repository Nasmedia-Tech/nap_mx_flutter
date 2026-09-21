import 'package:flutter/foundation.dart';

/// Ad formats exposed by nap mx.
enum NapMxAdFormat {
  banner,
  native,
  inlineVideo,
  interstitial,
  interstitialVideo,
  rewarded;

  String get wireName => switch (this) {
        banner => 'banner',
        native => 'native',
        inlineVideo => 'inlineVideo',
        interstitial => 'interstitial',
        interstitialVideo => 'interstitialVideo',
        rewarded => 'rewarded',
      };

  bool get isFullscreen => switch (this) {
        interstitial || interstitialVideo || rewarded => true,
        _ => false,
      };
}

/// A privacy signal with an explicit unset state.
enum NapMxConsentStatus { unspecified, granted, denied }

/// Privacy signals forwarded to the native SDK before initialization.
@immutable
final class NapMxPrivacySettings {
  const NapMxPrivacySettings({
    this.gdprConsent = NapMxConsentStatus.unspecified,
    this.usSaleConsent = NapMxConsentStatus.unspecified,
    this.childDirected = NapMxConsentStatus.unspecified,
    this.underAgeOfConsent = NapMxConsentStatus.unspecified,
    this.usPrivacyString,
  });

  final NapMxConsentStatus gdprConsent;
  final NapMxConsentStatus usSaleConsent;
  final NapMxConsentStatus childDirected;
  final NapMxConsentStatus underAgeOfConsent;

  /// IAB US Privacy string, for example `1YNN`. The host CMP owns this value.
  final String? usPrivacyString;

  Map<String, Object?> toMap() => <String, Object?>{
        'gdprConsent': gdprConsent.name,
        'usSaleConsent': usSaleConsent.name,
        'childDirected': childDirected.name,
        'underAgeOfConsent': underAgeOfConsent.name,
        'usPrivacyString': usPrivacyString,
      };
}

enum NapMxLogLevel { none, error, info, debug }

/// Initialization values for one app and one nap mx media key.
@immutable
final class NapMxConfiguration {
  NapMxConfiguration({
    required this.mediaKey,
    required Map<NapMxAdFormat, String> adUnitIds,
    this.privacy = const NapMxPrivacySettings(),
    this.logLevel = NapMxLogLevel.error,
    this.testMode = false,
    this.testDeviceIds = const <String>[],
    Map<String, Map<String, String>> mediation = const {},
  })  : adUnitIds = Map.unmodifiable(adUnitIds),
        mediation = Map.unmodifiable(
          mediation.map((key, value) => MapEntry(key, Map.unmodifiable(value))),
        ) {
    if (mediaKey.trim().isEmpty) {
      throw ArgumentError.value(mediaKey, 'mediaKey', 'must not be empty');
    }
    if (adUnitIds.isEmpty || adUnitIds.values.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(
        adUnitIds,
        'adUnitIds',
        'must contain only non-empty IDs',
      );
    }
  }

  final String mediaKey;
  final Map<NapMxAdFormat, String> adUnitIds;
  final NapMxPrivacySettings privacy;
  final NapMxLogLevel logLevel;
  final bool testMode;
  final List<String> testDeviceIds;

  /// Optional network keys. Only installed native adapters consume entries.
  final Map<String, Map<String, String>> mediation;

  String? adUnitIdFor(NapMxAdFormat format) => adUnitIds[format];

  Map<String, Object?> toMap() => <String, Object?>{
        'mediaKey': mediaKey.trim(),
        'adUnitIds': <String, String>{
          for (final entry in adUnitIds.entries)
            entry.key.wireName: entry.value.trim(),
        },
        'privacy': privacy.toMap(),
        'logLevel': logLevel.name,
        'testMode': testMode,
        'testDeviceIds': testDeviceIds,
        'mediation': mediation,
      };
}

@immutable
final class NapMxSdkInfo {
  const NapMxSdkInfo({
    required this.platform,
    required this.pluginVersion,
    this.sdkVersion,
    this.adapterVersions,
  });

  factory NapMxSdkInfo.fromMap(Map<Object?, Object?> map) => NapMxSdkInfo(
        platform: map['platform'] as String? ?? 'unknown',
        pluginVersion: map['pluginVersion'] as String? ?? 'unknown',
        sdkVersion: map['sdkVersion'] as String?,
        adapterVersions: map['adapterVersions'] as String?,
      );

  final String platform;
  final String pluginVersion;
  final String? sdkVersion;
  final String? adapterVersions;
}
