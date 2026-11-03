# VSLight SDK 조사 브리프

조사 대상 환경은 이 머신 그대로다.

- macOS 27.2 (26B123)
- Xcode 27.2 (27B52)
- Swift 6.4.2, arm64
- SDK: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`

앱 요구사항은 다음과 같다.

- macOS 전용 네이티브 Swift/SwiftUI 앱, 메뉴 바 팝오버와 설정 창
- 시스템 출력 볼륨을 소수점 단위로 제어, 슬라이더와 숫자 직접 입력 병행
- 프리셋별 전역 단축키
- 네이티브 출력 장치 선택 UI
- 앱별 볼륨 제어 포함
- macOS 27 최신 기능 최대 활용

## 조사 항목

### 1. SwiftUI 최신 API

`SwiftUI.swiftinterface`와 `SwiftUICore.swiftinterface`에서 다음 항목의 availability(macOS 버전)와 정확한 선언을 인용한다.

- `glassEffect`, `GlassEffectContainer`, `Glass`, `glassProminent` 버튼 스타일, 관련 전환/union API
- `MenuBarExtra`, `MenuBarExtraStyle`, 메뉴 바 라벨 커스터마이징
- `Settings` scene, `SettingsLink`
- `ControlGroup`, `Slider`, `Stepper`, `TextField`의 최신 옵션
- macOS 26.0 및 27.0에서 새로 추가된 항목 중 이 앱에 직접 쓸 만한 것
- 각 항목의 사용 제약(예: glass는 어떤 컨테이너 안에서만 동작하는지)

### 2. 시스템 출력 볼륨

`CoreAudio.framework/Headers/AudioHardware.h`를 근거로 다음을 확정한다.

- 기본 출력 장치의 볼륨 스칼라를 읽고 쓰는 정확한 프로퍼티와 element/scope
- `kAudioDevicePropertyVolumeScalar`와 `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`의 차이, 권장 선택
- 값 타입(Float32), 범위, 설정 가능 여부 확인 방법
- 변경 알림 리스너 등록 방법과 콜백 스레드 주의사항
- 뮤트 프로퍼티와 볼륨 0과의 관계
- 채널별 볼륨이 있는 장치에서 main element 사용 시 동작
- Bluetooth/AirPlay 장치에서의 제약
- 실제 macOS 볼륨 UI가 0.0625 스텝으로 보이는 이유와, 임의의 Float 값을 설정했을 때의 실제 반영 여부

### 3. 출력 장치

- 출력 장치 열거 프로퍼티와 장치 이름/UID/manufacturer/transport type 획득
- 기본 출력 장치 get/set 프로퍼티와 설정 성공 판정
- 장치 변경 리스너
- 장치 UID 영속화 시 주의사항
- 데이터 소스(`kAudioDevicePropertyDataSource`) 선택 가능 여부와 네이티브 UI 대응
- 샌드박스 앱에서 가능한 범위

### 4. 앱별 볼륨

다음을 판정한다.

- 공개 API만으로 다른 앱의 출력 볼륨을 감쇠할 수 있는가
- 프로세스 탭(`AudioHardwareCreateProcessTap`, `CATapDescription`)은 무엇을 할 수 있고 무엇을 할 수 없는가. macOS 26.0 추가 API 포함
- 앱별 볼륨을 구현하려면 가상 HAL 플러그인(`AudioServerPlugIn`)이 필요한지, 필요하다면 최소 구현 요건과 설치 경로, 코어오디오 재시작 필요 여부
- 가상 드라이버를 앱 번들에 포함해 설치하는 절차와 서명/공증 요구사항, 샌드박스 제약
- 대안: 프로세스 탭 기반 캡처와 미터링만 제공하고 볼륨은 시스템 볼륨으로 제한하는 설계
- v0.1 권장 범위

### 5. 전역 단축키

- Carbon `RegisterEventHotKey`의 macOS 27 동작 여부와 샌드박스 호환성
- `CGEventTap` 방식의 필요 권한(손쉬운 사용)과 거부 시 동작
- `NSEvent.addGlobalMonitorForEvents` 방식의 제약
- 키 조합 저장/표시 형식과 충돌 감지 방법
- App Store 배포 시 제약

### 6. 패키징과 배포

- `LSUIElement` 메뉴 바 앱 구성과 `Settings` 창 표시 방법
- App Sandbox 사용 여부에 따른 CoreAudio/단축키 기능 차이
- 개발용 서명과 배포용 서명/공증의 차이, 필요한 entitlement
- 하드웨어 최소 버전과 deployment target 권장값
- macOS 27 전용 API 사용 시 하위 버전 지원 전략

## 결과 형식

- 모든 주장에 SDK 파일 경로와 라인 번호를 붙인다.
- 확인하지 못한 항목은 UNVERIFIED로 표시한다.
- 마지막에 결정표(선택지/장점/단점/위험/권장)와 v0.1 범위 제안을 넣는다.
- 한국어로 작성하고 이모지와 아스키아트를 쓰지 않는다.
