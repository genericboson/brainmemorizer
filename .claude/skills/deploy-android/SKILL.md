---
name: deploy-android
description: brainmemorizer 를 안드로이드 APK 로 빌드해서 USB 로 연결된 특정 핸드폰에 설치하고 실행한다. "폰에 배포", "안드로이드 빌드해서 깔아줘", "/deploy-android [시리얼]" 에 쓴다. 안드로이드 SDK 가 없으면 설치 스크립트부터 안내한다.
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
2. **폰 연결 확인.** 사용자에게 USB 로 폰을 연결하고 개발자 옵션에서 **USB 디버깅**을 켜 두었는지 확인시킨다.
   처음 연결하면 폰에 "USB 디버깅을 허용하시겠습니까?" 창이 뜨니 **허용**을 누르라고 알린다.
3. **배포.** 아래를 실행한다. 시리얼이 있으면 `-Serial <값>` 을 붙인다.
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
- Gradle 이 SDK 구성요소를 못 찾음 — `setup-android-sdk.ps1` 을 다시 실행하면 빠진 것만 채운다.
- 기기 목록에 폰이 없는데 `adb devices` 에는 있음 — Flutter 가 아니라 adb 로 설치하므로 문제없다. 스크립트는 adb 만 쓴다.

## 하지 않는 것

- Play 스토어 배포, 릴리스 키스토어 서명, 무선(Wi-Fi) adb 페어링은 다루지 않는다. 필요하면 별도로 만든다.
