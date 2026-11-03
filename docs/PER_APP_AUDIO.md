# 앱별 볼륨 조사와 계획

## 1. 결론

macOS 27.2 공개 CoreAudio API만으로 다른 앱의 출력 볼륨을 직접 낮출 수 없다. 프로세스 객체에는 볼륨 프로퍼티가 없고, 프로세스 탭은 캡처 전용이다. 앱별 게인을 적용하려면 가상 HAL 오디오 드라이버가 필요하다.

v0.1은 앱별 볼륨을 제외하고 다음만 제공한다.

- 현재 오디오를 재생하는 앱 목록
- 시스템 출력 볼륨과 출력 장치 제어
- 프리셋과 전역 단축키

## 2. 근거

### 2.1 프로세스 프로퍼티

`CoreAudio.framework/Headers/AudioHardware.h`에는 다음 프로세스 프로퍼티만 있다.

| 상수 | 값 | 줄 |
| --- | --- | --- |
| `kAudioProcessPropertyPID` | `'ppid'` | 1973 |
| `kAudioProcessPropertyBundleID` | `'pbid'` | 1974 |
| `kAudioProcessPropertyDevices` | `'pdv#'` | 1975 |
| `kAudioProcessPropertyIsRunning` | `'pir?'` | 1976 |
| `kAudioProcessPropertyIsRunningInput` | `'piri'` | 1977 |
| `kAudioProcessPropertyIsRunningOutput` | `'piro'` | 1978 |

볼륨, 게인, 팬에 해당하는 프로세스 프로퍼티는 없다. 프로세스 목록은 `kAudioHardwarePropertyProcessObjectList`(`AudioHardware.h:633`)로 얻는다.

### 2.2 프로세스 탭

`AudioHardwareTapping.h:43`의 `AudioHardwareCreateProcessTap`은 `CATapDescription`으로 탭을 만들고 `AudioObjectID`를 돌려준다. 탭은 오디오를 **읽는** 입력이다. 탭 자체에 볼륨 프로퍼티가 없다.

`CATapDescription.h`에는 다음이 있다.

- `muteBehavior` (`CATapMuteBehavior`, 30행): 탭 대상 프로세스의 원래 출력을 음소거할 수 있다.
- `processes`, `bundleIDs`, `exclusive`, `mixdown`, `privateTap`
- `processRestoreEnabled` (macOS 26.0): 종료된 프로세스를 다시 탭에 복원한다.

`mutedWhenTapped`와 자체 재생을 조합하면 이론적으로 게인을 적용할 수 있지만, Apple이 문서화한 재생 경로가 아니다. 지연, 클록 드리프트, 포맷 변환, 보호된 오디오, Bluetooth 전환에서 취약하다. v0.1에 넣지 않는다.

### 2.3 가상 드라이버

앱별 게인을 제대로 구현하려면 `AudioServerPlugIn`을 구현한 가상 오디오 장치가 필요하다. Apple 문서에 `Creating an Audio Server Driver Plug-in`과 `Building an Audio Server Plug-in and Driver Extension`이 존재한다. 드라이버는 `/Library/Audio/Plug-Ins/HAL`에 설치되고 `coreaudiod` 재시작이 필요할 수 있다.

일반적인 제약은 다음과 같다.

- 관리자 권한 설치
- Developer ID 서명과 공증
- 앱 샌드박스 안에서 설치 불가
- App Store 배포 부적합
- 드라이버와 앱 사이의 제어 채널 필요
- 오디오 장치 전환, 샘플레이트, 클록 처리 구현 필요

## 3. 선택지

| 방식 | 앱별 감쇠 | 드라이버 설치 | 위험 | 판정 |
| --- | --- | --- | --- | --- |
| 공개 API만 사용 | 불가 | 없음 | 없음 | v0.1 |
| 프로세스 탭 + 자체 재생 | 가능(비문서) | 없음 | 지연, DRM, 장치 전환, 권한 | 보류 |
| 프로세스 탭 + 가상 HAL 드라이버 | 가능 | 필요 | 설치/공증/드라이버 안정성 | v0.2 후보 |
| 서드파티 가상 장치(예: BlackHole) 의존 | 가능 | 사용자 설치 | 외부 의존, 네이티브 원칙 위반 | 제외 |

## 4. 가상 드라이버 단계 계획

1. 최소 `AudioServerPlugIn`을 구현해 가상 출력 장치를 만들고, 앱에서 장치를 선택할 수 있게 한다.
2. 드라이버가 클라이언트 프로세스별 오디오를 구분할 수 있는지 검증한다. HAL 플러그인은 기본적으로 믹스된 IO를 받으므로, 프로세스별 제어는 탭과 결합해야 할 수 있다.
3. 앱과 드라이버 사이에 XPC 또는 공유 메모리 기반 제어 채널을 둔다.
4. 설치 도우미를 `SMAppService` 또는 권한 요청 흐름으로 제공하고, 실패 시 시스템 볼륨 모드로 폴백한다.
5. Developer ID 서명, 공증, 드라이버 재시작 안내를 릴리스 체크리스트에 넣는다.

2단계에서 프로세스별 분리가 불가능하다고 판정되면, 앱별 볼륨 대신 “앱별 음소거”만 제공하는 축소안을 검토한다. 이 경우에도 탭 권한과 캡처 설명이 필요하다.

## 5. 사용자에게 표시하는 문구

v0.1 설정의 앱별 볼륨 탭에는 다음을 명시한다.

- macOS 공개 API는 다른 앱의 출력 볼륨을 직접 낮출 수 없다.
- 프로세스 탭은 캡처 전용이라 감쇠를 적용할 수 없다.
- 앱별 게인에는 HAL 오디오 드라이버 설치가 필요하다.
- 현재 버전은 재생 중인 앱 목록만 보여준다.

## 6. 재확인 필요 항목

- 드라이버 설치 경로와 `coreaudiod` 재시작 필요 여부
- macOS 27에서 HAL 플러그인 로딩 정책 변화
- 공증된 드라이버의 설치 자동화 가능 범위
- Bluetooth/AirPlay 장치에서 탭과 가상 장치의 동시 사용 안정성
- 보호된 오디오(DRM) 재생 시 탭 동작
