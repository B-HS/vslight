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
| 시스템 | 절전/깨우기/세션 활성화/종료 감지 | `Sources/Core/System/` |
| 버전 | 숫자 4 금지 정책 | `Sources/Core/Version/` |
| UI | 볼륨 카드, 장치 메뉴, 프리셋 칩, 설정 탭 | `Sources/Features/` |

## 2. 동시성

- `AudioSystem`, `AppModel`, `SettingsStore`, `HotkeyManager`는 모두 `@MainActor @Observable`이다.
- CoreAudio 프로퍼티 읽기/쓰기는 짧은 동기 호출이라 메인 액터에서 수행한다.
- CoreAudio 변경 리스너는 `DispatchQueue.main`으로 등록하고 블록 안에서 `MainActor.assumeIsolated`로 상태를 갱신한다.
- Carbon 이벤트 핸들러는 애플리케이션 이벤트 타깃의 메인 스레드에서 호출되므로 `MainActor.assumeIsolated`로 프리셋을 적용한다.
- 앱 시작은 `AppModel.init`에서 `Task { @MainActor ... }`로 한 번 지연시켜 `NSApplication` 초기화 이후에 Carbon/CoreAudio 리스너를 설치한다.
- `SystemLifecycle`은 `NotificationCenter.notifications(named:)` AsyncSequence를 `Task`로 구독한다. 절전/깨우기, 화면 깨우기, 세션 활성화, 앱 활성화, 종료 이벤트를 각각 처리하고 `stop()`에서 모든 Task를 취소한다.
- CoreAudio 장치/서비스 변경은 즉시 반영하지 않고 120ms debounce Task로 합쳐 중복 갱신을 막는다.

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
- 프리셋 목록은 macOS 27의 `DynamicViewContent.reorderable()`을 사용한다. 같은 이유로 availability 분기가 필요 없다.
- 메뉴 바 라벨은 `Image(systemName:variableValue:)`로 볼륨에 따라 심볼을 바꾸고, 설정에서 퍼센트 텍스트를 켤 수 있다.
- 설정 창은 `Settings` scene과 `openSettings` 환경 액션으로 연다.
- 메뉴 바 창은 304pt 폭으로 줄이고 제목, 버전, 중복 여백을 제거했다. 출력 장치 선택은 최상단에 둔다.
- 퍼센트 숫자는 별도 입력 행 없이 큰 `TextField`로 직접 수정한다. 편집 중에만 옅은 배경을 표시하고, 포커스 시 전체 선택한다.
- 프리셋이 없으면 빈 상태에서 설정의 프리셋 탭으로 이동하는 버튼만 표시한다.
- 설정은 `SettingsTab` selection으로 열리는 탭을 지정할 수 있다. 빠른 창의 빈 프리셋 버튼은 프리셋 탭을 연다.

## 8. 앱별 볼륨

앱별 볼륨은 HAL 오디오 드라이버와 루프백 엔진으로 구현한다.

- 드라이버: `Driver/VSLightAudioDriver.cpp`, libASPL 기반 `AudioServerPlugIn`
- 장치 UID: `com.bhs.vslight.driver.device`
- 출력 스트림과 루프백 입력 스트림을 함께 노출한다.
- `OnProcessClientOutput`이 클라이언트별 게인을 적용한다. 클라이언트의 bundle ID 또는 PID로 게인을 찾는다.
- 앱은 커스텀 프로퍼티 `'apvl'`에 `{bundleID, pid, volume, muted}` 배열을 써서 게인을 전달한다.
- 믹스된 오디오는 드라이버의 링 버퍼에 저장되고, 입력 스트림을 통해 앱의 루프백 엔진이 읽는다.
- 루프백 엔진은 가상 장치 입력과 실제 출력 장치를 두 개의 IOProc과 링 버퍼로 연결한다.
- 앱은 가상 장치를 기본 출력으로 전환하고, 실제 출력 장치 볼륨은 1.0으로 둔 뒤 종료 시 복원한다.
- 설치는 `/Library/Audio/Plug-Ins/HAL`에 복사하고 `coreaudiod`를 재시작해야 하므로 관리자 승인이 필요하다.
- 앱이 비정상 종료되면 기본 출력이 가상 장치로 남을 수 있다. 다음 실행 시 `recoverIfNeeded()`가 실제 장치로 되돌린다.
- 루프백은 추가 IO 버퍼만큼 지연이 생긴다. App Store 배포에는 적합하지 않다.

자세한 배경과 공개 API 제약은 [PER_APP_AUDIO.md](PER_APP_AUDIO.md)에 기록했다.

## 9. 서명과 배포

- Debug는 ad-hoc 서명으로 빌드한다.
- 배포는 Developer ID Application, Hardened Runtime, `notarytool` 공증, `stapler`를 전제로 한다.
- App Sandbox는 사용하지 않는다. v0.1은 직접 배포 채널을 기준으로 한다.
- `.github/workflows/ci.yml`은 XcodeGen, 버전 검사, 빌드, 테스트를 실행한다.
- `.github/workflows/release.yml`은 버전을 계산하고 draft 릴리스를 만든다. 인증서와 공증 값이 없으면 ad-hoc 서명으로 진행한다.

## 10. 절전/깨우기와 상태 복구

- `SystemLifecycle`은 `NSWorkspace.didWakeNotification`, `screensDidWakeNotification`, `sessionDidBecomeActiveNotification`, `NSApplication.didBecomeActiveNotification`, `willTerminateNotification`을 구독한다.
- 깨우기 시 `AudioSystem.restartMonitoring()`으로 CoreAudio 리스너를 모두 제거하고 다시 설치한다. 절전 중 사라진 장치나 재시작된 `coreaudiod`를 반영하기 위해서다.
- 깨우기 직후 1초 뒤 한 번 더 refresh해 장치 초기화가 늦는 경우를 보완한다.
- `kAudioHardwarePropertyServiceRestarted`를 리스닝해 CoreAudio 서비스가 재시작되면 400ms 뒤 모니터링을 재설치한다.
- 앱 활성화 시에도 상태를 다시 읽어 외부에서 바뀐 기본 장치와 볼륨을 반영한다.
- 재부팅 후에는 앱 시작 시 설정을 읽고 기본 장치/볼륨을 새로 조회한다. 로그인 시 실행이 켜져 있으면 같은 경로로 복구된다.

## 11. 로그인 시 실행

- `SMAppService.mainApp`을 사용한다.
- 상태는 `.enabled`, `.requiresApproval`, `.notRegistered`, `.notFound`로 구분해 UI에 표시한다.
- 등록 직후 `.requiresApproval`이면 `SMAppService.openSystemSettingsLoginItems()`로 승인 화면을 연다.
- 설정 화면에서 상태 새로고침과 앱 재시작을 제공한다. 재시작은 `/usr/bin/open -n`으로 새 인스턴스를 띄운 뒤 현재 인스턴스를 종료한다.
- `/Applications` 밖에서 실행 중이면 `.notFound`가 될 수 있으므로 설치 위치 안내를 표시한다.

## 12. 메모리와 정리

- `AudioSystem.stop()`은 모든 CoreAudio 리스너와 debounce Task를 해제한다.
- `HotkeyManager.stop()`은 등록된 모든 단축키와 이벤트 핸들러를 해제한다.
- `SystemLifecycle.stop()`은 모든 AsyncSequence 구독 Task를 취소한다.
- `AppModel.shutdown()`은 종료 알림에서 위 정리와 `SettingsStore.flush()`를 호출한다.
- `SettingsStore`는 250ms debounce로 디스크 쓰기를 합치고, 종료 시 flush한다.
- 반복 생성되는 CoreAudio 리스너/단축키/Task는 소유 객체가 하나씩만 보관한다.

## 13. 다국어

- 소스 문자열은 한국어를 키로 사용하고 `Sources/Resources/Localizable.xcstrings`에 영어·일본어 번역을 둔다.
- SwiftUI `Text`, `Label`, `Button`은 자동으로 로컬라이즈된다.
- 계산 프로퍼티와 오류 메시지는 `String(localized:)`를 사용한다.
- `Scripts/generate-localizations.py`가 카탈로그를 생성한다.
- 빌드 결과의 `en.lproj`/`ja.lproj`에 컴파일된 문자열이 포함되는지 확인한다.

## 14. HAL 드라이버

- `Scripts/build-driver.sh`가 libASPL을 고정 커밋으로 받아 C++17로 컴파일하고 `.driver` 번들을 만든다.
- `Scripts/install-driver.sh`가 `/Library/Audio/Plug-Ins/HAL`에 복사하고 `coreaudiod`를 재시작한다.
- 앱은 번들에 포함된 드라이버를 관리자 승인으로 설치하는 UI를 제공한다.
- 제거 시 앱별 모드를 끄고 기본 출력/볼륨을 복원한 뒤 시스템·사용자 경로의 드라이버 파일을 삭제하고 `coreaudiod`를 재시작한다. 이후 감지 여부와 파일 잔존 여부를 확인하고 앱별 설정을 초기화한다.
- Developer ID 릴리스에서는 드라이버도 같은 인증서로 서명한다. 공증은 앱 번들 전체에 적용된다.
