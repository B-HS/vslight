# 아키텍처

## 1. 제품 경계

VSLight는 macOS 27 전용 메뉴 바 앱이다. Dock 아이콘 없이 동작하고(`LSUIElement`), 메뉴 바 팝오버에서 일상 제어를, 설정 창에서 프리셋과 표시 옵션을 관리한다.

| 영역 | 책임 | 파일 |
| --- | --- | --- |
| 앱 셸 | `MenuBarExtra`, `Settings`, 모델 주입 | `Sources/App/VSLightApp.swift` |
| 루트 모델 | 장치/프리셋/단축키 조정, 로그인 항목 | `Sources/App/AppModel.swift` |
| 오디오 | 장치 열거, 기본 장치 전환, 볼륨/뮤트 읽기·쓰기, 변경 리스너, 프로세스 열거 | `Sources/Core/Audio/` |
| 단축키 | Carbon 전역 단축키 등록/해제, 충돌 보고 | `Sources/Core/Hotkeys/` |
| 설정 | JSON 영속화, 기본값, 프리셋 모델 | `Sources/Core/Settings/` |
| 버전 | 숫자 4 금지 정책 | `Sources/Core/Version/` |
| UI | 볼륨 카드, 장치 메뉴, 프리셋 칩, 설정 탭 | `Sources/Features/` |

## 2. 동시성

- `AudioSystem`, `AppModel`, `SettingsStore`, `HotkeyManager`는 모두 `@MainActor @Observable`이다.
- CoreAudio 프로퍼티 읽기/쓰기는 짧은 동기 호출이라 메인 액터에서 수행한다.
- CoreAudio 변경 리스너는 `DispatchQueue.main`으로 등록하고 블록 안에서 `MainActor.assumeIsolated`로 상태를 갱신한다.
- Carbon 이벤트 핸들러는 애플리케이션 이벤트 타깃의 메인 스레드에서 호출되므로 `MainActor.assumeIsolated`로 프리셋을 적용한다.
- 앱 시작은 `AppModel.init`에서 `Task { @MainActor ... }`로 한 번 지연시켜 `NSApplication` 초기화 이후에 Carbon/CoreAudio 리스너를 설치한다.

## 3. 시스템 볼륨

### 3.1 사용한 API

- 기본 출력 장치: `kAudioHardwarePropertyDefaultOutputDevice` (`AudioHardware.h:610`)
- 장치 목록: `kAudioHardwarePropertyDevices` (`AudioHardware.h:608`)
- 출력 채널 구성: `kAudioDevicePropertyStreamConfiguration` (`AudioHardware.h:1023`)
- 볼륨: `kAudioDevicePropertyVolumeScalar` (`AudioHardware.h:1299`), `Float32`, 0.0~1.0
- 뮤트: `kAudioDevicePropertyMute` (`AudioHardware.h:1306`), `UInt32`
- 기본 장치 가능 여부: `kAudioDevicePropertyDeviceCanBeDefaultDevice` (`AudioHardwareBase.h:748`)
- 전송 타입: `kAudioDevicePropertyTransportType` (`AudioHardwareBase.h:743`)
- 데이터 소스: `kAudioDevicePropertyDataSource` (`AudioHardware.h:1313`)
- 변경 리스너: `AudioObjectAddPropertyListenerBlock` (`AudioHardware.h:397`)

### 3.2 읽기/쓰기 규칙

1. `kAudioObjectPropertyElementMain` element의 볼륨 스칼라를 먼저 시도한다.
2. main element가 없거나 설정 불가면 출력 채널 element(1...n)을 순회해 평균을 읽고, 설정 시 모든 채널에 같은 값을 쓴다.
3. 쓰기 전에 `AudioObjectIsPropertySettable`로 확인한다.
4. 뮤트는 볼륨과 독립 상태로 취급한다. 볼륨을 올리면 뮤트를 해제한다.
5. 장치가 바뀌면 기존 볼륨/뮤트 리스너를 제거하고 새 장치에 등록한다.

### 3.3 소수점 정밀도

이 머신(macOS 27.2, MacBook Pro Speakers)에서 0.1373을 설정하고 되읽은 값은 0.13730001이었다. 차이는 1.49e-08로 Float32 표현 오차 수준이다. 즉 시스템이 1/16 단계로 양자화하지 않고 임의의 Float32 값을 보존한다.

검증 명령은 `swift Scripts/probe-volume.swift`이며, 원래 볼륨으로 복원한다. 이 검증은 기기와 드라이버에 따라 달라질 수 있으므로 릴리스 전 실제 출력 장치에서 다시 확인한다.

## 4. 출력 장치

- 장치 이름은 `kAudioObjectPropertyName`, UID는 `kAudioDevicePropertyDeviceUID`에서 읽는다.
- 출력 채널이 0이어도 `kAudioDevicePropertyDeviceCanBeDefaultDevice`가 참이면 목록에 포함한다. AirPlay처럼 비활성 상태에서 채널이 0으로 보고되는 장치를 놓치지 않기 위해서다.
- 기본 장치 전환은 시스템 오브젝트에 `kAudioHardwarePropertyDefaultOutputDevice`를 쓰는 방식이다.
- 장치 목록과 기본 장치 변경을 모두 리스닝해 연결/해제를 반영한다.
- 데이터 소스(예: 내장 스피커의 잭 선택)는 v0.1 UI에 노출하지 않는다. API는 확인했지만 장치별 지원 편차가 커서 별도 단계로 미룬다.

## 5. 전역 단축키

- Carbon `RegisterEventHotKey` (`CarbonEvents.h:15484`)를 사용한다.
- 손쉬운 사용 권한이 필요 없고, `LSUIElement` 앱에서 동작하며, 키 조합 충돌을 `OSStatus`로 돌려준다.
- `InstallEventHandler`는 `GetApplicationEventTarget()`에 한 번 설치하고, `EventHotKeyID.id`를 프리셋 슬롯으로 매핑한다.
- 같은 조합을 여러 프리셋에 지정하면 두 번째부터 등록하지 않고 경고를 표시한다.
- 키 조합은 `keyCode`와 Carbon 수정키 비트마스크를 저장한다. 표시 문자열은 키코드 표와 수정키 기호(`⌃⌥⇧⌘`)로 만든다.
- 수정키 없이 일반 키만 누르는 조합은 허용하지 않는다.

## 6. 설정 영속화

- 경로: `~/Library/Application Support/VSLight/settings.json`
- 형식: JSON, pretty printed, sorted keys
- 누락 키는 기본값으로 보완한다.
- 슬라이더 드래그로 바뀌는 현재 볼륨은 저장하지 않는다. 저장 대상은 프리셋, 표시 옵션, 동작 옵션, 마지막 장치 UID다.

## 7. UI

- `MenuBarExtra` (`SwiftUI` 인터페이스 2378행), `.menuBarExtraStyle(.window)`
- Liquid Glass: `glassEffect(_:in:)` (`SwiftUICore` 인터페이스 3085행, macOS 26.0+), `GlassEffectContainer`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`
- 배포 타깃은 macOS 27.0이므로 Glass API에 별도 availability 분기를 두지 않는다.
- 메뉴 바 라벨은 `Image(systemName:variableValue:)`로 볼륨에 따라 심볼을 바꾸고, 설정에서 퍼센트 텍스트를 켤 수 있다.
- 설정 창은 `Settings` scene과 `openSettings` 환경 액션으로 연다.

## 8. 앱별 볼륨

v0.1은 읽기 전용 프로세스 목록만 제공한다. 공개 CoreAudio API에 프로세스 볼륨 프로퍼티가 없기 때문이다. 자세한 판정과 드라이버 계획은 [PER_APP_AUDIO.md](PER_APP_AUDIO.md)에 기록했다.

## 9. 서명과 배포

- Debug는 ad-hoc 서명으로 빌드한다.
- 배포는 Developer ID Application, Hardened Runtime, `notarytool` 공증, `stapler`를 전제로 한다.
- App Sandbox는 사용하지 않는다. v0.1은 직접 배포 채널을 기준으로 한다.
- GitHub Actions 릴리스 워크플로는 사용자가 제공하는 값과 함께 별도 단계에서 추가한다.
