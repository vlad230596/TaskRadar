<#
.SYNOPSIS
  Links the TaskRadar agent skill (agent-skill/taskradar) into ~/.claude/skills,
  so Claude Code knows about TaskRadar in every project on this machine.

.DESCRIPTION
  A directory junction, not a copy: the skill stays versioned here next to the
  MCP server it describes, and a `git pull` of this checkout updates it
  everywhere. Whatever was at ~/.claude/skills/taskradar before is moved aside
  to taskradar.bak-<timestamp> (a junction is just removed).

  The MCP server itself is configured once per machine, in user scope:
    claude mcp add --scope user --transport http taskradar https://<host>/mcp `
      --header "Authorization: Bearer trk_..."
  (the token comes from the app: Настройки -> Агенты).
#>
$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot '..\agent-skill\taskradar' | Resolve-Path
$skills = Join-Path $env:USERPROFILE '.claude\skills'
$target = Join-Path $skills 'taskradar'

New-Item -ItemType Directory -Force $skills | Out-Null

$existing = Get-Item $target -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    if ($existing.LinkType -eq 'Junction' -or $existing.LinkType -eq 'SymbolicLink') {
        if ($existing.Target -contains $source.Path) {
            Write-Host "Already linked: $target -> $($source.Path)"
            exit 0
        }
        $existing.Delete()
    } else {
        $backup = "$target.bak-$(Get-Date -Format yyyyMMddHHmmss)"
        Move-Item $target $backup
        Write-Host "Moved the old skill aside: $backup"
    }
}

New-Item -ItemType Junction -Path $target -Target $source.Path | Out-Null
Write-Host "Linked: $target -> $($source.Path)"

$config = Join-Path $env:USERPROFILE '.claude.json'
if (-not (Test-Path $config) -or -not ((Get-Content $config -Raw) -match '"taskradar"')) {
    Write-Warning 'No taskradar MCP server in ~/.claude.json yet -- add it in user scope (see the help of this script).'
}
