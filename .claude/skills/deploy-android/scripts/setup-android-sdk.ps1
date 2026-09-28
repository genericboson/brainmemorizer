# Android Studio 없이 안드로이드 SDK 를 설치한다. 다시 실행하면 빠진 것만 채운다.
# - 명령줄 도구를 받아 D:\Android\Sdk 에 풀고
# - SDK 라이선스에 동의한 뒤 (사용자 허락을 받고 실행할 것)
# - Flutter 가 요구하는 platform / build-tools / NDK 를 설치하고
# - ANDROID_HOME 과 PATH 를 사용자 환경변수에 등록한다.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SdkRoot = 'D:\Android\Sdk'
$ToolsUrl = 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip'
$ToolsSha256 = '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'
# Flutter 3.47 의 기본값 (packages/flutter_tools/gradle FlutterExtension.kt)
$Packages = @('platform-tools', 'platforms;android-36', 'build-tools;36.0.0', 'ndk;28.2.13676358')

$FlutterBin = 'D:\flutter\bin'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { $env:Path += ";$FlutterBin" }

# Gradle 이 쓸 JDK. JAVA_HOME 이 없으면 Flutter 가 찾지 못한다.
if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
  throw "JAVA_HOME 이 JDK 를 가리키지 않습니다 (현재: '$env:JAVA_HOME'). JDK 17 이상을 설치하고 JAVA_HOME 을 설정하세요."
}

$SdkManager = "$SdkRoot\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $SdkManager)) {
  Write-Host "명령줄 도구 다운로드: $ToolsUrl"
  $zip = Join-Path $env:TEMP 'commandlinetools-win.zip'
  Invoke-WebRequest $ToolsUrl -OutFile $zip
  $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
  if ($hash -ne $ToolsSha256) { throw "다운로드한 파일의 SHA-256 이 다릅니다: $hash" }

  $extract = Join-Path $env:TEMP 'commandlinetools-extract'
  if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
  Expand-Archive $zip -DestinationPath $extract
  New-Item -ItemType Directory -Force "$SdkRoot\cmdline-tools" | Out-Null
  # zip 안의 cmdline-tools/ 를 sdkmanager 가 기대하는 cmdline-tools/latest/ 로 옮긴다.
  Move-Item "$extract\cmdline-tools" "$SdkRoot\cmdline-tools\latest"
  Remove-Item $zip, $extract -Recurse -Force
}

Write-Host '라이선스 동의'
# sdkmanager 는 라이선스마다 y/N 을 묻는다. 최대 30개까지 y 를 넣는다.
$yes = 1..30 | ForEach-Object { 'y' }
$yes | & $SdkManager --sdk_root="$SdkRoot" --licenses | Out-Null

Write-Host "설치: $($Packages -join ', ')"
& $SdkManager --sdk_root="$SdkRoot" $Packages
if ($LASTEXITCODE -ne 0) { throw "sdkmanager 가 실패했습니다 (exit $LASTEXITCODE)" }

[Environment]::SetEnvironmentVariable('ANDROID_HOME', $SdkRoot, 'User')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$platformTools = "$SdkRoot\platform-tools"
if ($userPath -notlike "*$platformTools*") {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$platformTools"), 'User')
}
$env:ANDROID_HOME = $SdkRoot
$env:Path += ";$platformTools"

flutter config --android-sdk $SdkRoot | Out-Null
Write-Host ''
flutter doctor -v 2>&1 | Select-String -Pattern 'Android toolchain' -Context 0, 6
Write-Host ''
Write-Host "SDK 설치 완료: $SdkRoot"
