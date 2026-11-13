# Pulls the TaskRadar production database and task pictures to this machine over SSH.
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

# Runs ssh with $Arguments and writes its stdout to $OutputPath, its stderr to
# $ErrorPath; returns the exit code.
# Drain SSH stdout as bytes before checking the result. Start-Process's
# asynchronous redirection can otherwise leave a truncated file at process exit.
function Invoke-SshToFile {
    param([string[]] $Arguments, [string] $OutputPath, [string] $ErrorPath)

    $sshInfo = New-Object System.Diagnostics.ProcessStartInfo
    $sshInfo.FileName = 'ssh.exe'
    $sshInfo.Arguments = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $sshInfo.UseShellExecute = $false
    $sshInfo.CreateNoWindow = $true
    $sshInfo.RedirectStandardOutput = $true
    $sshInfo.RedirectStandardError = $true
    $sshProcess = New-Object System.Diagnostics.Process
    $sshProcess.StartInfo = $sshInfo
    $outputStream = $null
    try {
        if (-not $sshProcess.Start()) { throw 'Could not start SSH.' }
        $stderrTask = $sshProcess.StandardError.ReadToEndAsync()
        $outputStream = [System.IO.File]::Create($OutputPath)
        $sshProcess.StandardOutput.BaseStream.CopyTo($outputStream)
        $outputStream.Dispose()
        $outputStream = $null
        $sshProcess.WaitForExit()
        [System.IO.File]::WriteAllText($ErrorPath, $stderrTask.GetAwaiter().GetResult())
        return $sshProcess.ExitCode
    } finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        $sshProcess.Dispose()
    }
}

function Read-SshError([string] $ErrorPath) {
    if (Test-Path -LiteralPath $ErrorPath) {
        (Get-Content -LiteralPath $ErrorPath -Raw).Trim()
    } else {
        'No SSH error output was captured.'
    }
}

# Written to a .partial file first, so an interrupted transfer can never be
# mistaken for the current dump by the snapshot that follows.
$exitCode = Invoke-SshToFile -Arguments $sshArguments -OutputPath $partialPath -ErrorPath $stderrPath
if ($exitCode -ne 0) {
    $stderr = Read-SshError $stderrPath
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
    throw "Database export failed with SSH exit code ${exitCode}: $stderr"
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
Write-Output "TaskRadar database export completed: $($dump.Length) bytes, SHA-256 $hash"

# Task pictures: a second call, after the database (BACKUPS.md, "Картинки
# задач"). In this order a picture uploaded in between is in the archive without
# a row -- harmless, the sweep removes it -- rather than a row without a picture.
# The forced command maps the word `attachments` to a fixed exporter.
$attachmentsPath = Join-Path $destinationDirectory 'taskradar-attachments.tar'
$attachmentsPartial = "$attachmentsPath.partial"
$attachmentsStderr = "$attachmentsPath.stderr"
Remove-Item -LiteralPath $attachmentsPartial, $attachmentsStderr -Force -ErrorAction SilentlyContinue

$exitCode = Invoke-SshToFile -Arguments ($sshArguments + 'attachments') -OutputPath $attachmentsPartial -ErrorPath $attachmentsStderr
if ($exitCode -ne 0) {
    $stderr = Read-SshError $attachmentsStderr
    Remove-Item -LiteralPath $attachmentsPartial -Force -ErrorAction SilentlyContinue
    throw "Attachments export failed with SSH exit code ${exitCode}: $stderr"
}

$archive = Get-Item -LiteralPath $attachmentsPartial
if ($archive.Length -eq 0) {
    throw 'Attachments export produced an empty file.'
}

# A cut stream is a truncated tar, and listing it end to end fails on one: this
# is the completeness check, like the pg_dump marker above. tar.exe ships with
# Windows 10+.
& "$env:SystemRoot\System32\tar.exe" -tf $attachmentsPartial > $null
if ($LASTEXITCODE -ne 0) {
    throw 'Attachments export is not a complete tar archive.'
}

$attachmentsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $attachmentsPartial).Hash
Move-Item -LiteralPath $attachmentsPartial -Destination $attachmentsPath -Force
# stderr carries the orphan sweep's report; keep the last one next to the archive.
Move-Item -LiteralPath $attachmentsStderr -Destination (Join-Path $destinationDirectory 'last-sweep.log') -Force
Write-Output "TaskRadar attachments export completed: $($archive.Length) bytes, SHA-256 $attachmentsHash"

[ordered]@{
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    path = $destinationPath
    bytes = $dump.Length
    sha256 = $hash
    attachmentsPath = $attachmentsPath
    attachmentsBytes = $archive.Length
    attachmentsSha256 = $attachmentsHash
} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8

Remove-Item -LiteralPath $errorStatusPath -Force -ErrorAction SilentlyContinue
