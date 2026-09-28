---
name: deploy-android
description: brainmemorizer 를 안드로이드 APK 로 빌드해서 USB 또는 Wi-Fi(무선 디버깅)로 연결된 특정 핸드폰에 설치하고 실행한다. "폰에 배포", "안드로이드 빌드해서 깔아줘", "/deploy-android [시리얼]" 에 쓴다. 안드로이드 SDK 가 없으면 설치 스크립트부터 안내한다.
---

# deploy-android

`$ARGUMENTS` 는 선택 사항인 기기 시리얼(`adb devices` 의 첫 열)이다.

## 순서

1. **SDK 확인.** `Test-Path D:\Android\Sdk\platform-tools\adb.exe` 가 false 면 아직 SDK 가 없다.
   `scripts/setup-android-sdk.ps1` 를 실행하기 전에 사용자에게 반드시 먼저 허락을 받는다:
   - Google 서버에서 Android 명령줄 도구(약 156MB)를 받고, SDK 구성요소(플랫폼·빌드 도구·NDK, 합계 약 2GB)를 `D:\Android\Sdk` 에 설치한다.
   - **Android SDK 라이선스에 동의**하는 절차가 포함된다(약관 동의는 사용자 결정이다).
   - 사용자 환경변수 `ANDROID_HOME` 을 만들고 `platform-tools` 를 사용자 PATH 에 넣는다.
   허락받으면 Run 버튼용 명령으로 준다:
   ```bash
   powershell -ExecutionPolicy Bypass -File D:\projects\brainmemorizer\.claude\skills\deploy-android\scripts\setup-android-sdk.ps1
   ```
2. **폰 연결 확인.** 두 방법 중 하나.
   - **USB**: 개발자 옵션에서 **USB 디버깅**을 켜고 연결. 처음이면 폰의 "USB 디버깅을 허용하시겠습니까?" 창에서 **허용**.
     PC 가 폰을 아예 못 보면(`adb devices` 비어 있고 Windows 장치 목록에도 없음) 충전 전용 케이블이거나 USB 모드가 "충전만"이다.
   - **Wi-Fi (무선 디버깅, Android 11+)**: PC 와 폰이 같은 공유기에 있으면 된다(PC 는 유선이어도 됨).
     처음 한 번은 페어링이 필요하다. 사용자에게 개발자 옵션 → 무선 디버깅 → **페어링 코드로 기기 페어링** 창을 열어 두고
     **페어링 코드 · 페어링 IP:포트 · 본문의 연결용 IP:포트** 세 값을 받는다. 페어링 포트는 그 창이 열려 있는 동안만 열리고,
     코드와 포트는 창을 열 때마다 바뀐다. 코드는 **인자로** 넘긴다(파이프로 넣으면 데몬 기동 중에 씹힌다):
     ```
     D:\Android\Sdk\platform-tools\adb.exe pair <ip>:<페어링포트> <코드>
     ```
     연결용 포트는 폰 재부팅이나 무선 디버깅 재시작 때 바뀌므로 매번 사용자에게 확인한다.
     지난번 폰: 갤럭시 노트20 (SM-N981N), `192.168.0.9`, USB 시리얼 `R3CRA0FS5PK`.
3. **배포.** USB 면 아래를 그대로, 무선이면 `-Wireless <ip>:<연결용포트>` 를 붙인다. 시리얼을 지정하려면 `-Serial <값>`.
   ```bash
   powershell -ExecutionPolicy Bypass -File D:\projects\brainmemorizer\.claude\skills\deploy-android\scripts\deploy.ps1
   ```
   스크립트는 다음을 한다:
   - `adb devices` 로 기기를 고른다. `-Serial` > `device.txt`(지난번 기기) > 연결된 기기가 하나면 그것. 여럿이면 목록을 보여 주고 멈춘다.
   - `flutter build apk --release` (템플릿의 디버그 키로 서명되므로 바로 설치된다).
   - `adb install -r` 로 설치하고 앱을 실행한다.
   - 쓴 시리얼을 `device.txt` 에 저장한다(git 에는 안 올라간다).
4. **결과 보고.** 스크립트 마지막 줄의 `DEPLOYED <serial> <model>` 을 확인해 사용자에게 어느 폰에 깔렸는지 말한다.

## 자주 나는 오류

- `unauthorized` — 폰에서 USB 디버깅 허용 창을 아직 안 눌렀다. 누르게 하고 다시 실행.
- `no devices` — 케이블이 충전 전용이거나 USB 디버깅이 꺼짐. 다른 케이블/포트, 폰 알림에서 USB 모드를 "파일 전송" 으로.
- `INSTALL_FAILED_UPDATE_INCOMPATIBLE` — 다른 키로 서명된 같은 앱이 폰에 있다. 폰에서 앱을 지우고 다시 실행.
- `Could not close incremental caches ... this and base files have different roots` — Kotlin 증분 컴파일이 C:(pub 캐시)와 D:(빌드 폴더)를 못 잇는 Windows 버그. `android/gradle.properties` 의 `kotlin.incremental=false` 가 해결책이며 이미 들어 있다.
- 첫 빌드가 10분 넘게 걸림 — Gradle 9.3 과 안드로이드 의존성(약 3GB)을 받는 중이다. 두 번째부터는 1~2분.
- Gradle 이 SDK 구성요소를 못 찾음 — `setup-android-sdk.ps1` 을 다시 실행하면 빠진 것만 채운다.
- 기기 목록에 폰이 없는데 `adb devices` 에는 있음 — Flutter 가 아니라 adb 로 설치하므로 문제없다. 스크립트는 adb 만 쓴다.

## 하지 않는 것

- Play 스토어 배포와 릴리스 키스토어 서명은 다루지 않는다. 필요하면 별도로 만든다.
