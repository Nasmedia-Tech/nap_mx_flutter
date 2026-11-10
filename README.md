# nap_mx_flutter

[![CI](https://github.com/Nasmedia-Tech/nap_mx_flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/Nasmedia-Tech/nap_mx_flutter/actions/workflows/ci.yml)

Android와 iOS의 [nap mx SDK](https://napmx.github.io/)를 같은 타입 기반 Dart API로 연결하는 Flutter 플러그인입니다. 배너·네이티브·인라인 동영상은 SDK의 네이티브 뷰를 그대로 표시하고, 전면·전면 동영상·리워드는 SDK 표시 API를 사용합니다.

> 초기 공개 버전입니다. `pub.dev`에는 배포하지 않으며 Git 태그로 설치합니다.

## 문서 바로가기

- 설치부터 출시 전 점검까지는 [nap mx Flutter SDK (Beta) 공식 가이드](https://napmx.github.io/#/flutter/)에 정리되어 있습니다.
- 처음 연동하거나 운영 앱에 적용할 때는 [상세 연동 가이드](doc/integration-guide.md)를 순서대로 진행하세요.
- 실행 가능한 전체 화면은 [Sample 앱](example/lib/main.dart)에서 확인할 수 있습니다.
- 네이티브 SDK 설정과 네트워크별 요구사항은 [nap mx 공식 가이드](https://napmx.github.io/)를 따릅니다.

아래 Quick Start는 이미 nap mx 연동 경험이 있는 개발자를 위한 축약본입니다. 개인정보 동의, 선택 어댑터, 앱 수명주기와 보상 중복 방지는 상세 가이드에서 설명합니다.

## 요구사항과 고정 버전

`v0.1.10` 기준입니다.

| 항목 | 최소/고정 버전 |
|---|---|
| Flutter / Dart | Flutter 3.24+, Dart 3.5+ (CI: Flutter 3.44.9) |
| Android | API 21+, compile SDK 36, Java 17; AGP 8.10.1+ / Kotlin 2.1.0+ (권장 2.2.10) |
| nap mx Android | `admixer-ssp:2.5.1` (공식 BOM `2026.11.02`) |
| iOS | iOS 13+, Xcode 16+, Swift 5.9 |
| nap mx iOS | `AdMixerMediation` 2.6.1 + `AdMixer` 1.5.1 |

선택 어댑터에 따라 최소 OS가 올라갑니다. Android Google/Naver는 API 23, AppLovin/GMA NextGen은 API 24가 필요하고, iOS AdFit/Teads는 iOS 14가 필요합니다. iOS Teads는 Xcode 26 이상이 필요합니다.

Android 플러그인은 호스트의 AGP·Kotlin 버전을 사용합니다. AGP 8 호스트는 `android/settings.gradle(.kts)`에서 `org.jetbrains.kotlin.android`를 버전과 함께 선언하고, 앱 모듈에도 적용하세요. 플러그인 모듈에는 자동으로 적용합니다. 예제와 CI는 AGP 8.10.1 / Gradle 8.11.1에서 Kotlin 2.1.0 및 2.2.10 조합을 검증합니다. SDK 2.5.0의 `kotlin-stdlib` 의존성은 2.2.10이며, 호스트 컴파일러와 별도로 해석됩니다. stdlib를 2.1.0으로 강제 낮추지 마세요.

AGP 9에서 `android.builtInKotlin=false`를 사용하는 호스트도 같은 방식으로 Kotlin 플러그인을 선언해야 합니다. AGP 9의 내장 Kotlin이 활성화된 모듈에는 별도 Kotlin Android 플러그인을 적용하지 않습니다. Flutter 3.44의 AGP 9 연동은 `android.builtInKotlin=false`와 `android.newDsl=false`가 필요하며, 내장 Kotlin을 켠 Flutter 앱은 Flutter 3.47 이상이 필요합니다. 자세한 내용은 [Flutter 공식 가이드](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors)를 확인하세요.

## 지원 범위

| 포맷 | Android | iOS | Flutter API |
|---|---|---|---|
| 배너 | 지원 | 지원 | `NapMxAdView` |
| 전면 | 지원 | 지원 | `NapMxFullscreenAdController` |
| 네이티브 | 지원 | 지원 | `NapMxAdView` (SDK 네이티브 템플릿) |
| 인스트림(인라인) 동영상 | 지원 | 지원 | `NapMxAdView` |
| 아웃스트림(전면) 동영상 | 지원 | 지원 | `NapMxFullscreenAdController` |
| 리워드 동영상 | 지원 | 지원 | `NapMxFullscreenAdController` |

| 네트워크 | Android 공식 어댑터 | iOS 공식 어댑터 |
|---|---|---|
| nap mx 자체 광고 | Core 내장 | Core 내장 |
| Google Ad Manager | `admixer-admanager` | `AdMixerMediationGAM` |
| Google Mobile Ads NextGen | `admixer-gma-nextgen` (beta) | 미지원 |
| Naver Ad Manager | `admixer-naveradmanager` | `AdMixerMediationNAM` |
| Kakao AdFit | `admixer-adfit` | `AdMixerMediationAdFit` |
| Pangle | `admixer-pangle` | `AdMixerMediationPangle` |
| AppLovin | `admixer-applovin` | `AdMixerMediationAppLovin` |
| Unity Ads | `admixer-unity` | `AdMixerMediationUnityAds` |
| Teads | `admixer-teads` | `AdMixerMediationTeads` |

어느 네트워크의 광고가 나갈지는 nap mx 서버 설정과 각 네트워크의 지원 포맷·정책에 따라 정해집니다. 앱에서 네트워크를 지정하는 API는 없습니다.

## Quick Start

### 1. 설치

`pubspec.yaml`에 추가합니다.

```yaml
dependencies:
  nap_mx_flutter:
    git:
      url: https://github.com/Nasmedia-Tech/nap_mx_flutter.git
      ref: v0.1.10
```

```bash
flutter pub get
```

### 2. 플랫폼 설정

플러그인에는 Core SDK만 들어 있습니다. 미디에이션 어댑터는 사용하는 것만 앱에 추가합니다.

Android 앱의 `android/app/build.gradle.kts` 예시:

```kotlin
dependencies {
    implementation(platform("io.github.nasmedia-tech:admixer-bom:2026.11.02"))
    implementation("io.github.nasmedia-tech:admixer-admanager") // 선택
    // implementation("io.github.nasmedia-tech:admixer-pangle") // 선택
}
```

AdFit, Pangle, Teads는 앱의 `android/build.gradle(.kts)` `allprojects` 블록에 각 공식 Maven 저장소를 추가해야 합니다. Google Ad Manager 사용 시 발급받은 앱 ID도 필요합니다.

Google 광고 ID는 Core의 API 21 호환 `18.0.0`을 사용합니다. 앱의 `minSdk`가 23 이상이면 최신 수정판 `18.3.0`을 선택할 수 있습니다. 구형 Android 크래시가 있는 `18.2.0`은 사용하지 마세요.

```xml
<!-- android/app/src/main/AndroidManifest.xml의 application 안 -->
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-################~##########" />
```

플러그인과 네이티브 SDK의 R8(코드 축소·난독화) 규칙은 빌드할 때 자동으로 적용됩니다. 선택 네트워크에 별도 규칙이 필요하면 해당 네트워크 가이드를 따르세요.

iOS는 Flutter Swift Package Manager 또는 CocoaPods를 사용할 수 있습니다. 플러그인은 Mediation 2.6.1과 Core 1.5.1을 고정합니다. 선택 네트워크는 Xcode의 Package Dependencies에 [공식 SPM 패키지](https://napmx.github.io/#/ios/native/getting-started)를 추가하거나 `Podfile`에 필요한 Pod만 추가합니다.

```ruby
pod 'AdMixerMediationGAM'      # 선택
pod 'AdMixerMediationPangle'   # 선택
```

Google 사용 시 `GADApplicationIdentifier`, 추적을 요청할 경우 `NSUserTrackingUsageDescription`, 사용하는 네트워크의 SKAdNetwork ID가 필요합니다. 최신 목록은 [공식 iOS 설정 가이드](https://napmx.github.io/#/ios/native/getting-started)를 기준으로 적용하세요. 플러그인과 Core SDK에는 Privacy Manifest가 들어 있습니다. 앱 자체와 선택 네트워크 SDK의 개인정보 항목은 앱에서 따로 작성해야 합니다.

iOS의 Pangle, AppLovin, Unity Ads 등 네트워크별 초기화는 각 공식 가이드에 따라 `AppDelegate`/`SceneDelegate`에서 수행합니다. 개인정보 신호를 먼저 확정한 뒤 네트워크 SDK를 초기화하세요. Android 어댑터는 의존성만 추가하면 자동으로 등록되고, 처음 사용할 때 초기화됩니다.

### 3. 개인정보 신호와 초기화

값을 설정하지 않으면 동의한 것으로 처리하지 않습니다. 동의 관리 도구(CMP)의 결과는 초기화 전에 전달하세요. iOS ATT 권한 요청은 플러그인이 하지 않으므로 앱에서 직접 요청합니다.

```dart
await NapMx.initialize(
  NapMxConfiguration(
    mediaKey: 'YOUR_MEDIA_KEY',
    // 사용할 모든 지면 ID를 목록으로 등록합니다.
    additionalAdUnitIds: [
      'YOUR_BANNER_ID',
      'YOUR_INTERSTITIAL_ID',
      'YOUR_REWARDED_ID',
    ],
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

#### 같은 포맷의 여러 지면 등록

기존 `adUnitIds` 맵을 유지하면서 `additionalAdUnitIds: List<String>`로 같은 포맷의 추가 지면을 등록할 수 있습니다. 맵을 생략하고 목록만 사용할 수도 있습니다.

```dart
await NapMx.initialize(NapMxConfiguration(
  mediaKey: '123', // 실제 발급값으로 교체
  additionalAdUnitIds: ['789', '790'], // 리워드 지면 A, B의 예시 ID
));
final placementB = NapMxFullscreenAdController(
  format: NapMxAdFormat.rewarded,
  adUnitId: '790',
);
await placementB.load();
// 화면 수명에 맞춰 placementB.dispose()를 호출하세요.
```

두 컬렉션을 합쳐 공백과 중복 ID를 제거한 뒤 네이티브 SDK 초기화에 전달합니다. iOS에서는 모든 ID가 정수 문자열이어야 합니다. 두 컬렉션이 모두 비었거나 빈 ID가 포함되면 `ArgumentError`가 발생합니다.

컨트롤러와 광고 뷰에는 사용할 ID를 명시하세요. `adUnitIdFor(format)`은 기존 맵만 조회합니다. 초기화 후 재호출하여 ID를 추가할 수 없으므로 사용할 지면을 처음에 모두 등록해야 합니다. 등록하지 않은 ID로 요청하면 SDK에 그대로 전달되지만, 정상 동작은 보장하지 않습니다.

자세한 내용은 [다중 지면 등록 가이드](doc/integration-guide.md#61-같은-포맷의-여러-지면-등록)를 참고하세요.

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

네이티브 광고는 SDK의 템플릿 뷰를 그대로 표시합니다. 광고 표기, AdChoices, CTA 버튼, 미디어 영역이 SDK 규격대로 유지됩니다.

### 5. 전면·전면 동영상·리워드

```dart
final ad = NapMxFullscreenAdController(
  format: NapMxAdFormat.rewarded,
  adUnitId: 'YOUR_REWARDED_ID',
);

final subscription = ad.events.listen((event) {
  if (event.type == NapMxEventType.rewarded) {
    // SDK가 보상 지급을 알릴 때만 발생합니다. transactionId로 중복 지급을 막으세요.
    grantRewardOnce(event.reward!.transactionId);
  }
});

await ad.load();
await ad.show();

// 화면 수명 종료 시
await subscription.cancel();
await ad.dispose();
```

서버 간 보상 확인(S2S 콜백)을 쓰면 앱과 서버에 같은 `transaction_id`가 전달됩니다. `(adunit_id, transaction_id)` 조합으로 중복 지급을 막으세요. 콜백 URL 등록과 재시도 정책은 [공식 Flutter 리워드 가이드](https://napmx.github.io/#/flutter/ad-formats)를 확인하세요.

controller 하나로는 광고 한 개만 요청합니다. `load → show → dispose` 순서로 사용하고, 다음 광고는 새 controller로 요청하세요.

## Sample 앱

공용 테스트 ID가 없으므로, 테스트 ID를 넣기 전에는 예제 앱이 광고를 요청하지 않습니다. 운영 담당자에게 받은 테스트 값은 로컬 파일에만 저장하세요.

```bash
cd example
cp config/example.json config/local.json
# config/local.json에 테스트 값을 입력 (Git 추적 제외)
flutter run --dart-define-from-file=config/local.json
```

예제 앱의 이벤트 로그에서 포맷별 상태, 오류 코드, 응답 네트워크(SDK가 알려 준 경우), 소요 시간, 보상 transaction ID를 볼 수 있습니다. 다크 모드, 작은 화면, 큰 글자 설정에서도 확인할 수 있습니다.

## 선택 어댑터 버전

Android는 아래 공식 배포 버전을 BOM으로 고정합니다.

| 어댑터 | 버전 | 추가 조건 |
|---|---:|---|
| AdManager | 2.1.6 | API 23+, Kotlin 2.1+ |
| Naver / Teads | 2.1.4 | Naver는 API 23+, Kotlin 2.1+ |
| GMA NextGen | 2.1.5 | beta·API 24+, AdManager와 택1 |
| Pangle | 2.1.3 | Core 2.3.3 이상 |
| AdFit / Unity | 2.0.7 | Core 2.3.3 이상, AdFit은 Kotlin 2.0+ |
| AppLovin | 2.0.7 | Core 2.3.3 이상, API 24+ |

iOS 어댑터와 그 하위 네트워크 SDK의 허용 범위는 릴리스별로 바뀔 수 있으므로 [공식 최신 표](https://napmx.github.io/#/ios/native/getting-started)를 확인하세요. Core와 어댑터 버전을 임의로 섞지 마세요.

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

CI는 self-hosted macOS(ARM64) 러너에서 format·analyze·테스트·pub dry-run, Android debug/release 빌드와 단위 테스트(Kotlin 2.1.0·2.2.10), iOS 시뮬레이터 빌드와 XCTest를 실행합니다.

## 주요 오류

| 증상 | 확인할 항목 |
|---|---|
| `invalid_configuration` / `invalid_ad_unit` | 빈 키/ID, iOS에서 숫자가 아닌 Media Key·AdUnit ID |
| `not_initialized` | `NapMx.initialize` 완료 전에 요청했는지 확인 |
| `NapMxError.isNoFill == true` | 테스트 지면, 서버 워터폴, 광고 재고 확인 |
| `load_failed`와 어댑터 관련 native code | 선택 어댑터 의존성, 저장소, 앱 ID 및 네트워크 초기화 확인 |
| `timeout` | 네트워크 상태와 기본 제한 시간(30초) 확인. 바로 반복 재요청하지 않기 |
| show 실패 | load 성공 이벤트 이후 같은 controller에서 show했는지 확인 |

Android 백그라운드 복귀나 Activity 재생성 시 플러그인은 현재 Activity를 다시 연결하고, 배너·네이티브·인라인 동영상 View에 SDK가 요구하는 `onResume`/`onPause`를 호스트 Activity 상태에 맞춰 전달합니다. iOS는 현재 활성화된 화면(Scene)의 ViewController에 광고를 표시합니다. 화면을 닫을 때 controller를 dispose하세요. 그 뒤에 도착하는 콜백은 무시됩니다.

리워드는 예외입니다. 네이티브 SDK는 보상(`rewarded`)과 닫힘(`closed`)의 도착 순서를 보장하지 않으므로, `closed`를 받자마자 controller를 dispose하면 뒤늦게 도착하는 보상 콜백을 놓칠 수 있습니다. 플러그인은 닫힘 이후에도 네이티브 광고를 짧은 유예 시간 동안 유지하지만, 앱도 `rewarded`를 받았거나 유예 시간이 지난 뒤에 dispose해야 합니다. 지급 누락을 막으려면 S2S 콜백도 함께 사용하세요.

## 보안과 라이선스

실제 Media Key, AdUnit ID, 서명키, 인증서, `google-services.json`, `GoogleService-Info.plist`는 커밋하지 마세요. 이 저장소에는 예시 값만 들어 있습니다. 이 플러그인은 Apache-2.0이며, 다운로드되는 nap mx SDK와 선택 네트워크 SDK는 각자의 라이선스와 재배포 조건을 따릅니다. 자세한 내용은 [LICENSE](LICENSE)와 [NOTICE](NOTICE)를 확인하세요.
