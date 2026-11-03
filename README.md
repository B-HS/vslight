# VSLight

macOS 27 전용 네이티브 볼륨 컨트롤. 메뉴 바에서 시스템 출력 볼륨을 소수점 단위로 조절하고, 프리셋을 전역 단축키로 적용하며, 출력 장치를 네이티브 UI처럼 전환한다.

SwiftUI, CoreAudio, Carbon 단축키만 사용한다. Electron, Tauri, 서드파티 라이브러리가 없다.

## 상태

- v0.1.0 초안. GitHub draft PR에서 테스트한 뒤 릴리스한다.
- 시스템 출력 볼륨, 출력 장치 선택, 프리셋, 전역 단축키가 동작한다.
- 앱별 볼륨은 v0.1 범위에서 제외했다. macOS 공개 API에 프로세스 볼륨 프로퍼티가 없고, 가상 HAL 오디오 드라이버가 필요하다. 자세한 내용은 [docs/PER_APP_AUDIO.md](docs/PER_APP_AUDIO.md)를 참고한다.

## 기능

- 소수점 단위 시스템 출력 볼륨 제어. 슬라이더와 퍼센트 직접 입력을 함께 제공한다.
- 출력 장치 열거, 기본 출력 장치 전환, 장치 UID 기반 복원.
- 프리셋 목록과 프리셋별 전역 단축키. Carbon `RegisterEventHotKey`를 사용해 손쉬운 사용 권한 없이 동작한다.
- macOS 27 `reorderable()` 기반 프리셋 순서 변경.
- 메뉴 막대 아이콘과 퍼센트 표시, 음소거 상태 반영.
- Liquid Glass 기반 메뉴 바 팝오버와 설정 창.
- 현재 오디오를 재생하는 앱 목록 표시.
- 로그인 시 실행 설정.
- 버전 번호에 숫자 4를 사용하지 않는 릴리스 정책.

## 요구사항

- macOS 27.0 이상
- Xcode 27.2 이상
- Swift 6
- XcodeGen 2.45 이상 (`brew install xcodegen`)

## 빌드

```bash
xcodegen generate
xcodebuild -project VSLight.xcodeproj -scheme VSLight -configuration Debug build
open build/Build/Products/Debug/VSLight.app
```

Xcode에서 열 때는 `VSLight.xcodeproj`를 연다. `project.yml`을 수정하면 `xcodegen generate`를 다시 실행한다.

## 테스트

```bash
xcodebuild -project VSLight.xcodeproj -scheme VSLight -destination 'platform=macOS' test
bash Scripts/check-version.sh
swift Scripts/verify-audio.swift
```

`Scripts/probe-volume.swift`는 현재 볼륨을 읽고 0.1373으로 설정한 뒤 되읽어 소수점 반영 여부를 확인하고 원래 값으로 복원한다. 오디오 출력이 잠깐 바뀔 수 있으므로 필요할 때만 실행한다.

## 사용

1. 메뉴 바의 스피커 아이콘을 클릭한다.
2. 슬라이더를 움직이거나 퍼센트를 직접 입력한다.
3. 출력 장치 메뉴에서 다른 장치를 선택한다.
4. 프리셋 버튼을 클릭하면 저장된 볼륨이 적용된다.
5. 설정의 프리셋 탭에서 이름, 볼륨, 단축키를 편집한다.

단축키를 기록할 때는 최소 하나의 보조 키(Command, Option, Control, Shift)가 필요하다. Escape로 기록을 취소한다. 다른 앱이 이미 사용하는 조합은 등록되지 않고 경고 아이콘이 표시된다.

## 버전 정책

버전과 빌드 번호에 숫자 4를 사용하지 않는다.

```text
0.1.0 -> 0.2.0 -> 0.3.0 -> 0.5.0 -> 0.6.0 -> 0.7.0 -> 0.8.0 -> 0.9.0 -> 0.10.0
```

자세한 규칙과 검증 방법은 [docs/VERSIONING.md](docs/VERSIONING.md)를 참고한다.

## 구조

```text
Sources/
  App/                    앱 진입점, 루트 모델, 메뉴 바 라벨
  Core/Audio/             CoreAudio 장치/볼륨/프로세스 계층
  Core/Hotkeys/           Carbon 전역 단축키
  Core/Settings/          설정과 프리셋 저장
  Core/Version/           숫자 4 금지 버전 정책
  Features/Volume/        메뉴 바 볼륨 UI
  Features/Output/        출력 장치 메뉴
  Features/Presets/       프리셋 칩
  Features/Apps/          앱별 볼륨 안내 화면
  Features/Settings/      설정 창
Tests/                    단위 테스트
Scripts/                  버전 검사, CoreAudio 진단
docs/                     아키텍처, 버전 정책, 앱별 볼륨 계획, 작업 기록
```

## 알려진 제한

- 앱별 볼륨은 지원하지 않는다. 공개 API 제약 때문에 가상 오디오 드라이버가 필요하다.
- App Sandbox를 사용하지 않는다. v0.1은 Developer ID 배포를 전제로 한다. App Store 배포는 별도 검토가 필요하다.
- 서명과 공증은 릴리스 단계에서 설정한다. 현재 빌드는 ad-hoc 서명이다.
- 자동 업데이트는 포함하지 않는다.

## 기준 문서

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/PER_APP_AUDIO.md](docs/PER_APP_AUDIO.md)
- [docs/VERSIONING.md](docs/VERSIONING.md)
- [docs/PROCESS.md](docs/PROCESS.md)
