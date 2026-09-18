# Packs a Windows release build into the zip that is attached to a GitHub
# Release (and produced as an artifact on every CI run).
#
# Why a script rather than a few lines inside the workflow: the zip is what the
# owner actually installs from, so what goes into it -- the build tree *and* the
# installer that knows how to make a shortcut Windows will show toasts for -- is
# part of the product, not part of the CI configuration. Having one definition
# also means the layout can be produced and tried out locally before a release
# discovers it is wrong.
#
# Layout inside the zip, which `install-windows-app.ps1` depends on:
#
#     taskradar-<version>-windows-x64/
#       TaskRadar/                     <- the whole flutter build output
#         taskradar.exe
#         flutter_windows.dll, data/, ...
#       install-windows-app.ps1
#       README.txt
#
# A single top-level folder because Windows' own zip extraction does not create
# one, and unpacking a bare tree into Downloads spreads forty files across it.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\package-windows-app.ps1 -Version 1.2.3
[CmdletBinding()]
param(
    # Version the zip is named after. Free-form on purpose: CI passes the
    # release tag, a local run can pass "dev".
    [Parameter(Mandatory = $true)]
    [string] $Version,

    # The build to pack. Defaults to this repository's release build.
    [string] $Source,

    # Where the zip and its checksum land.
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ASCII only, for the reason spelled out in install-windows-app.ps1: Windows
# PowerShell 5.1 reads a BOM-less .ps1 as the system ANSI codepage.
$appName = 'TaskRadar'
$exeName = 'taskradar.exe'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if (-not $Source) {
    $Source = Join-Path $repositoryRoot 'app\build\windows\x64\runner\Release'
}
if (-not $OutputDirectory) {
    $OutputDirectory = $repositoryRoot
}

if (-not (Test-Path -LiteralPath (Join-Path $Source $exeName))) {
    throw "No Windows build at '$Source'. Run: cd app; flutter build windows --release"
}

$installer = Join-Path $PSScriptRoot 'install-windows-app.ps1'
if (-not (Test-Path -LiteralPath $installer)) {
    throw "The installer is missing at '$installer'."
}

$name = "taskradar-$Version-windows-x64"
$staging = Join-Path ([System.IO.Path]::GetTempPath()) "taskradar-package-$([guid]::NewGuid())"
$payload = Join-Path $staging $name

New-Item -ItemType Directory -Path (Join-Path $payload $appName) -Force | Out-Null
Copy-Item -Path (Join-Path $Source '*') -Destination (Join-Path $payload $appName) -Recurse -Force
Copy-Item -Path $installer -Destination $payload -Force

# Deliberately short, and deliberately about the two things that are not
# obvious: that the shortcut is what makes notifications work at all, and that
# the API address is already baked into this build.
$readme = @"
TaskRadar $Version (Windows x64)

Install:
    powershell -ExecutionPolicy Bypass -File install-windows-app.ps1

This copies TaskRadar\ to %LOCALAPPDATA%\Programs\TaskRadar and creates a Start
menu shortcut. The shortcut is not a convenience: Windows only shows
notifications for an unpackaged app that has one, carrying the app's identity.

Add -Autostart to also start TaskRadar when you sign in, or -Uninstall to
remove it again.

Running taskradar.exe straight out of this folder works, but nothing will
remind you of anything.

The server address is built into this download; there is no setting for it.
"@
Set-Content -Path (Join-Path $payload 'README.txt') -Value $readme -Encoding utf8

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$zipPath = Join-Path $OutputDirectory "$name.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path $payload -DestinationPath $zipPath -CompressionLevel Optimal

# Same format as the APK's checksum file (`sha256sum` output), so both releases
# can be verified the same way.
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path "$zipPath.sha256" -Value "$hash  $name.zip" -Encoding ascii

Remove-Item -LiteralPath $staging -Recurse -Force

Write-Host "Packed $zipPath"
Write-Host "sha256 $hash"
