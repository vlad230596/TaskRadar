# Installs and verifies a SYSTEM-readable copy of the TaskRadar backup SSH key.
#
# Why this script exists at all: Backrest runs as the SYSTEM account, and SYSTEM
# cannot read a key stored under a user profile's .ssh directory. The failure is
# not obvious -- the plan simply reports a failed pre-snapshot command with an
# SSH permission error -- and the tempting fix (loosening the ACL on the real
# key) would expose it to every process on the machine. Instead SYSTEM gets its
# own copy, owned by SYSTEM with inheritance disabled, and then the script
# proves the copy actually works by running the real export once as SYSTEM.
#
# Run from an elevated PowerShell prompt.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Server,
    [string] $ProfilePath = $env:USERPROFILE,
    [string] $StagingStatusPath = 'D:\Backups\TaskRadar\staging\last-export.json'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run from an elevated PowerShell process.'
}

$clientDirectory = Join-Path $ProfilePath 'AppData\Local\TaskRadarBackup'
$pullScript = Join-Path $clientDirectory 'pull-production-backup.ps1'
$privateKey = Join-Path $ProfilePath '.ssh\taskradar-backup-pc1'
$systemPrivateKey = Join-Path $clientDirectory 'taskradar-backup-system-key'
$knownHosts = Join-Path $ProfilePath '.ssh\known_hosts'
$statusPath = Join-Path $clientDirectory 'system-backup-verification.json'
$taskName = 'TaskRadar Backup Verification'

foreach ($requiredPath in @($pullScript, $privateKey, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required backup file not found: $requiredPath"
    }
}

# A previous run left a SYSTEM-owned file that the current administrator cannot
# overwrite, so ownership has to be reclaimed before replacing it.
if (Test-Path -LiteralPath $systemPrivateKey -PathType Leaf) {
    & takeown.exe /F $systemPrivateKey /A | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to take temporary ownership of the existing SYSTEM SSH key.'
    }
    & icacls.exe $systemPrivateKey /grant '*S-1-5-32-544:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to make the existing SYSTEM SSH key replaceable.'
    }
}

Copy-Item -LiteralPath $privateKey -Destination $systemPrivateKey -Force

# SetAccessRuleProtection($true, $false) drops inherited permissions instead of
# converting them to explicit ones, which is what leaves SYSTEM as the only
# account on the copy. Administrators are deliberately not re-added: the file is
# replaceable by taking ownership above, and nothing else needs to read it.
$systemKeyAcl = New-Object System.Security.AccessControl.FileSecurity
$systemKeyAcl.SetOwner((New-Object System.Security.Principal.NTAccount('SYSTEM')))
$systemKeyAcl.SetAccessRuleProtection($true, $false)
$systemKeyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'SYSTEM',
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    [System.Security.AccessControl.AccessControlType]::Allow
)
$systemKeyAcl.AddAccessRule($systemKeyRule)
Set-Acl -LiteralPath $systemPrivateKey -AclObject $systemKeyAcl

# StrictHostKeyChecking=yes in the pull script means SYSTEM must be able to read
# known_hosts too, otherwise the verification below fails on host verification
# rather than on the key.
& icacls.exe $knownHosts /grant:r 'SYSTEM:(R)' | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to grant SYSTEM read access to known_hosts.'
}

$arguments = @(
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy', 'Bypass',
    '-File', "`"$pullScript`"",
    '-Server', "`"$Server`"",
    '-SshKey', "`"$systemPrivateKey`"",
    '-KnownHostsFile', "`"$knownHosts`""
) -join ' '
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(10))
$taskPrincipal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# A temporary scheduled task is the only reliable way to execute something *as*
# SYSTEM for a one-off check; it is unregistered again in the finally block.
$startedAt = Get-Date
try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $taskPrincipal `
        -Settings $settings `
        -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName

    $deadline = (Get-Date).AddMinutes(2)
    do {
        Start-Sleep -Seconds 2
        $task = Get-ScheduledTask -TaskName $taskName
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
    } while (
        (Get-Date) -lt $deadline -and
        ($task.State -eq 'Running' -or $taskInfo.LastRunTime -lt $startedAt.AddSeconds(-5))
    )

    if ($taskInfo.LastTaskResult -ne 0) {
        throw "SYSTEM backup verification failed with task result $($taskInfo.LastTaskResult)."
    }

    # The task result alone is not proof: a stale status file from an earlier
    # interactive run would look identical. The timestamp is what shows the
    # export really happened just now, as SYSTEM.
    $exportStatus = Get-Content -LiteralPath $StagingStatusPath -Raw | ConvertFrom-Json
    if ([DateTime]::Parse($exportStatus.completedAtUtc).ToUniversalTime() -lt $startedAt.ToUniversalTime()) {
        throw 'SYSTEM backup verification did not produce a fresh export status.'
    }

    [ordered]@{
        checkedAtUtc = [DateTime]::UtcNow.ToString('o')
        taskResult = $taskInfo.LastTaskResult
        exportCompletedAtUtc = $exportStatus.completedAtUtc
        exportBytes = $exportStatus.bytes
        exportSha256 = $exportStatus.sha256
        systemPrivateKey = $systemPrivateKey
    } | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
} finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Output "TaskRadar backup access verified as SYSTEM. Status: $statusPath"
