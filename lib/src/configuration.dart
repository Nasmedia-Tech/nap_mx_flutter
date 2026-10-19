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
///
/// [unspecified] never means consent; it leaves the value unset so the host
/// CMP or installed native SDK policy remains authoritative.
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

  /// Whether the user granted GDPR personalization consent.
  final NapMxConsentStatus gdprConsent;

  /// US privacy sale/share choice; denied represents an opt-out.
  final NapMxConsentStatus usSaleConsent;

  /// Whether the app/request is directed to children for COPPA purposes.
  final NapMxConsentStatus childDirected;

  /// Whether the user is below the GDPR age of consent.
  ///
  /// The Android Core has no matching setter and rejects an explicit value.
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
///
/// Register every placement before initialization using [adUnitIds],
/// [additionalAdUnitIds], or both. At least one non-empty ID is required.
/// The native SDK receives their combined, deduplicated values.
@immutable
final class NapMxConfiguration {
  NapMxConfiguration({
    required this.mediaKey,
    Map<NapMxAdFormat, String> adUnitIds = const {},
    List<String> additionalAdUnitIds = const [],
    this.privacy = const NapMxPrivacySettings(),
    this.logLevel = NapMxLogLevel.error,
    this.testMode = false,
    this.testDeviceIds = const <String>[],
    Map<String, Map<String, String>> mediation = const {},
  })  : adUnitIds = Map.unmodifiable(adUnitIds),
        additionalAdUnitIds = List.unmodifiable(additionalAdUnitIds),
        mediation = Map.unmodifiable(
          mediation.map((key, value) => MapEntry(key, Map.unmodifiable(value))),
        ) {
    if (mediaKey.trim().isEmpty) {
      throw ArgumentError.value(mediaKey, 'mediaKey', 'must not be empty');
    }
    if ((adUnitIds.isEmpty && additionalAdUnitIds.isEmpty) ||
        [...adUnitIds.values, ...additionalAdUnitIds]
            .any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(
        adUnitIds,
        'adUnitIds',
        'must contain only non-empty IDs',
      );
    }
  }

  /// App-level nap mx Media Key.
  ///
  /// iOS requires decimal digits even though the cross-platform type is String.
  final String mediaKey;

  /// Optional format-to-ID lookup for the app's default placements.
  ///
  /// Omit this map when registering all placements in [additionalAdUnitIds].
  /// Controllers and views still require an explicit ID; they do not select
  /// defaults automatically. iOS requires decimal integer strings.
  final Map<NapMxAdFormat, String> adUnitIds;

  /// Additional placements registered with the native SDK, without format keys.
  ///
  /// May contain multiple IDs of the same format, or all IDs when [adUnitIds]
  /// is omitted. Pass the desired ID explicitly when loading an ad.
  /// iOS requires decimal integer strings.
  final List<String> additionalAdUnitIds;

  /// Privacy choices forwarded before nap mx native initialization.
  final NapMxPrivacySettings privacy;

  /// Native SDK diagnostic verbosity.
  final NapMxLogLevel logLevel;

  /// Android global test mode. iOS rejects true because no equivalent API exists.
  final bool testMode;

  /// Android native test-device identifiers, if officially assigned.
  final List<String> testDeviceIds;

  /// Optional Android adapter configuration consumed only by installed adapters.
  ///
  /// iOS rejects non-empty values; initialize iOS network SDKs in the host app.
  final Map<String, Map<String, String>> mediation;

  /// Returns the default ID in [adUnitIds] for [format], or null if absent.
  ///
  /// Does not search [additionalAdUnitIds] or check native registration.
  String? adUnitIdFor(NapMxAdFormat format) => adUnitIds[format];

  Map<String, Object?> toMap() => <String, Object?>{
        'mediaKey': mediaKey.trim(),
        'adUnitIds': <String, String>{
          for (final entry in adUnitIds.entries)
            entry.key.wireName: entry.value.trim(),
        },
        'additionalAdUnitIds': additionalAdUnitIds
            .map((id) => id.trim())
            .toSet()
            .toList(growable: false),
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

  /// `android`, `ios`, or a platform-specific fallback value.
  final String platform;

  /// Version of this Flutter plugin implementation.
  final String pluginVersion;

  /// Native Core/Mediation version when reported by the SDK.
  final String? sdkVersion;

  /// Installed adapter information when exposed by the native platform.
  final String? adapterVersions;
}
