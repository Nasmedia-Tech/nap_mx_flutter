## 0.1.4

- Add `additionalAdUnitIds: List<String>` for multiple placements of any format,
  preserving the existing `adUnitIds` map and default-ID lookup. List-only
  initialization is supported.
- Forward combined, deduplicated IDs to Android and iOS initialization;
  include additional placements in Dart initialization equivalence checks.
- Fix iOS validation rejecting duplicate IDs registered across formats.
- Update the Korean README, publisher integration guide, sample documentation,
  and API comments with registration, explicit placement selection, and
  reinitialization constraints.

## 0.1.3

- Fix Android Kotlin compilation on AGP 8 and AGP 9 hosts with built-in
  Kotlin disabled. Use the host's AGP/Kotlin plugin versions instead of pinning
  a separate buildscript classpath; retain AGP 9 built-in Kotlin support.
- Move the example to AGP 8.10.1 / Kotlin 2.2.10 / Gradle 8.11.1.
- Add Android unit tests covering the 0.1.2 ad lifecycle fixes: host
  Activity lifecycle observation and its scoping to the attached Activity, the
  ad view registry, the banner listener being held in a field, and exactly-once
  reward delivery that survives the ad closing first. CI now runs them.
- Extract the reward gate and the host lifecycle contract behind internal seams
  so the above can be tested without a device. No behaviour change.

## 0.1.2

- Keep a closed full-screen ad alive briefly so a reward the network reports
  after the close callback still reaches the app, and stop gating reward
  delivery on teardown state. Reward delivery stays exactly-once.
- Hold the Android inline ad listener in a field. `AMMBannerView` keeps it in a
  `WeakReference`, so the previous request-scoped listener could be collected
  and the banner would silently stop reporting events.
- Forward the host Activity's `onResume`/`onPause` to Android banner, native,
  and inline-video views, which the native SDK requires.
- Document that `customParams` reach iOS on the rewarded format, correcting the
  previous claim that iOS ignores them.
- Document the `play-services-ads` 25.2.0 ceiling required by the Android SDK.

## 0.1.1

- Add a commented, publisher-oriented Android and iOS integration guide.
- Clarify platform-specific initialization, privacy, lifecycle, event, error, and reward handling.
- Normalize PlatformView channel failures to `NapMxError` and preserve no-fill/timeout flags.

## 0.1.0

- Add typed initialization, privacy, event, error, and request APIs.
- Add native banner, native-ad, and inline-video PlatformViews.
- Add interstitial, outstream-video, and rewarded controllers.
- Add Android SDK 2.3.0 and iOS SDK 2.5.0 integrations.
- Add a Material 3 example, tests, CI, and public integration guide.
