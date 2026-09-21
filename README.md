# nap_mx_flutter

[![CI](https://github.com/Nasmedia-Tech/nap_mx_flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/Nasmedia-Tech/nap_mx_flutter/actions/workflows/ci.yml)

Android와 iOS의 [nap mx SDK](https://napmx.github.io/)를 같은 타입 기반 Dart API로 연결하는 Flutter 플러그인입니다. 배너·네이티브·인라인 동영상은 SDK의 네이티브 뷰를 그대로 표시하고, 전면·전면 동영상·리워드는 SDK 표시 API를 사용합니다.

> 이 저장소는 초기 공개 버전입니다. `pub.dev`에는 아직 배포하지 않았으며 Git 의존성으로 설치합니다. 운영 전 반드시 발급받은 테스트 지면으로 두 플랫폼의 실기기 검증을 완료하세요.

## 문서 바로가기

- 처음 연동하거나 운영 앱에 적용할 때는 [상세 연동 가이드](doc/integration-guide.md)를 순서대로 진행하세요.
- 실행 가능한 전체 화면은 [Sample 앱](example/lib/main.dart)에서 확인할 수 있습니다.
- 네이티브 SDK 원문과 최신 네트워크 요구사항은 [nap mx 공식 가이드](https://napmx.github.io/)를 기준으로 합니다.

아래 Quick Start는 이미 nap mx 연동 경험이 있는 개발자를 위한 축약본입니다. 개인정보 동의, 선택 어댑터, 앱 수명주기와 보상 중복 방지는 상세 가이드에서 설명합니다.

## 요구사항과 고정 버전

| 항목 | 최소/고정 버전 |
|---|---|
| Flutter / Dart | Flutter 3.24+, Dart 3.5+ (CI: Flutter 3.44.9) |
| Android | API 21+, compile SDK 36, Java 17, Kotlin 2.3.20 |
| nap mx Android | `admixer-ssp:2.3.0` (공식 BOM `2026.09.03`) |
| iOS | iOS 13+, Xcode 16+, Swift 5.9 |
| nap mx iOS | `AdMixerMediation` 2.5.0 + `AdMixer` 1.3.0 |

선택 어댑터에 따라 최소 OS가 올라갑니다. Android Google/Naver는 API 23, AppLovin/GMA NextGen은 API 24가 필요하고, iOS AdFit/Teads는 iOS 14가 필요합니다. iOS Teads는 Xcode 26 이상이 필요합니다.

## 지원 범위

`지원`은 공개 SDK API와 플러그인 경로가 구현되었다는 뜻입니다. 네트워크별 실제 광고 응답은 계정·애드유닛·재고·심사에 의존하므로 CI 컴파일만으로 검증된 것으로 표시하지 않습니다.

| 포맷 | Android | iOS | Flutter 표현 |
|---|---|---|---|
| 배너 | 지원 | 지원 | `NapMxAdView` / 실제 SDK 뷰 |
| 전면 | 지원 | 지원 | `NapMxFullscreenAdController` |
| 네이티브 | 지원 | 지원 | SDK binder/네이티브 템플릿을 포함한 실제 SDK 뷰 |
| 인스트림(인라인) 동영상 | 지원 | 지원 | `NapMxAdView` / 실제 SDK 뷰 |
| 아웃스트림(전면) 동영상 | 지원 | 지원 | `NapMxFullscreenAdController` |
| 리워드 동영상 | 지원 | 지원 | 실제 SDK reward 콜백만 전달 |

| 네트워크 | Android 공식 어댑터 | iOS 공식 어댑터 | 이 저장소 실기기 검증 |
|---|---|---|---|
| nap mx 자체 광고 | Core 내장 | Core 내장 | 미검증 |
| Google Ad Manager | `admixer-admanager` | `AdMixerMediationGAM` | 미검증 |
| Google Mobile Ads NextGen | `admixer-gma-nextgen` (beta) | 미지원 | 미검증 |
| Naver Ad Manager | `admixer-naveradmanager` | `AdMixerMediationNAM` | 미검증 |
| Kakao AdFit | `admixer-adfit` | `AdMixerMediationAdFit` | 미검증 |
| Pangle | `admixer-pangle` | `AdMixerMediationPangle` | 미검증 |
| AppLovin | `admixer-applovin` | `AdMixerMediationAppLovin` | 미검증 |
| Unity Ads | `admixer-unity` | `AdMixerMediationUnityAds` | 미검증 |
| Teads | `admixer-teads` | `AdMixerMediationTeads` | 미검증 |

포맷별로 어느 네트워크가 응답하는지는 nap mx 서버 설정과 각 네트워크의 지원 포맷·정책에 따릅니다. 특정 네트워크를 강제로 선택하는 API는 제공하지 않습니다.

## Quick Start

### 1. 설치

`pubspec.yaml`에 추가합니다.

```yaml
dependencies:
  nap_mx_flutter:
    git:
      url: https://github.com/Nasmedia-Tech/nap_mx_flutter.git
      ref: v0.1.1
```

```bash
flutter pub get
```

### 2. 플랫폼 설정

코어 SDK만 플러그인이 가져오며 미디에이션 어댑터는 사용하는 것만 앱에 추가합니다.

Android 앱의 `android/app/build.gradle.kts` 예시:

```kotlin
dependencies {
    implementation(platform("io.github.nasmedia-tech:admixer-bom:2026.09.03"))
    implementation("io.github.nasmedia-tech:admixer-admanager") // 선택
    // implementation("io.github.nasmedia-tech:admixer-pangle") // 선택
}
```

AdFit, Pangle, Teads는 앱의 `settings.gradle(.kts)`에 각 공식 Maven 저장소를 추가해야 합니다. Google Ad Manager 사용 시 발급받은 앱 ID도 필요합니다.

```xml
<!-- android/app/src/main/AndroidManifest.xml의 application 안 -->
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-################~##########" />
```

플러그인의 consumer R8 규칙과 네이티브 SDK 규칙이 자동 병합됩니다. 선택 네트워크가 별도 규칙을 요구하면 해당 네트워크 공식 가이드를 함께 적용하세요.

iOS는 Flutter Swift Package Manager 또는 CocoaPods를 사용할 수 있습니다. 플러그인은 공식 가이드의 필수 구성인 Mediation 2.5.0과 Core 1.3.0을 고정합니다. 선택 네트워크는 Xcode의 Package Dependencies에 [공식 SPM 패키지](https://napmx.github.io/ios/native/getting-started)를 추가하거나 `Podfile`에 필요한 Pod만 추가합니다.

```ruby
pod 'AdMixerMediationGAM'      # 선택
pod 'AdMixerMediationPangle'   # 선택
```

Google 사용 시 `GADApplicationIdentifier`, 추적을 요청할 경우 `NSUserTrackingUsageDescription`, 사용하는 네트워크의 SKAdNetwork ID가 필요합니다. 최신 목록은 [공식 iOS 설정 가이드](https://napmx.github.io/ios/native/getting-started)를 기준으로 적용하세요. 플러그인과 Core SDK의 Privacy Manifest는 의존성에 포함되지만, 앱과 선택 SDK의 개인정보 선언 책임을 대신하지 않습니다.

iOS의 Pangle, AppLovin, Unity Ads 등 네트워크별 초기화는 각 공식 가이드에 따라 `AppDelegate`/`SceneDelegate`에서 수행합니다. 개인정보 신호를 먼저 확정한 뒤 네트워크 SDK를 초기화하세요. Android 어댑터는 클래스패스에서 자동 등록되고 필요 시 lazy 초기화됩니다.

### 3. 개인정보 신호와 초기화

미설정은 동의로 간주하지 않습니다. CMP 결과를 네이티브 SDK 초기화 전에 넘기세요. ATT 프롬프트 표시와 사용 목적 문구는 앱의 책임이며 이 플러그인은 ATT를 자동 요청하지 않습니다.

```dart
await NapMx.initialize(
  NapMxConfiguration(
    mediaKey: 'YOUR_MEDIA_KEY',
    adUnitIds: {
      NapMxAdFormat.banner: 'YOUR_BANNER_ID',
      NapMxAdFormat.interstitial: 'YOUR_INTERSTITIAL_ID',
      NapMxAdFormat.rewarded: 'YOUR_REWARDED_ID',
    },
    privacy: const NapMxPrivacySettings(
      gdprConsent: NapMxConsentStatus.unspecified,
      usSaleConsent: NapMxConsentStatus.unspecified,
      childDirected: NapMxConsentStatus.unspecified,
    ),
    logLevel: NapMxLogLevel.error,
  ),
);
```

Android의 Media Key와 AdUnit ID는 문자열입니다. iOS 네이티브 SDK는 Media Key와 AdUnit ID가 모두 정수이므로 플러그인이 숫자 문자열인지 검사하고 잘못된 값은 `invalid_configuration` 또는 `invalid_ad_unit`으로 실패시킵니다. 중복 초기화는 같은 설정에서만 허용됩니다.

### 4. 배너·네이티브·인라인 동영상

```dart
NapMxAdView(
  format: NapMxAdFormat.banner,
  adUnitId: 'YOUR_BANNER_ID',
  onViewCreated: (controller) async {
    controller.events.listen((event) => debugPrint('$event'));
    await controller.load();
    // 화면 수명 종료 시 await controller.dispose();
  },
)
```

네이티브 광고는 SDK가 노출·클릭을 등록한 템플릿을 사용합니다. Flutter에서 자산을 임의 재조합하지 않으며 광고 표기, AdChoices, CTA, 미디어 영역을 보존합니다.

### 5. 전면·전면 동영상·리워드

```dart
final ad = NapMxFullscreenAdController(
  format: NapMxAdFormat.rewarded,
  adUnitId: 'YOUR_REWARDED_ID',
);

final subscription = ad.events.listen((event) {
  if (event.type == NapMxEventType.rewarded) {
    // 실제 SDK 보상 콜백에서만 발생합니다. transactionId로 중복 지급을 막으세요.
    grantRewardOnce(event.reward!.transactionId);
  }
});

await ad.load();
await ad.show();

// 화면 수명 종료 시
await subscription.cancel();
await ad.dispose();
```

각 controller는 하나의 요청만 소유합니다. `load → show → dispose` 순서를 지키며, 요청 ID로 이벤트를 분리하고 timeout/no-fill/cancel/dispose 이후 콜백을 구분합니다.

## Sample 앱

공개 테스트 ID는 문서화되어 있지 않으므로 예제는 빈 ID로 광고 요청을 막습니다. 운영팀에서 발급받은 테스트 설정을 로컬 파일에만 저장하세요.

```bash
cd example
cp config/example.json config/local.json
# config/local.json에 테스트 값을 입력 (Git 추적 제외)
flutter run --dart-define-from-file=config/local.json
```

Material 3, 시스템 다크 모드, SafeArea, 작은 화면 스크롤과 글자 확대를 지원합니다. 광고 포맷별 상태·오류 코드·네트워크(실제 콜백에 있을 때만)·소요 시간·reward transaction ID를 이벤트 로그에서 확인할 수 있습니다. Mock 응답이나 광고 클릭 자동화는 없습니다.

## 선택 어댑터 버전

Android는 아래 공식 배포 버전을 BOM으로 고정합니다.

| 어댑터 | 버전 | 추가 조건 |
|---|---:|---|
| AdManager / Naver | 2.1.3 | API 23+, Kotlin 2.1+ |
| GMA NextGen / Pangle / Teads | 2.1.2 | NextGen은 beta·API 24+, AdManager와 택1 |
| AdFit / Unity | 2.0.6 | AdFit은 Kotlin 2.0+ |
| AppLovin | 2.0.5 | API 24+ |

iOS 어댑터와 그 하위 네트워크 SDK의 허용 범위는 릴리스별로 바뀔 수 있으므로 [공식 최신 표](https://napmx.github.io/ios/native/getting-started)를 확인하세요. Core와 어댑터 버전을 임의로 섞지 마세요.

## 테스트와 검증

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
dart pub publish --dry-run

cd example
flutter pub get
flutter test
flutter build apk --release
flutter build apk --debug
# macOS/Xcode 환경
flutter build ios --simulator --no-codesign
```

CI는 등록된 self-hosted macOS ARM64 runner에서 format/analyze/test/pub dry-run, Android debug/release, iOS Simulator 빌드를 실행합니다. runner가 한 대이면 두 job은 순차 실행됩니다. 실제 광고 노출·클릭·보상은 CI의 컴파일 성공과 별개이며 발급된 테스트 지면과 실기기에서 확인해야 합니다.

## 주요 오류

| 증상 | 확인할 항목 |
|---|---|
| `invalid_configuration` / `invalid_ad_unit` | 빈 키/ID, iOS에서 숫자가 아닌 Media Key·AdUnit ID |
| `not_initialized` | `NapMx.initialize` 완료 전에 요청했는지 확인 |
| `NapMxError.isNoFill == true` | 테스트 지면·서버 워터폴·재고 확인. 성공으로 재해석하지 않음 |
| `load_failed`와 어댑터 관련 native code | 선택 어댑터 의존성, 저장소, 앱 ID 및 네트워크 초기화 확인 |
| `timeout` | 네트워크 상태와 30초 기본 timeout 확인. 자동 무한 재요청 금지 |
| show 실패 | load 성공 이벤트 이후 같은 controller에서 show했는지 확인 |

Android 백그라운드 복귀나 Activity 재생성 시 플러그인은 현재 Activity를 다시 연결합니다. iOS는 foreground-active Scene의 ViewController를 메인 스레드에서 사용합니다. 화면 종료 시 controller를 dispose해 참조와 늦은 콜백을 해제하세요.

## 보안과 라이선스

실제 Media Key, AdUnit ID, 서명키, 인증서, `google-services.json`, `GoogleService-Info.plist`는 커밋하지 마세요. 공개 저장소에는 placeholder만 포함됩니다. 이 플러그인은 Apache-2.0이며, 다운로드되는 nap mx SDK와 선택 네트워크 SDK는 각자의 라이선스와 재배포 조건을 따릅니다. 자세한 내용은 [LICENSE](LICENSE)와 [NOTICE](NOTICE)를 확인하세요.
