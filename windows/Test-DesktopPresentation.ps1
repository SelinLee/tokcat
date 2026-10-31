$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Monitor.ps1')
. (Join-Path $PSScriptRoot 'AgentPresentation.ps1')
. (Join-Path $PSScriptRoot 'DesktopPresentation.ps1')
function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message : expected '$Expected', got '$Actual'" }
}
$now = [datetimeoffset]::Parse('2026-10-31T04:00:00Z')
$sessions = @(
    [pscustomobject]@{ Source='Codex'; Id='1'; State='running'; Updated=$now; Title='Fix [UI]'; Project='C:\demo'; Model='gpt-test'; Phase='Editing' },
    [pscustomobject]@{ Source='Claude Code'; Id='2'; State='approval'; Updated=$now.AddSeconds(-15); Title='Review'; Project='C:\demo'; Model='claude-test'; Phase='Waiting' },
    [pscustomobject]@{ Source='Codex'; Id='3'; State='running'; Updated=$now.AddSeconds(-121); Title='Long tool'; Project='C:\other'; Model='gpt-test'; Phase='Tool' },
    [pscustomobject]@{ Source='WorkBuddy'; Id='4'; State='completed'; Updated=$now; Title='Done'; Project='C:\demo'; Model='test'; Phase='Done' },
    [pscustomobject]@{ Source='Kimi'; Id='5'; State='unknown'; Updated=$now; Title='Activity'; Project='C:\demo'; Model='test'; Phase='Activity' }
)
$all = @(Select-DesktopSessions $sessions '' '全部 Agent' 0 $now)
Assert-Equal $all.Count 5 'all recent tasks remain visible'
Assert-Equal $all[0].Session.Id '2' 'tasks requiring attention sort first'
Assert-Equal $all[1].State 'stalled' 'silent running task is presented as inactive'
Assert-Equal $sessions[2].State 'running' 'presentation does not change lifecycle state'
$literal = @(Select-DesktopSessions $sessions '[ui]' '' 0 $now)
Assert-Equal $literal.Count 1 'search is literal and case insensitive'
Assert-Equal $literal[0].Session.Id '1' 'literal bracket query finds task title'
Assert-Equal @(Select-DesktopSessions $sessions '?' '' 0 $now).Count 0 'question mark does not match every task'
Assert-Equal @(Select-DesktopSessions $sessions ' C:\OTHER ' '' 0 $now).Count 1 'search trims whitespace and matches projects'
Assert-Equal @(Select-DesktopSessions $sessions 'CLAUDE-TEST' '' 0 $now).Count 1 'model search works'
Assert-Equal @(Select-DesktopSessions $sessions '' 'Codex' 0 $now).Count 2 'Agent filter keeps exact source'
Assert-Equal @(Select-DesktopSessions $sessions '' '' 1 $now).Count 1 'running filter excludes inactive tasks'
Assert-Equal @(Select-DesktopSessions $sessions '' '' 2 $now).Count 1 'attention filter includes authorization waits'
Assert-Equal @(Select-DesktopSessions $sessions '' '' 3 $now).Count 1 'completed filter'
Assert-Equal @(Select-DesktopSessions $sessions '' '' 4 $now).Count 1 'problem filter includes inactivity'
Assert-Equal @(Select-DesktopSessions $sessions '' '' 5 $now).Count 1 'unknown filter'
Assert-Equal @(Select-DesktopSessions $sessions 'Review' 'Codex' 2 $now).Count 0 'filters compose without changing the snapshot'
Assert-Equal @(Select-DesktopSessions @() '' '' 0 $now).Count 0 'empty first launch'
Write-Host 'Desktop search, filters and priority checks passed.'
