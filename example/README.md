# nap_mx_flutter example

모든 광고 요청은 상위 플러그인의 공개 Dart API만 사용합니다.

- 바로 실행하기: [상위 README의 Sample 앱](../README.md#sample-앱)
- 운영 앱에 적용하기: [상세 연동 가이드](../doc/integration-guide.md)
- 전체 화면 구현: [lib/main.dart](lib/main.dart)

`config/example.json`을 `config/local.json`으로 복사한 뒤 발급받은 테스트 값만 입력하세요. `local.json`은 Git에서 제외되며, 공개 테스트 ID가 없으므로 값이 비어 있으면 Sample 앱이 요청을 차단합니다.

Sample 앱의 설정 화면은 포맷별 ID 하나씩을 입력받습니다. 같은 포맷의 여러 지면을 사용하는 운영 앱은 `NapMxConfiguration.additionalAdUnitIds`에 추가 ID를 등록하고 컨트롤러 또는 `NapMxAdView`에 원하는 ID를 명시하세요. 목록만으로 초기화하는 예제와 제한사항은 [다중 지면 등록 가이드](../doc/integration-guide.md#61-같은-포맷의-여러-지면-등록-014)를 참고하세요.
