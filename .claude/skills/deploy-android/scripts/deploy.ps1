# brainmemorizer 를 릴리스 APK 로 빌드해 USB 로 연결된 폰에 설치하고 실행한다.
#   deploy.ps1                 연결된 폰이 하나면 그 폰, 아니면 지난번 폰(device.txt)
#   deploy.ps1 -Serial XXXX    특정 폰
param(
  [string]$Serial = '',
  [switch]$Debug   # 릴리스 대신 디버그 빌드
)
$ErrorActionPreference = 'Stop'

$Project = 'D:\projects\brainmemorizer'
$AppId = 'com.brainmemorizer.brainmemorizer'
$DeviceFile = Join-Path $PSScriptRoot '..\device.txt'

$SdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\Android\Sdk' }
$Adb = "$SdkRoot\platform-tools\adb.exe"
if (-not (Test-Path $Adb)) {
  throw "adb 가 없습니다 ($Adb). 먼저 setup-android-sdk.ps1 을 실행하세요."
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { $env:Path += ';D:\flutter\bin' }
$env:ANDROID_HOME = $SdkRoot

# ---- 기기 고르기 -----------------------------------------------------------
& $Adb start-server | Out-Null
$lines = & $Adb devices -l | Select-Object -Skip 1 | Where-Object { $_.Trim() }
$devices = foreach ($l in $lines) {
  $parts = $l -split '\s+'
  $model = ($parts | Where-Object { $_ -like 'model:*' }) -replace 'model:', ''
  [pscustomobject]@{ Serial = $parts[0]; State = $parts[1]; Model = $model }
}

$unauthorized = $devices | Where-Object State -eq 'unauthorized'
if ($unauthorized) {
  Write-Host "폰에서 'USB 디버깅을 허용하시겠습니까?' 창에 허용을 누른 뒤 다시 실행하세요: $($unauthorized.Serial -join ', ')"
  exit 2
}
$ready = @($devices | Where-Object State -eq 'device')
if ($ready.Count -eq 0) {
  Write-Host 'no devices: 연결된 안드로이드 기기가 없습니다. USB 케이블과 USB 디버깅 설정을 확인하세요.'
  exit 2
}

if (-not $Serial -and (Test-Path $DeviceFile)) {
  $saved = (Get-Content $DeviceFile -TotalCount 1).Trim()
  if ($ready.Serial -contains $saved) { $Serial = $saved }
}
if (-not $Serial) {
  if ($ready.Count -eq 1) {
    $Serial = $ready[0].Serial
  } else {
    Write-Host '기기가 여러 개입니다. -Serial 로 하나를 고르세요:'
    $ready | ForEach-Object { Write-Host "  $($_.Serial)  $($_.Model)" }
    exit 2
  }
}
$target = $ready | Where-Object Serial -eq $Serial
if (-not $target) {
  Write-Host "기기 '$Serial' 이 연결되어 있지 않습니다. 연결된 기기: $($ready.Serial -join ', ')"
  exit 2
}
Write-Host "대상 기기: $($target.Serial) ($($target.Model))"

# ---- 빌드 ------------------------------------------------------------------
Set-Location $Project
$mode = if ($Debug) { 'debug' } else { 'release' }
flutter build apk --$mode
if ($LASTEXITCODE -ne 0) { throw "flutter build apk --$mode 실패" }
$apk = "$Project\build\app\outputs\flutter-apk\app-$mode.apk"
if (-not (Test-Path $apk)) { throw "APK 가 없습니다: $apk" }

# ---- 설치 & 실행 -----------------------------------------------------------
& $Adb -s $Serial install -r $apk
if ($LASTEXITCODE -ne 0) { throw 'adb install 실패' }
& $Adb -s $Serial shell monkey -p $AppId -c android.intent.category.LAUNCHER 1 | Out-Null

Set-Content -Path $DeviceFile -Value $Serial -Encoding ascii
Write-Host "DEPLOYED $($target.Serial) $($target.Model)"
