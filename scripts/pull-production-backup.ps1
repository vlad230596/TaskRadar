# Pulls the TaskRadar production database to this machine over SSH.
#
# Pull model, not push: the VDS never learns where the backups live and holds no
# credentials for this machine, so compromising the server does not give access
# to the backup history. This script is meant to be the pre-snapshot command of
# a local Backrest/restic plan (see BACKUPS.md).
#
# It fails loudly instead of producing an empty or truncated snapshot -- a backup
# that silently succeeds with no data is worse than no backup at all, because it
# stops anyone from looking.
[CmdletBinding()]
param(
    [string] $Destination = 'D:\Backups\TaskRadar\staging\taskradar.sql',
    [string] $SshKey = "$env:USERPROFILE\.ssh\taskradar-backup-pc1",
    [string] $KnownHostsFile = "$env:USERPROFILE\.ssh\known_hosts",
    [Parameter(Mandatory = $true)][string] $Server,
    [string] $SshUser = 'taskradar-backup'
)

$ErrorActionPreference = 'Stop'

$destinationPath = [System.IO.Path]::GetFullPath($Destination)
$destinationDirectory = Split-Path -Parent $destinationPath
$partialPath = "$destinationPath.partial"
$stderrPath = "$destinationPath.stderr"
$statusPath = Join-Path $destinationDirectory 'last-export.json'
$errorStatusPath = Join-Path $destinationDirectory 'last-export-error.log'

# Backrest runs this unattended, so a failure has to leave a readable trace on
# disk rather than only in a transient console.
trap {
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    ($_ | Out-String) | Set-Content -LiteralPath $errorStatusPath -Encoding utf8
    throw
}

if (-not (Test-Path -LiteralPath $SshKey -PathType Leaf)) {
    throw "SSH key not found: $SshKey"
}
if (-not (Test-Path -LiteralPath $KnownHostsFile -PathType Leaf)) {
    throw "SSH known_hosts file not found: $KnownHostsFile"
}

New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
Remove-Item -LiteralPath $partialPath, $stderrPath -Force -ErrorAction SilentlyContinue

# No command is passed: the server side forces one (see
# scripts/taskradar-backup-forced-command.sh). BatchMode plus
# StrictHostKeyChecking=yes means an unknown host key or a prompt of any kind
# fails the run instead of hanging a scheduled task forever.
$sshArguments = @(
    '-T',
    '-i', $SshKey,
    '-o', 'BatchMode=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$KnownHostsFile",
    '-o', 'ConnectTimeout=20',
    "$SshUser@$Server"
)

# Written to a .partial file first, so an interrupted transfer can never be
# mistaken for the current dump by the snapshot that follows.
$process = Start-Process `
    -FilePath 'ssh.exe' `
    -ArgumentList $sshArguments `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $partialPath `
    -RedirectStandardError $stderrPath

if ($process.ExitCode -ne 0) {
    $stderr = if (Test-Path -LiteralPath $stderrPath) {
        (Get-Content -LiteralPath $stderrPath -Raw).Trim()
    } else {
        'No SSH error output was captured.'
    }
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
    throw "Database export failed with SSH exit code $($process.ExitCode): $stderr"
}

$dump = Get-Item -LiteralPath $partialPath
if ($dump.Length -eq 0) {
    throw 'Database export produced an empty file.'
}

# pg_dump writes this marker as its last line. Exit code 0 from ssh only proves
# the connection closed cleanly, not that the dump finished, so this is the check
# that actually catches a stream cut in the middle.
if (-not (Select-String -LiteralPath $partialPath -SimpleMatch 'PostgreSQL database dump complete' -Quiet)) {
    throw 'Database export is incomplete: the pg_dump completion marker is missing.'
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $partialPath).Hash
Move-Item -LiteralPath $partialPath -Destination $destinationPath -Force
Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue

[ordered]@{
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    path = $destinationPath
    bytes = $dump.Length
    sha256 = $hash
} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8

Remove-Item -LiteralPath $errorStatusPath -Force -ErrorAction SilentlyContinue
Write-Output "TaskRadar database export completed: $($dump.Length) bytes, SHA-256 $hash"
