[CmdletBinding()]
param(
    # A dedicated emulator: the suites clear the QA package and toggle radios.
    [string]$Device = 'emulator-5554',
    # Reuse tests/android/results/taskradar-qa.apk (its package is checked again).
    [switch]$SkipBuild,
    [ValidateSet('all', 'back', 'offline')]
    [string]$Suite = 'all',
    # Consecutive passes; both must be green, no retries in between.
    [int]$Passes = 2
)

# Builds the emulator QA package (com.taskradar.app.qa, release, debug-signed, synthetic API
# on 10.0.2.2:18743), proves the APK's real package name before installing it,
# and runs the Android Back and offline suites. See tests/android/README.md.

$ErrorActionPreference = 'Stop'
if ($Device -notmatch '^emulator-\d+$') { throw 'Use a dedicated Android emulator, not a phone.' }
$repoRoot = Split-Path -Parent $PSScriptRoot
$results = Join-Path $repoRoot 'tests/android/results'
$apk = Join-Path $results 'taskradar-qa.apk'
$qaPackage = 'com.taskradar.app.qa'
$previousDevice = $env:QA_ANDROID_DEVICE
$env:QA_ANDROID_DEVICE = $Device

Push-Location $repoRoot
try {
    if ((adb -s $Device get-state) -ne 'device') { throw "Start $Device first." }
    New-Item -ItemType Directory -Path $results -Force > $null

    if (-not $SkipBuild) {
        $flutter = Get-Command flutter -ErrorAction SilentlyContinue
        $flutterPath = if ($flutter) { $flutter.Source } else { 'C:\FlutterSdk\flutter\bin\flutter.bat' }
        Push-Location app
        try {
            & $flutterPath build apk --release `
                --dart-define=TASKRADAR_QA=true `
                --dart-define=TASKRADAR_API_URL=http://10.0.2.2:18743
            if ($LASTEXITCODE -ne 0) { throw 'QA APK build failed.' }
        } finally { Pop-Location }
        Copy-Item -LiteralPath app/build/app/outputs/flutter-apk/app-release.apk -Destination $apk -Force
    }

    # The package inside the APK, not what Gradle was supposed to do: an APK
    # under the regular id would replace the real app and its data.
    $sdkRoot = Split-Path -Parent (Split-Path -Parent (Get-Command adb).Source)
    $aapt = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Directory |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $aapt) { throw 'Android build-tools aapt.exe is required.' }
    $identity = & $aapt dump badging $apk | Select-Object -First 1
    if ($identity -notmatch "name='$([regex]::Escape($qaPackage))'") {
        throw "Refusing to install: the APK is not $qaPackage ($identity)."
    }
    adb -s $Device install -r -g $apk
    if ($LASTEXITCODE -ne 0) { throw 'QA APK installation failed.' }

    $busy = Get-NetTCPConnection -LocalPort 18743 -State Listen -ErrorAction SilentlyContinue
    if ($busy) { throw 'Port 18743 is taken; stop that server first.' }

    foreach ($pass in 1..$Passes) {
        if ($Suite -in 'all', 'back') {
            node tests/android/run-back.mjs --pass $pass
            if ($LASTEXITCODE -ne 0) { throw "Back suite failed on pass $pass; see tests/android/results/back-pass-$pass.json." }
        }
        if ($Suite -in 'all', 'offline') {
            node tests/android/run-offline.mjs --pass $pass
            if ($LASTEXITCODE -ne 0) { throw "Offline suite failed on pass $pass; see tests/android/results/offline-pass-$pass.json." }
        }
    }
} finally {
    $env:QA_ANDROID_DEVICE = $previousDevice
    Pop-Location
}
