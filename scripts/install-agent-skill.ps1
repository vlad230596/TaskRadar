<#
.SYNOPSIS
  Links the TaskRadar agent skill (agent-skill/taskradar) into the skills
  folder of Claude Code (~/.claude/skills) and/or Codex (~/.codex/skills), so
  the agent knows about TaskRadar in every project on this machine.

.PARAMETER Agent
  claude, codex, or all (default): every agent whose home folder exists.

.DESCRIPTION
  A directory junction, not a copy: the skill stays versioned here next to the
  MCP server it describes, and a `git pull` of this checkout updates it
  everywhere. Whatever was at <skills>/taskradar before is moved aside to
  taskradar.bak-<timestamp> (a junction is just removed).

  The MCP server itself is configured once per machine and agent, each with
  its own token (the app: Настройки -> Агенты):

  Claude Code, user scope:
    claude mcp add --scope user --transport http taskradar https://task-radar.duckdns.org:8443/mcp `
      --header "Authorization: Bearer trk_..."

  Codex, ~/.codex/config.toml (the token in the user environment variable
  TASKRADAR_TOKEN, never in the file):
    [mcp_servers.taskradar]
    url = "https://task-radar.duckdns.org:8443/mcp"
    bearer_token_env_var = "TASKRADAR_TOKEN"
#>
param(
    [ValidateSet('claude', 'codex', 'all')]
    [string]$Agent = 'all'
)
$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot '..\agent-skill\taskradar' | Resolve-Path

function Install-Link([string]$home_, [string]$name) {
    $skills = Join-Path $home_ 'skills'
    $target = Join-Path $skills 'taskradar'
    New-Item -ItemType Directory -Force $skills | Out-Null

    $existing = Get-Item $target -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        if ($existing.LinkType -eq 'Junction' -or $existing.LinkType -eq 'SymbolicLink') {
            if ($existing.Target -contains $source.Path) {
                Write-Host "${name}: already linked: $target -> $($source.Path)"
                return
            }
            $existing.Delete()
        } else {
            $backup = "$target.bak-$(Get-Date -Format yyyyMMddHHmmss)"
            Move-Item $target $backup
            Write-Host "${name}: moved the old skill aside: $backup"
        }
    }
    New-Item -ItemType Junction -Path $target -Target $source.Path | Out-Null
    Write-Host "${name}: linked $target -> $($source.Path)"
}

$claudeHome = Join-Path $env:USERPROFILE '.claude'
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }

if ($Agent -eq 'claude' -or ($Agent -eq 'all' -and (Test-Path $claudeHome))) {
    Install-Link $claudeHome 'Claude Code'
    $config = Join-Path $env:USERPROFILE '.claude.json'
    if (-not (Test-Path $config) -or -not ((Get-Content $config -Raw) -match '"taskradar"')) {
        Write-Warning 'Claude Code: no taskradar MCP server in ~/.claude.json yet (see the help of this script).'
    }
}

if ($Agent -eq 'codex' -or ($Agent -eq 'all' -and (Test-Path $codexHome))) {
    Install-Link $codexHome 'Codex'
    $config = Join-Path $codexHome 'config.toml'
    if (-not (Test-Path $config) -or -not ((Get-Content $config -Raw) -match '\[mcp_servers\.taskradar\]')) {
        Write-Warning 'Codex: no [mcp_servers.taskradar] in config.toml yet (see the help of this script).'
    }
    if (-not [Environment]::GetEnvironmentVariable('TASKRADAR_TOKEN', 'User')) {
        Write-Warning 'Codex: user environment variable TASKRADAR_TOKEN is not set.'
    }
}
