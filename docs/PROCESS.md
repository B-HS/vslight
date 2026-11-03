# PROCESS

## 기준 문서

- `~/.claude/convention/index.md`
- `~/.claude/convention/ai-process.md`
- `~/.claude/convention/common.md`
- `~/.claude/convention/git.md`
- `~/.claude/convention/security.md`
- `docs/tasks/vslight-sdk-research.md`

## 작업: VSLight v0.1.0 구현과 GitHub draft 준비

- [x] a. 환경과 SDK 확인 — macOS 27.2, Xcode 27.2, Swift 6.4.2, CoreAudio/SwiftUI 인터페이스 확인
- [x] b. 요구사항 확정 — 메뉴 바 앱, 시스템 볼륨, 프리셋 단축키, 출력 장치, 앱별 볼륨 포함 여부 결정
- [x] c. 프로젝트 스캐폴딩 — `project.yml`, XcodeGen, Info.plist, 폴더 구조
- [x] d. CoreAudio 계층 — 장치 열거, 기본 장치 전환, 볼륨/뮤트 읽기·쓰기, 변경 리스너, 프로세스 열거
- [x] e. 프리셋과 전역 단축키 — Carbon `RegisterEventHotKey`, 충돌 보고, 기록 UI
- [x] f. UI — Liquid Glass 메뉴 바 팝오버, 출력 장치 메뉴, 프리셋 칩, 설정 창
- [x] g. 단위 테스트 — 버전 정책, 볼륨 포매터, 단축키, 프리셋 직렬화
- [x] h. 빌드와 실행 검증 — `xcodebuild build`, `xcodebuild test`, 메뉴 바 실행, CoreAudio 소수점 프로브
- [x] i. 문서 — README, 아키텍처, 버전 정책, 앱별 볼륨 계획
- [x] j. GitHub 초기화와 draft PR — `B-HS/vslight` 생성, `main`과 `feat/v0.1-app` 푸시, PR #1 draft 생성
- [ ] k. 릴리스 워크플로 — 사용자가 서명/공증 값을 제공한 뒤 추가
- [ ] l. 앱별 볼륨 가상 드라이버 — v0.2 이후, `docs/PER_APP_AUDIO.md` 계획 참고

## 상세

### a. 환경과 SDK

- 이 머신은 macOS 27.2(26B123), Xcode 27.2, Swift 6.4.2, arm64.
- `SwiftUICore` 인터페이스 3085행에서 `glassEffect`가 macOS 26.0+임을 확인했다.
- `SwiftUI` 인터페이스 2378행에서 `MenuBarExtra`를 확인했다.
- `CoreAudio` 헤더에서 볼륨, 뮤트, 장치, 프로세스, 탭 상수를 확인했다.
- research 에이전트는 프로젝트 외부 SDK 경로 접근이 차단되어 BLOCKED를 반환했고, SDK 검증은 메인이 직접 수행했다.

### b. 요구사항

- 사용자는 workflow A, pen 모델 상속, 앱 이름 VSLight, 메뉴 바 + 설정 창, 시스템 및 앱별 볼륨을 선택했다.
- 앱별 볼륨은 공개 API 제약 때문에 v0.1에서 목록만 제공하고 드라이버 단계로 분리했다.

### c. 프로젝트

- XcodeGen을 사용하고 `.xcodeproj`는 저장소에 넣지 않는다.
- 배포 타깃 macOS 27.0, Swift 6 strict concurrency.
- `LSUIElement` 메뉴 바 앱, App Sandbox 미사용, Hardened Runtime 설정.

### d. CoreAudio

- main element 볼륨 스칼라 우선, 채널 폴백, `AudioObjectIsPropertySettable` 확인.
- 기본 장치와 장치 목록 변경을 모두 리스닝한다.
- 0.1373 설정 후 0.13730001로 되읽혀 Float32 정밀도를 확인했다.

### e. 단축키

- Carbon 전역 단축키를 사용해 손쉬운 사용 권한을 요구하지 않는다.
- 같은 조합 중복과 다른 앱 충돌을 경고로 표시한다.

### f. UI

- 메뉴 바 팝오버는 344pt 폭, 볼륨 카드에 Glass 효과를 적용했다.
- 설정은 일반, 프리셋, 앱별 볼륨, 정보 탭으로 구성했다.

### g. 테스트

- `VersionPolicyTests`, `VolumeFormatterTests`, `HotkeyTests` 10개 테스트 통과.

### h. 검증

- `xcodebuild -project VSLight.xcodeproj -scheme VSLight build` 성공.
- `xcodebuild ... test` 성공.
- 메뉴 바 팝오버 실행과 볼륨 퍼센트 표시를 확인했다.
- `Scripts/probe-volume.swift`로 소수점 반영을 확인했다.
- ⌃⌥1 테스트 프리셋을 실제 키 이벤트로 보내 0.137 적용을 확인했다.

### i. 문서

- README는 빌드, 사용, 제한, 버전 정책을 담는다.
- ARCHITECTURE는 SDK 근거와 동시성 모델을 담는다.
- PER_APP_AUDIO는 드라이버 필요성과 단계 계획을 담는다.
- VERSIONING은 숫자 4 금지 규칙과 릴리스 절차를 담는다.

### j. GitHub draft

- `B-HS/vslight` 저장소를 만들고 `main`과 `feat/v0.1-app` 브랜치를 푸시한다.
- `feat/v0.1-app`에서 `main`으로 draft PR을 연다.
- 사용자가 PR 브랜치를 받아 테스트한 뒤 릴리스한다.

### k. 릴리스 워크플로

- 사용자가 Developer ID, 공증 자격 증명, GitHub Actions 값을 제공하면 추가한다.
- 버전 검사 스크립트를 CI 첫 단계에 넣는다.

### l. 앱별 볼륨

- HAL 드라이버 구현, 설치 흐름, XPC 제어 채널이 필요하다.
- 2단계에서 프로세스별 분리가 불가능하면 앱별 음소거로 축소한다.
