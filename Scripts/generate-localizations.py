#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Sources/Resources/Localizable.xcstrings"

TRANSLATIONS = {
    "프리셋": ("Presets", "プリセット"),
    "프리셋 추가": ("Add Preset", "プリセットを追加"),
    "프리셋 없음": ("No Presets", "プリセットなし"),
    "자주 쓰는 볼륨을 저장하고 전역 단축키를 지정하세요.": (
        "Save frequently used volumes and assign global shortcuts.",
        "よく使う音量を保存し、グローバルショートカットを割り当てます。",
    ),
    "설정에서 프리셋을 만듭니다.": ("Create presets in Settings.", "設定でプリセットを作成します。"),
    "이름": ("Name", "名前"),
    "단축키 없음": ("No shortcut", "ショートカットなし"),
    "단축키 지우기": ("Clear shortcut", "ショートカットを消去"),
    "키 입력...": ("Press keys...", "キーを入力..."),
    "설정": ("Settings", "設定"),
    "종료": ("Quit", "終了"),
    "출력 장치 선택": ("Select output device", "出力デバイスを選択"),
    "출력 장치 없음": ("No output device", "出力デバイスなし"),
    "사운드 설정 열기": ("Open Sound Settings", "サウンド設定を開く"),
    "음소거": ("Mute", "ミュート"),
    "음소거 해제": ("Unmute", "ミュート解除"),
    "일반": ("General", "一般"),
    "앱별 볼륨": ("Per-App Volume", "アプリごとの音量"),
    "정보": ("Info", "情報"),
    "표시": ("Display", "表示"),
    "소수점 자리": ("Decimal places", "小数点以下の桁数"),
    "메뉴 막대에 퍼센트 표시": ("Show percentage in menu bar", "メニューバーにパーセントを表示"),
    "동작": ("Behavior", "動作"),
    "프리셋 단축키 사용": ("Enable preset shortcuts", "プリセットショートカットを有効にする"),
    "마지막 출력 장치 복원": ("Restore last output device", "最後の出力デバイスを復元"),
    "시작": ("Startup", "起動"),
    "로그인 시 실행": ("Launch at login", "ログイン時に起動"),
    "다시 확인": ("Check Again", "再確認"),
    "앱 재시작": ("Restart App", "アプリを再起動"),
    "시스템 설정에서 승인": ("Approve in System Settings", "システム設定で承認"),
    "설치 위치 확인 필요": ("Check install location", "インストール場所を確認"),
    "시스템 설정 승인 필요": ("Approval required", "システム設定での承認が必要"),
    "로그인 시 자동 실행 켜짐": ("Launch at login is on", "ログイン時の自動起動はオン"),
    "로그인 시 자동 실행 꺼짐": ("Launch at login is off", "ログイン時の自動起動はオフ"),
    "시스템 설정 > 일반 > 로그인 항목에서 VSLight를 허용하세요.": (
        "Allow VSLight in System Settings > General > Login Items.",
        "システム設定 > 一般 > ログイン項目で VSLight を許可してください。",
    ),
    "로그인 항목은 /Applications에 설치된 VSLight에서 등록할 수 있습니다.": (
        "Login items can be registered when VSLight is installed in /Applications.",
        "ログイン項目は /Applications にインストールされた VSLight から登録できます。",
    ),
    "등록 상태를 다시 읽습니다.": ("Re-read the registration status.", "登録状態を再読み込みします。"),
    "로그인 항목 변경을 적용하기 위해 앱을 다시 시작합니다.": (
        "Restart the app to apply login item changes.",
        "ログイン項目の変更を適用するためにアプリを再起動します。",
    ),
    "출력 장치": ("Output Device", "出力デバイス"),
    "현재 장치": ("Current device", "現在のデバイス"),
    "오디오 다시 감지": ("Rescan Audio", "オーディオを再検出"),
    "잠자기에서 깨어난 뒤 오디오 상태가 갱신되지 않을 때 사용합니다.": (
        "Use this if audio state is stale after waking from sleep.",
        "スリープ復帰後にオーディオ状態が更新されない場合に使用します。",
    ),
    "닫기": ("Close", "閉じる"),
    "소수점 단위 시스템 볼륨 제어": ("Precise system volume control", "小数点単位のシステム音量調整"),
    "프리셋별 전역 단축키": ("Global shortcuts per preset", "プリセットごとのグローバルショートカット"),
    "네이티브 출력 장치 선택": ("Native output device selection", "ネイティブ出力デバイス選択"),
    "Liquid Glass 인터페이스": ("Liquid Glass interface", "Liquid Glass インターフェース"),
    "GitHub에서 보기": ("View on GitHub", "GitHub で見る"),
    "macOS 27 전용 네이티브 볼륨 컨트롤": (
        "Native volume control for macOS 27",
        "macOS 27 専用のネイティブ音量コントロール",
    ),
    "앱별 볼륨에는 가상 오디오 드라이버가 필요합니다": (
        "Per-app volume requires a virtual audio driver",
        "アプリごとの音量には仮想オーディオドライバーが必要です",
    ),
    "macOS 공개 API는 다른 앱의 출력 볼륨을 직접 낮출 수 없습니다. 프로세스 탭은 캡처 전용이라 감쇠를 적용할 수 없고, 앱별 게인을 적용하려면 HAL 오디오 드라이버를 설치해야 합니다.": (
        "macOS public APIs cannot lower another app's output volume directly. Process taps are capture-only, so per-app gain requires a HAL audio driver.",
        "macOS の公開 API では他のアプリの出力音量を直接下げることはできません。プロセスタップはキャプチャ専用のため、アプリごとのゲインには HAL オーディオドライバーが必要です。",
    ),
    "v0.1은 시스템 출력 볼륨과 장치 선택, 프리셋 단축키를 제공하고, 이 화면에서는 현재 오디오를 재생하는 앱만 보여줍니다.": (
        "v0.1 provides system output volume, device selection, and preset shortcuts. This screen lists apps that are currently playing audio.",
        "v0.1 ではシステム出力音量、デバイス選択、プリセットショートカットを提供します。この画面には現在オーディオを再生しているアプリが表示されます。",
    ),
    "현재 오디오를 재생하는 앱": ("Apps currently playing audio", "現在オーディオを再生しているアプリ"),
    "재생 중인 앱이 없습니다.": ("No apps are playing audio.", "オーディオを再生しているアプリはありません。"),
    "앱별 볼륨은 드라이버 단계에서 지원합니다.": (
        "Per-app volume is supported in the driver phase.",
        "アプリごとの音量はドライバーフェーズで対応します。",
    ),
    "알 수 없는 앱": ("Unknown app", "不明なアプリ"),
    "CoreAudio 오류": ("CoreAudio error", "CoreAudio エラー"),
    "오디오 속성 값을 읽지 못했습니다.": (
        "Could not read the audio property.",
        "オーディオプロパティを読み取れませんでした。",
    ),
    "같은 단축키를 다른 프리셋이 사용 중입니다.": (
        "Another preset uses the same shortcut.",
        "別のプリセットが同じショートカットを使用しています。",
    ),
    "단축키를 등록하지 못했습니다.": (
        "Could not register the shortcut.",
        "ショートカットを登録できませんでした。",
    ),
    "이미 다른 앱이 사용하는 단축키입니다.": (
        "Another app already uses this shortcut.",
        "別のアプリがこのショートカットを使用しています。",
    ),
    "로그인 항목을 변경하지 못했습니다.": (
        "Could not change the login item.",
        "ログイン項目を変更できませんでした。",
    ),
    "앱을 다시 시작하지 못했습니다.": (
        "Could not restart the app.",
        "アプリを再起動できませんでした。",
    ),
    "새 프리셋": ("New Preset", "新しいプリセット"),
    "내장": ("Built-in", "内蔵"),
    "USB": ("USB", "USB"),
    "Bluetooth": ("Bluetooth", "Bluetooth"),
    "Bluetooth LE": ("Bluetooth LE", "Bluetooth LE"),
    "HDMI": ("HDMI", "HDMI"),
    "DisplayPort": ("DisplayPort", "DisplayPort"),
    "AirPlay": ("AirPlay", "AirPlay"),
    "가상": ("Virtual", "仮想"),
    "집계 장치": ("Aggregate Device", "集約デバイス"),
    "Thunderbolt": ("Thunderbolt", "Thunderbolt"),
    "PCI": ("PCI", "PCI"),
    "FireWire": ("FireWire", "FireWire"),
    "AVB": ("AVB", "AVB"),
    "기타": ("Other", "その他"),
    "키": ("Key", "キー"),
    "단축키": ("Shortcut", "ショートカット"),
    "가상 오디오 드라이버 설치됨": ("Virtual audio driver installed", "仮想オーディオドライバーがインストールされています"),
    "가상 오디오 드라이버가 필요합니다": ("Virtual audio driver required", "仮想オーディオドライバーが必要です"),
    "드라이버 설치": ("Install Driver", "ドライバーをインストール"),
    "드라이버 제거": ("Remove Driver", "ドライバーを削除"),
    "앱별 게인은 시스템 출력과 모니터 출력 사이를 오가는 HAL 드라이버가 담당합니다. 설치는 관리자 승인이 필요하며 coreaudiod가 재시작됩니다.": (
        "A HAL driver routes audio between the system output and the monitor output. Installation requires administrator approval and restarts coreaudiod.",
        "HAL ドライバーがシステム出力とモニター出力の間でオーディオをルーティングします。インストールには管理者の承認が必要で、coreaudiod が再起動します。",
    ),
    "앱별 볼륨 사용": ("Enable per-app volume", "アプリごとの音量を有効にする"),
    "모니터 출력": ("Monitor output", "モニター出力"),
    "시스템 출력이 VSLight Audio로 전환됩니다. 메뉴 바 볼륨은 전체 게인으로 동작합니다.": (
        "System output switches to VSLight Audio. The menu bar volume controls the master gain.",
        "システム出力が VSLight Audio に切り替わります。メニューバーの音量はマスターゲインとして動作します。",
    ),
    "드라이버 설치에 실패했습니다.": ("Driver installation failed.", "ドライバーのインストールに失敗しました。"),
    "드라이버 제거에 실패했습니다.": ("Driver removal failed.", "ドライバーの削除に失敗しました。"),
    "드라이버 번들이 앱에 없습니다. Scripts/build-driver.sh를 실행하세요.": (
        "The driver bundle is not in the app. Run Scripts/build-driver.sh.",
        "アプリにドライバーバンドルがありません。Scripts/build-driver.sh を実行してください。",
    ),
    "앱별 볼륨을 사용하려면 드라이버를 설치하세요.": (
        "Install the driver to use per-app volume.",
        "アプリごとの音量を使用するにはドライバーをインストールしてください。",
    ),
    "앱별 볼륨을 적용하지 못했습니다.": (
        "Could not apply per-app volume.",
        "アプリごとの音量を適用できませんでした。",
    ),
    "VSLight 오디오 드라이버를 찾지 못했습니다.": (
        "Could not find the VSLight audio driver.",
        "VSLight オーディオドライバーが見つかりません。",
    ),
    "출력 장치를 찾지 못했습니다.": ("Could not find the output device.", "出力デバイスが見つかりません。"),
    "오디오 루프백을 만들지 못했습니다.": (
        "Could not create the audio loopback.",
        "オーディオループバックを作成できませんでした。",
    ),
    "오디오 루프백을 시작하지 못했습니다.": (
        "Could not start the audio loopback.",
        "オーディオループバックを開始できませんでした。",
    ),
    "출력 장치를 전환하지 못했습니다.": (
        "Could not switch the output device.",
        "出力デバイスを切り替えられませんでした。",
    ),
    "%lld자리": ("%lld digits", "%lld桁"),
    "%lld개": ("%lld", "%lld個"),
}

strings = {}
for source, (english, japanese) in TRANSLATIONS.items():
    strings[source] = {
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": english}},
            "ja": {"stringUnit": {"state": "translated", "value": japanese}},
        }
    }

catalog = {
    "sourceLanguage": "ko",
    "strings": strings,
    "version": "1.0",
}

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
OUTPUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Wrote {OUTPUT} ({len(strings)} keys)")
