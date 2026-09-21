# nap mx Flutter 상세 연동 가이드

이 문서는 `nap_mx_flutter`를 실제 Android·iOS Flutter 앱에 적용하는 매체 개발자를 위한 순서형 가이드입니다. 플러그인은 Flutter와 nap mx 네이티브 SDK 사이의 공통 API를 제공하지만, 매체 계정 발급, 개인정보 동의 UI, 선택 광고 네트워크의 앱 키와 네이티브 초기화는 호스트 앱의 책임입니다.

최신 네이티브 요구사항은 [nap mx 공식 가이드](https://napmx.github.io/)가 기준입니다. 이 문서의 검증 기준은 다음과 같습니다.

| 항목 | 고정/검증 버전 |
|---|---|
| Flutter CI | 3.44.9 |
| Android Core | `admixer-ssp:2.3.0` |
| Android BOM | `admixer-bom:2026.09.03` |
| iOS Mediation | `AdMixerMediation` 2.5.0 |
| iOS Core | `AdMixer` 1.3.0 |

## 1. 시작 전 준비

nap mx 운영 담당자를 통해 다음 값을 준비합니다.

- 앱당 하나의 Media Key
- 사용할 광고 포맷별 AdUnit ID
- 미디에이션 네트워크를 사용한다면 해당 네트워크의 App ID 또는 Publisher Key
- 운영 지면과 분리된 테스트용 지면

공개 범용 테스트 ID는 제공되지 않습니다. 값이 없을 때 운영 ID를 임의로 사용하거나 다른 앱의 ID를 복사하지 마세요.

플랫폼별 ID 형식도 다릅니다.

| 플랫폼 | Media Key | AdUnit ID |
|---|---|---|
| Android | 문자열 | 문자열 |
| iOS | 숫자로 변환 가능한 문자열 | 숫자로 변환 가능한 문자열 |

Dart API는 두 플랫폼을 함께 지원하기 위해 모두 `String`으로 받습니다. iOS 빌드에서는 예를 들어 `'12345'`는 허용되지만 `'banner-home'`은 초기화 또는 요청 단계에서 거부됩니다.

연동 책임은 다음처럼 구분합니다.

| 항목 | 플러그인 | 매체 앱 |
|---|---|---|
| nap mx Core 초기화 | 담당 | 설정값과 호출 시점 결정 |
| 광고 load/show/해제 | 담당 | 화면 수명주기와 UX 결정 |
| SDK 광고 View/클릭 등록 | 담당 | View를 임의 분해하지 않음 |
| CMP와 동의 UI | 자동 수행하지 않음 | 담당 |
| iOS ATT 요청 | 자동 수행하지 않음 | 담당 |
| 선택 네트워크 설치·App ID | 강제 설치하지 않음 | 담당 |
| iOS 선택 네트워크 초기화 | 자동 수행하지 않음 | 담당 |
| 보상 금액·중복 지급 방지 | transaction ID 전달 | 담당 |

## 2. 플러그인 설치

현재 `pub.dev`에는 배포하지 않습니다. 재현 가능한 빌드를 위해 브랜치가 아니라 태그를 지정합니다.

```yaml
dependencies:
  nap_mx_flutter:
    git:
      url: https://github.com/Nasmedia-Tech/nap_mx_flutter.git
      ref: v0.1.1 # 검증된 공개 태그. main을 사용하지 마세요.
```

```bash
flutter pub get
```

## 3. 키를 안전하게 주입하기

Media Key와 AdUnit ID를 Dart 소스, 공개 `.env`, CI 로그에 직접 넣지 않는 구성을 권장합니다. Sample 앱처럼 `--dart-define-from-file`을 사용할 수 있습니다.

```json
{
  "NAP_MX_MEDIA_KEY": "발급받은_MEDIA_KEY",
  "NAP_MX_BANNER_ID": "발급받은_BANNER_ID",
  "NAP_MX_REWARDED_ID": "발급받은_REWARDED_ID"
}
```

```bash
# 이 파일은 반드시 .gitignore에 포함합니다.
flutter run --dart-define-from-file=config/local.json
```

```dart
// 컴파일 시 주입한 값입니다. 값 자체를 로그에 출력하지 마세요.
const mediaKey = String.fromEnvironment('NAP_MX_MEDIA_KEY');
const bannerId = String.fromEnvironment('NAP_MX_BANNER_ID');
const rewardedId = String.fromEnvironment('NAP_MX_REWARDED_ID');
```

`--dart-define`은 소스 커밋을 막기 위한 방법이지 완전한 비밀 저장소는 아닙니다. 앱 바이너리에 포함되는 광고 식별 값은 추출될 수 있으므로 서버 비밀키나 관리 API 토큰을 넣어서는 안 됩니다.

## 4. Android 설정

플러그인은 nap mx Core를 포함합니다. 매체 앱은 실제 사용하는 선택 어댑터만 추가합니다.

### 4.1 선택 어댑터

앱 모듈의 `android/app/build.gradle.kts` 예시입니다.

```kotlin
dependencies {
    // nap mx 모듈 버전을 공식 검증 조합으로 정렬합니다.
    implementation(platform("io.github.nasmedia-tech:admixer-bom:2026.09.03"))

    // 아래에서 실제 사용하는 네트워크만 남깁니다.
    implementation("io.github.nasmedia-tech:admixer-admanager")       // Google Ad Manager
    // implementation("io.github.nasmedia-tech:admixer-naveradmanager") // Naver Ad Manager
    // implementation("io.github.nasmedia-tech:admixer-adfit")          // Kakao AdFit
    // implementation("io.github.nasmedia-tech:admixer-pangle")         // Pangle
    // implementation("io.github.nasmedia-tech:admixer-applovin")       // AppLovin
    // implementation("io.github.nasmedia-tech:admixer-unity")          // Unity Ads
    // implementation("io.github.nasmedia-tech:admixer-teads")          // Teads

    // beta: classic admixer-admanager와 동시에 넣지 않습니다.
    // implementation("io.github.nasmedia-tech:admixer-gma-nextgen")
}
```

Core만 사용할 때는 위 어댑터 의존성이 필요 없습니다. 모든 어댑터를 편의상 한꺼번에 설치하면 앱 크기, Manifest, 개인정보 선언과 네트워크 초기화 범위가 불필요하게 커집니다.

GMA NextGen을 선택했다면 classic Google Mobile Ads SDK가 함께 해석되지 않도록 공식 가이드의 전역 exclude가 추가로 필요합니다.

```kotlin
// admixer-gma-nextgen을 사용할 때만 적용합니다.
configurations.configureEach {
    exclude(group = "com.google.android.gms", module = "play-services-ads")
}
```

NextGen은 `admixer-admanager`와 함께 사용할 수 없으며 최소 API 24가 필요합니다. 도입 전 nap mx 운영 담당자와 지원 범위를 확인하세요.

### 4.2 추가 Maven 저장소

AdFit, Pangle, Teads를 사용할 때만 앱의 `android/settings.gradle.kts`에 필요한 저장소를 추가합니다.

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()

        // Kakao AdFit 사용 시
        maven("https://devrepo.kakao.com/nexus/content/groups/public/")

        // Pangle 사용 시
        maven("https://artifact.bytedance.com/repository/pangle/")

        // Teads 사용 시: 공식 가이드의 저장소를 모두 유지합니다.
        maven("https://sdk.teads.tv/android/repo")
        maven("https://teads.jfrog.io/artifactory/SDKAndroid-maven-prod")
        maven("https://developer.huawei.com/repo/")
    }
}
```

사용하지 않는 네트워크의 저장소는 추가하지 않아도 됩니다.

### 4.3 AndroidManifest

네트워크가 요구하는 값만 `<application>` 안에 추가합니다. 예를 들어 Google Ad Manager를 사용하는 경우:

```xml
<application ...>
    <!-- nap mx 운영 담당자로부터 전달받은 Google App ID를 사용합니다. -->
    <meta-data
        android:name="com.google.android.gms.ads.APPLICATION_ID"
        android:value="ca-app-pub-################~##########" />
</application>
```

Naver Ad Manager의 `com.naver.gfpsdk.PUBLISHER_CD`는 공식 어댑터에서 관리하므로 매체 앱 Manifest에 중복 선언하지 않습니다. 다른 네트워크 설정과 권한은 해당 네트워크의 최신 공식 문서를 함께 확인하세요.

### 4.4 Android 최소 요구사항

| 구성 | 최소 API |
|---|---:|
| Core, AdFit, Pangle, Unity, Teads | 21 |
| Google Ad Manager, Naver Ad Manager | 23 |
| AppLovin, GMA NextGen | 24 |

플러그인은 Java 17로 빌드됩니다. Google Ad Manager 어댑터를 추가하면 호스트 프로젝트에 Kotlin 2.1 이상이 필요할 수 있으므로 기존 앱의 AGP·Kotlin 조합을 확인하세요.

## 5. iOS 설정

플러그인의 Swift Package는 필수 Mediation 2.5.0과 Core 1.3.0을 함께 가져옵니다. 선택 네트워크 SDK는 매체 앱에서 추가합니다.

### 5.1 Swift Package Manager

Flutter SPM을 사용하는 앱은 다음 명령으로 활성화할 수 있습니다.

```bash
flutter config --enable-swift-package-manager
```

선택 네트워크를 사용하는 경우 Xcode의 **Package Dependencies**에서 해당 패키지만 앱 타깃에 연결합니다.

| 네트워크 | Package URL |
|---|---|
| Google Ad Manager | `https://github.com/Nasmedia-Tech/iOS-SSP-GAM-SPM.git` |
| Naver Ad Manager | `https://github.com/Nasmedia-Tech/iOS-SSP-NAM-SPM.git` |
| Kakao AdFit | `https://github.com/Nasmedia-Tech/iOS-SSP-AdFit-SPM.git` |
| Pangle | `https://github.com/Nasmedia-Tech/iOS-SSP-Pangle-SPM.git` |
| AppLovin | `https://github.com/Nasmedia-Tech/iOS-SSP-AppLovin-SPM.git` |
| Unity Ads | `https://github.com/Nasmedia-Tech/iOS-SSP-UnityAds-SPM.git` |
| Teads | `https://github.com/Nasmedia-Tech/iOS-SSP-Teads-SPM.git` |

SPM과 CocoaPods로 같은 네트워크 SDK를 중복 연결하지 마세요.

### 5.2 CocoaPods를 사용하는 호스트 앱

프로젝트가 CocoaPods 기반이면 사용하는 어댑터만 `Podfile`에 추가합니다.

```ruby
target 'Runner' do
  use_frameworks!

  # 플러그인의 필수 SDK는 podspec 의존성으로 설치됩니다.
  pod 'AdMixerMediationGAM'       # Google을 사용할 때만
  # pod 'AdMixerMediationNAM'     # Naver를 사용할 때만
  # pod 'AdMixerMediationPangle'  # Pangle을 사용할 때만
end
```

```bash
cd ios
pod install --repo-update
```

### 5.3 Info.plist, ATT, SKAdNetwork

ATT 요청은 플러그인이 자동으로 띄우지 않습니다. 추적 권한을 요청하는 앱만 사용자에게 실제 표시할 문구를 작성합니다.

```xml
<!-- ATT를 요청하는 앱에만 추가합니다. -->
<key>NSUserTrackingUsageDescription</key>
<string>맞춤형 광고 제공을 위해 기기 식별자 사용 권한이 필요합니다.</string>

<!-- Google Ad Manager 사용 시 발급받은 앱 ID로 교체합니다. -->
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-################~##########</string>
```

ATT를 사용한다면 앱이 active가 된 뒤 한 번만 요청합니다. 플러그인은 이 코드를 대신 실행하지 않습니다.

```swift
import AppTrackingTransparency

func sceneDidBecomeActive(_ scene: UIScene) {
    guard #available(iOS 14, *),
          ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
        return
    }

    ATTrackingManager.requestTrackingAuthorization { status in
        // status를 앱의 개인정보 정책과 CMP 흐름에 반영합니다.
        // 허용되지 않았다고 광고 요청을 성공으로 위장하지 않습니다.
    }
}
```

SKAdNetwork 목록은 선택한 네트워크와 버전에 따라 바뀌므로 이 저장소에 정적인 전체 목록을 복사하지 않습니다. 배포 전에 [공식 iOS 설정 가이드](https://napmx.github.io/ios/native/getting-started)의 최신 목록을 앱 `Info.plist`와 대조하세요.

플러그인과 Core의 Privacy Manifest가 앱 선언 전체를 대신하지는 않습니다. 앱이 수집하는 데이터와 선택 네트워크 SDK를 포함해 Xcode Privacy Report를 검토해야 합니다.

### 5.4 네트워크별 네이티브 초기화

iOS의 Google, Pangle, AppLovin, Unity, Naver 등은 각 SDK 초기화가 필요할 수 있습니다. 다음 순서를 지킵니다.

1. 앱의 CMP 또는 저장된 사용자 선택을 읽습니다.
2. 필요한 개인정보 신호를 확정합니다.
3. 네트워크 SDK가 초기화 시점에 읽는 동의 신호를 먼저 설정합니다.
4. `AppDelegate` 또는 활성 `SceneDelegate`에서 선택 네트워크 SDK를 초기화합니다.
5. Flutter에서 `NapMx.initialize`를 호출합니다.

네트워크 SDK를 Flutter 실행 전에 초기화한다면, 해당 네트워크가 초기화 시 읽는 동의 값도 Swift에서 먼저 설정해야 합니다. 나중에 전달되는 Dart `NapMxPrivacySettings`가 이미 끝난 네트워크 초기화를 소급해 바꾼다고 가정하지 마세요. nap mx Core에 전달하는 기본 형태는 다음과 같습니다.

```swift
import AdMixerMediation

// AppDelegate.didFinishLaunchingWithOptions 안에서,
// CMP/저장된 사용자 선택을 읽은 뒤 네트워크 초기화보다 먼저 실행합니다.
let consent = AMMConsent()
consent.gdprConsent = .granted       // 예시일 뿐, 실제 CMP 결과를 사용
consent.usSaleConsent = .denied      // denied = 판매/공유 옵트아웃
consent.childDirected = .denied      // granted = 아동 대상
consent.underAgeOfConsent = .denied  // granted = 동의 연령 미만
AMMediation.shared.setConsent(consent)

// 그 다음 설치한 네트워크 SDK만 각 공식 가이드에 따라 초기화합니다.
// GoogleMobileAds, Pangle, AppLovin, Unity, Naver 등을 사용하지 않으면
// 해당 SDK import와 초기화 코드도 넣지 않습니다.
```

위 `.granted`/`.denied`는 코드 형태를 보여주기 위한 예시이며 모든 사용자의 기본값이 아닙니다. CMP 결과가 없으면 동의로 바꾸지 않습니다. Naver Ad Manager는 공식 가이드에 따라 setup 후 같은 consent를 다시 설정해야 할 수 있습니다.

이 플러그인의 `mediation` 맵은 iOS 네트워크 초기화를 대신하지 않습니다. iOS에서 비어 있지 않은 `mediation`을 전달하면 `mediation_configuration_unsupported` 오류를 반환합니다.

## 6. 개인정보 신호와 SDK 초기화

초기화는 앱 프로세스에서 한 번만 수행합니다. 광고 화면마다 다시 초기화하지 마세요. 앱 시작 직후 무조건 호출하기보다 CMP/연령 설정 등 필요한 개인정보 판단이 끝난 시점에 호출합니다.

```dart
import 'package:nap_mx_flutter/nap_mx_flutter.dart';

Future<void> initializeAds() async {
  // 1) CMP 결과가 없으면 임의로 granted를 넣지 않습니다.
  // unspecified는 "동의"가 아니라, 플러그인이 해당 값을 설정하지 않는 상태입니다.
  const privacy = NapMxPrivacySettings(
    gdprConsent: NapMxConsentStatus.unspecified,
    usSaleConsent: NapMxConsentStatus.unspecified,
    childDirected: NapMxConsentStatus.unspecified,

    // iOS SDK는 지원하지만 Android Core에는 대응 setter가 없습니다.
    // 두 플랫폼 공용 구성에서는 unspecified를 유지하고,
    // Android 선택 네트워크에 필요한 설정은 호스트 앱에서 처리합니다.
    underAgeOfConsent: NapMxConsentStatus.unspecified,
  );

  await NapMx.initialize(
    NapMxConfiguration(
      mediaKey: mediaKey,

      // 실제로 사용하는 포맷만 등록해도 됩니다.
      // 등록하지 않은 포맷은 나중에 요청하지 마세요.
      adUnitIds: const {
        NapMxAdFormat.banner: bannerId,
        NapMxAdFormat.rewarded: rewardedId,
      },
      privacy: privacy,
      logLevel: NapMxLogLevel.error,

      // Android 공식 SDK의 테스트 모드입니다.
      // iOS에는 대응하는 전역 API가 없어 true로 설정하면 초기화가 실패합니다.
      // 공용 운영 코드는 false로 두고 발급받은 테스트 지면을 사용하세요.
      testMode: false,
    ),
  );
}
```

동시에 같은 설정으로 `NapMx.initialize`를 여러 번 호출하면 하나의 초기화 작업을 공유합니다. 이미 다른 설정으로 초기화된 뒤 재호출하면 `StateError`가 발생합니다. 계정 전환처럼 설정을 바꿔야 한다면 앱 프로세스를 새로 시작하는 구조로 설계하세요.

초기화 실패는 성공으로 간주하지 말고 광고 기능을 비활성화합니다.

```dart
try {
  await initializeAds();
} on NapMxError catch (error) {
  // 키 자체는 로그에 남기지 않습니다.
  debugPrint('nap mx init failed: ${error.code} / ${error.message}');
  // 광고가 없는 상태로 앱의 본 기능은 계속 제공하도록 처리합니다.
}
```

## 7. SDK 및 전체 이벤트 확인

`NapMx.events`는 모든 요청의 이벤트가 합쳐진 전역 스트림입니다. 분석 로그나 공통 모니터링에 사용하고, 개별 화면 로직은 controller의 필터링된 `events`를 사용하세요.

```dart
late final StreamSubscription<NapMxEvent> _allAdEvents;

void startAdMonitoring() {
  _allAdEvents = NapMx.events.listen((event) {
    // network는 SDK 콜백에서 실제 값을 제공한 경우에만 존재합니다.
    // null일 때 특정 네트워크라고 추정해서 기록하지 않습니다.
    debugPrint(
      'type=${event.type.name}, '
      'format=${event.format?.name}, '
      'network=${event.network ?? "not-reported"}, '
      'elapsedMs=${event.elapsedMilliseconds}',
    );
  });
}

Future<void> stopAdMonitoring() => _allAdEvents.cancel();
```

SDK 버전은 다음처럼 확인합니다.

```dart
final info = await NapMx.getSdkInfo();
debugPrint('plugin=${info.pluginVersion}, sdk=${info.sdkVersion ?? "unknown"}');
// 플랫폼 SDK가 어댑터 버전을 제공하지 않으면 adapterVersions는 null입니다.
```

## 8. 배너·네이티브·인라인 동영상

세 포맷은 실제 네이티브 SDK View를 `PlatformView`로 표시합니다. 네이티브 광고의 텍스트·이미지를 Flutter 위젯으로 분해해 다시 조립하면 SDK의 노출·클릭 등록을 우회할 수 있으므로 그렇게 사용하지 않습니다.

아래 위젯은 생성, 로드, 취소, 해제를 모두 포함한 예입니다.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nap_mx_flutter/nap_mx_flutter.dart';

class BannerSlot extends StatefulWidget {
  const BannerSlot({required this.adUnitId, super.key});

  final String adUnitId;

  @override
  State<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<BannerSlot> {
  NapMxAdViewController? _controller;
  StreamSubscription<NapMxEvent>? _events;
  String _status = 'waiting';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NapMxAdView(
          format: NapMxAdFormat.banner,
          adUnitId: widget.adUnitId,

          // 배너 기본 높이는 50입니다. 광고 슬롯의 실제 제약 안에 배치합니다.
          // 무한 높이 ListView 안에서는 SizedBox/ConstrainedBox를 함께 사용하세요.
          height: 50,
          autoLoad: false,
          onViewCreated: (controller) async {
            _controller = controller;
            _events = controller.events.listen((event) {
              if (!mounted) return;
              setState(() => _status = event.type.name);
            });

            try {
              // PlatformView가 생성된 뒤 한 번만 호출합니다.
              await controller.load();
            } catch (error) {
              if (mounted) setState(() => _status = 'failed: $error');
            }
          },
        ),
        Text(_status),
      ],
    );
  }

  @override
  void dispose() {
    // State.dispose는 async가 아니므로 기다리지 않고 정리를 시작합니다.
    // 이후 네이티브 콜백은 controller가 폐기 상태에서 무시합니다.
    unawaited(_events?.cancel());
    unawaited(_controller?.dispose());
    super.dispose();
  }
}
```

`NapMxAdFormat.native`의 기본 높이는 360, `inlineVideo`는 180입니다. `height`를 바꿀 수 있지만 네이티브 템플릿의 CTA, 광고 표기, 미디어 영역이 잘리지 않는지 작은 화면과 글자 확대 환경에서 확인하세요.

로드 중 화면이 사라지지만 View 자체는 재사용할 예정이면 `cancel()`을 호출할 수 있습니다. 다시 사용하지 않을 때는 반드시 `dispose()`를 호출합니다. dispose된 controller는 재사용할 수 없습니다.

## 9. 전면·전면 동영상

전면 포맷은 controller 하나가 요청 하나를 소유합니다. `load → show → dispose` 순서를 지킵니다.

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nap_mx_flutter/nap_mx_flutter.dart';

class InterstitialOwner {
  NapMxFullscreenAdController? _ad;
  StreamSubscription<NapMxEvent>? _events;

  Future<void> load(String adUnitId) async {
    // 이전 요청이 남아 있으면 먼저 해제합니다.
    await dispose();

    final ad = NapMxFullscreenAdController(
      format: NapMxAdFormat.interstitial,
      adUnitId: adUnitId,
      loadTimeout: const Duration(seconds: 30),
    );
    _ad = ad;

    // 이 스트림에는 이 controller의 requestId에 해당하는 이벤트만 들어옵니다.
    _events = ad.events.listen((event) {
      if (event.type == NapMxEventType.loadFailed) {
        debugPrint('load failed: ${event.error?.code}');
      }
    });

    // 네이티브 SDK가 로드 성공 또는 실패를 반환할 때 완료됩니다.
    await ad.load();
  }

  Future<void> show() async {
    final ad = _ad;
    if (ad == null || ad.state != NapMxAdState.loaded) {
      throw StateError('광고가 로드되지 않았습니다.');
    }

    // 사용자 액션 직후, 현재 화면이 활성 상태일 때 호출합니다.
    await ad.show();
  }

  Future<void> dispose() async {
    await _events?.cancel();
    _events = null;
    await _ad?.dispose();
    _ad = null;
  }
}
```

전면 동영상은 `NapMxAdFormat.interstitialVideo`만 바꾸면 같은 수명주기를 사용합니다. 앱이 백그라운드이거나 Android Activity/iOS ViewController가 아직 활성화되지 않은 시점에는 `show()`하지 마세요.

## 10. 리워드 광고와 중복 지급 방지

보상은 `show()` 성공, 동영상 완료 추정, 화면 닫힘 이벤트로 지급하지 않습니다. 오직 `NapMxEventType.rewarded`에서만 지급합니다.

```dart
import 'dart:async';

import 'package:nap_mx_flutter/nap_mx_flutter.dart';

final rewarded = NapMxFullscreenAdController(
  format: NapMxAdFormat.rewarded,
  adUnitId: rewardedId,
);

// show() Future는 광고가 닫힐 때가 아니라 "표시 성공" 콜백에서 완료됩니다.
// 따라서 closed 전까지 controller와 이벤트 구독을 유지합니다.
final closed = Completer<void>();
final subscription = rewarded.events.listen((event) {
  if (event.type == NapMxEventType.rewarded && event.reward != null) {
    final transactionId = event.reward!.transactionId;
    if (transactionId.isNotEmpty) {
      // 서버 또는 영속 저장소에서 transactionId의 유일성을 보장합니다.
      // 메모리 Set만으로는 앱 재시작/다중 기기 중복을 막을 수 없습니다.
      unawaited(rewardRepository.grantOnce(transactionId));
    }
  }

  if ((event.type == NapMxEventType.closed ||
          event.type == NapMxEventType.showFailed) &&
      !closed.isCompleted) {
    closed.complete();
  }
});

try {
  await rewarded.load();
  await rewarded.show();
  await closed.future;
} finally {
  await subscription.cancel();
  await rewarded.dispose();
}
```

보상 수량과 종류는 플러그인이 만들지 않습니다. 매체의 상품 정책과 서버 검증 결과를 기준으로 지급하세요. 빈 transaction ID가 전달될 가능성에 대한 정책도 백엔드와 합의하고, 임의 ID를 SDK transaction ID로 위장하지 마세요.

## 11. 이벤트 의미

| 이벤트 | 의미 | 일반적인 앱 처리 |
|---|---|---|
| `initializationSucceeded` | 네이티브 초기화 완료 | 광고 UI 활성화 |
| `loadStarted` | 요청 시작 | 로딩 상태 표시 |
| `loaded` | 표시 가능한 광고 로드 | 전면 광고 Show 버튼 활성화 |
| `loadFailed` | 로드 실패 | 오류 기록 후 UI 복구 |
| `shown` | SDK 표시 콜백 수신 | 노출 상태 기록 |
| `showFailed` | 표시 실패 | controller 해제 후 필요할 때 새 요청 |
| `clicked` | SDK 클릭 콜백 수신 | 분석 기록만 수행, 클릭 자동화 금지 |
| `completed` | 동영상 완료 콜백 | 보상 지급 근거로 사용하지 않음 |
| `skipped` | 동영상 건너뜀 | UI 상태 복구 |
| `rewarded` | SDK 보상 콜백 | transaction ID 기준 1회 지급 |
| `closed` | 전면 화면 닫힘 | 원래 화면 상태 복구 |
| `cancelled` | 요청 취소 | 필요할 때 새 controller 생성 |
| `disposed` | 네이티브 참조 해제 | controller 재사용 금지 |

`network`, `elapsedMilliseconds`, `nativeCode`처럼 SDK가 제공하지 않은 필드는 `null`일 수 있습니다. 추정값으로 채우지 마세요.

## 12. 오류 처리

동기 API 실패는 `NapMxError`, 잘못된 호출 순서는 `StateError`로 전달될 수 있습니다. 이벤트 스트림의 실패 이벤트에도 `NapMxError`가 포함됩니다.

```dart
try {
  await controller.load();
} on NapMxError catch (error) {
  if (error.isNoFill) {
    // no-fill은 정상적인 광고 재고 부족일 수 있습니다.
    // 성공으로 처리하거나 즉시 무한 재요청하지 않습니다.
    hideAdSlotTemporarily();
  } else if (error.isTimeout) {
    showContentWithoutAd();
  } else {
    reportAdError(error.code, error.nativeCode);
  }
} on StateError catch (error) {
  // 초기화 전 load, load 전 show, dispose 후 재사용 같은 앱 코드 오류입니다.
  debugPrint('invalid ad state: $error');
}
```

| 코드 | 원인과 확인 사항 |
|---|---|
| `invalid_configuration`, `invalid_ad_unit`, `invalid_request` | 키/ID 누락 또는 iOS 숫자 형식 오류 |
| `already_initialized` | 다른 값으로 중복 초기화 |
| `not_initialized` | 초기화 완료 전 광고 요청 |
| `already_loading`, `duplicate_request` | 같은 controller에 동시 요청 |
| `not_loaded` | 로드 성공 전 show 또는 로드 객체 소실 |
| `load_failed` | SDK 로드 실패. `nativeCode`와 공식 SDK 오류표 확인 |
| `timeout` | 플러그인 로드 제한 시간 초과 |
| `no_activity`, `no_view_controller` | 표시 가능한 활성 화면 없음 |
| `show_failed` | 네이티브 표시 실패 |
| `cancelled`, `disposed` | 요청 취소 또는 해제 후 접근 |
| `test_mode_unsupported` | iOS에서 전역 테스트 모드를 요청함 |
| `mediation_configuration_unsupported` | iOS에서 Android용 mediation 맵을 전달함 |
| `unsupported_privacy` | Android에서 지원하지 않는 under-age 값을 직접 전달함 |

어댑터 누락을 포함한 네이티브 실패는 보통 `load_failed`와 플랫폼별 `nativeCode`로 전달됩니다. Android의 `0x8000000x` 계열과 iOS의 `-1`부터 `-8` 코드는 각각 [공식 Android](https://napmx.github.io/android/native/error-codes)와 [공식 iOS](https://napmx.github.io/ios/native/getting-started) 오류표를 확인하세요.

## 13. 화면 및 앱 수명주기

- Android에서는 Flutter Activity가 재생성될 수 있습니다. 플러그인은 새 Activity를 다시 연결하지만, 이전 화면의 controller를 새 화면에서 재사용하지 않는 구성이 안전합니다.
- iOS에서는 foreground-active Scene의 ViewController가 필요합니다. 앱 시작 전이나 백그라운드에서 전면 광고를 표시하지 않습니다.
- 화면을 나갈 때 이벤트 구독과 controller를 함께 해제합니다.
- 화면 재진입 시 새 controller와 새 요청을 만듭니다.
- 앱 resume 직후 자동으로 광고를 무한 재요청하거나 자동 클릭하지 않습니다.
- 네트워크 전환, no-fill, timeout 재시도는 지수 backoff와 최대 횟수를 둔 매체 정책으로 관리합니다.

## 14. Sample 앱 실행

```bash
cd example

# Windows PowerShell
Copy-Item config/example.json config/local.json

# macOS/Linux
cp config/example.json config/local.json

# config/local.json에 발급받은 테스트 값 입력 후 실행
flutter run --dart-define-from-file=config/local.json
```

Sample 앱에서 다음을 확인할 수 있습니다.

- 초기화 전 요청 차단
- 포맷별 load/show/dispose 상태
- 오류 코드와 native code
- SDK가 실제 전달한 네트워크 이름
- 요청 소요 시간
- reward transaction ID
- 다크 모드, SafeArea, 작은 화면과 글자 확대

Mock은 사용하지 않으며 Sample 앱의 컴파일 성공은 실제 광고 수신 성공을 뜻하지 않습니다.

## 15. 출시 전 체크리스트

- [ ] Android와 iOS에 각각 올바른 Media Key/AdUnit ID를 사용했다.
- [ ] 운영 ID가 Git, 이슈, CI 로그에 노출되지 않았다.
- [ ] 사용하는 선택 어댑터만 설치했다.
- [ ] 네트워크별 App ID와 초기화를 완료했다.
- [ ] 개인정보 선택을 SDK 초기화보다 먼저 확정했다.
- [ ] ATT 요청 여부와 문구를 앱 정책에 맞게 결정했다.
- [ ] Privacy Manifest와 SKAdNetwork 목록을 실제 의존성 기준으로 검토했다.
- [ ] 배너·네이티브·동영상이 작은 화면과 글자 확대에서 잘리지 않는다.
- [ ] 전면 광고가 활성 화면에서 `load → show` 순서로 동작한다.
- [ ] 보상을 `rewarded` 콜백에서만 지급하고 transaction ID 중복을 차단했다.
- [ ] 화면 종료·재진입·백그라운드 복귀 후 늦은 콜백이 문제를 만들지 않는다.
- [ ] no-fill/timeout에 무한 재요청하지 않는다.
- [ ] 두 플랫폼 실기기에서 테스트 지면으로 최종 검증했다.

문제가 재현되면 플랫폼, 플러그인 버전, 네이티브 SDK 버전, 광고 포맷, 오류 code/nativeCode, 재현 순서를 정리하되 Media Key와 AdUnit ID 원문은 공개 이슈에 첨부하지 마세요.
