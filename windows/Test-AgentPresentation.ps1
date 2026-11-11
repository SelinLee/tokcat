$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Monitor.ps1')
. (Join-Path $PSScriptRoot 'AgentPresentation.ps1')
Add-Type -Path (Join-Path $PSScriptRoot 'ForegroundAgent.cs')
function Check($Actual,$Expected,[string]$Label) { if ($Actual -ne $Expected) { throw "$Label : expected '$Expected', got '$Actual'" } }
$start=[datetimeoffset]::FromUnixTimeSeconds(1000)
function At([double]$Seconds) { return $start.AddSeconds($Seconds) }
function Session([string]$Id,[string]$Source='Codex',[string]$State='completed',[double]$Updated=0,[string]$Turn='one') {
    return [pscustomobject]@{ Id=$Id; Source=$Source; State=$State; Updated=(At $Updated); TurnId=$Turn }
}
function Dots($Sessions,$Unread,[double]$Time,$Flashing=@{},[bool]$ReduceMotion=$false) { return Get-TaskbarDotPresentation @($Sessions) $Unread $Flashing (At $Time) $ReduceMotion }

# Mirror the Mac foreground-viewing tracker: each result gets a fresh three seconds.
$first=Session 'first'; $second=Session 'second' 'Codex' 'failed' 13
$unread=@{'Codex:first'=$true;'Codex:second'=$true}; $pending=@{}
$update=Update-ViewedReminders @($first) $unread $pending 'Codex' (At 12)
Check $update.FlashingSince['Codex:first'] (At 12) 'countdown begins at observation, not completion'
Check $unread.Count 2 'initial focus keeps reminders'
$update=Update-ViewedReminders @($first,$second) $unread $pending 'Codex' (At 13)
Check $update.FlashingSince['Codex:first'] (At 12) 'polling does not reset an existing countdown'
Check $update.FlashingSince['Codex:second'] (At 13) 'a later result gets its own countdown'
Check (Dots @($first) $unread 12.5 $update.FlashingSince).Dimmed[0] $true 'viewed result flashes before disappearing'
Check (Dots @($first) $unread 12.5 $update.FlashingSince $true).Dimmed[0] $false 'reduced motion keeps the dot steady'
$null=Update-ViewedReminders @($first,$second) $unread $pending 'Codex' (At 14.99)
Check $unread.Count 2 'neither result disappears before its deadline'
$update=Update-ViewedReminders @($first,$second) $unread $pending 'Codex' (At 15)
Check $update.Changed $true 'first reminder acknowledged at three seconds'
Check $unread.ContainsKey('Codex:first') $false 'only the elapsed result is read'
Check $unread.ContainsKey('Codex:second') $true 'newer failure remains visible'
Check (Dots @($first) $unread 15).States.Count 0 'read completion loses its dot'
$null=Update-ViewedReminders @($second) $unread $pending 'Codex' (At 16)
Check $unread.Count 0 'failure follows the same three-second rule'

$task=Session 'task'; $other=Session 'other' 'WorkBuddy'; $unread=@{'Codex:task'=$true;'WorkBuddy:other'=$true}; $pending=@{}
$null=Update-ViewedReminders @($task,$other) $unread $pending 'Codex' (At 0)
$null=Update-ViewedReminders @($task,$other) $unread $pending '' (At 2)
Check $pending.Count 0 'switching to an unrelated app cancels viewing'
$null=Update-ViewedReminders @($task,$other) $unread $pending 'Codex' (At 20)
$null=Update-ViewedReminders @($task,$other) $unread $pending 'Codex' (At 22.99)
Check $unread.Count 2 'returning requires three continuous seconds'
$null=Update-ViewedReminders @($task,$other) $unread $pending 'Codex' (At 23)
Check $unread.ContainsKey('WorkBuddy:other') $true 'another source is never acknowledged'

$unread=@{'Codex:task'=$true}; $pending=@{}
$null=Update-ViewedReminders @($task) $unread $pending 'Codex' (At 0)
$task.TurnId='two'; $task.Updated=At 2
$null=Update-ViewedReminders @($task) $unread $pending 'Codex' (At 2)
$null=Update-ViewedReminders @($task) $unread $pending 'Codex' (At 3)
Check $unread.Count 1 'an older countdown cannot clear a newer turn'
$task.State='failed'
$null=Update-ViewedReminders @($task) $unread $pending 'Codex' (At 4)
$null=Update-ViewedReminders @($task) $unread $pending 'Codex' (At 5)
Check $unread.Count 1 'a changed result state also restarts viewing'
$task.State='running'
$update=Update-ViewedReminders @($task) $unread $pending 'Codex' (At 7)
Check $update.FlashingSince.Count 0 'resuming cancels the countdown'
Check $unread.Count 1 'viewing never acknowledges a running task'

$unknown=Session 'unknown' 'Codex' 'unknown'
Check (Dots @($unknown) @{} 9.99).States.Count 1 'unknown dot starts visible'
Check (Dots @($unknown) @{} 10.5).Dimmed[0] $true 'uncertain state flashes during the last three seconds'
Check (Dots @($unknown) @{} 12.99).States.Count 1 'unknown grace is thirteen seconds'
Check (Dots @($unknown) @{} 13).States.Count 0 'unknown disappears exactly at thirteen seconds'
$interrupted=Session 'interrupted' 'Codex' 'interrupted'
Check (Dots @($interrupted) @{} 1).States.Count 0 'historical read interruption stays hidden'
$unread=@{'Codex:interrupted'=$true}
Check (Dots @($interrupted) $unread 12.99).States.Count 1 'fresh unread interruption gets the uncertainty grace'
Check (Dots @($interrupted) $unread 13).States.Count 0 'interruption expires after thirteen seconds'
$running=Session 'running' 'Codex' 'running'
Check (Dots @($running) @{} 119.99).States[0] 'running' 'active-state warning boundary'
Check (Dots @($running) @{} 120).States[0] 'stalled' 'silence warns at two minutes'
Check (Dots @($running) @{} 3600).States.Count 1 'stalled tasks do not expire'
foreach ($state in @('waiting','approval')) { Check (Dots @((Session $state 'Codex' $state)) @{} 3600).States.Count 1 'human-action dots do not time out' }
Check (Dots @((Session 'activity' 'OpenClaw' 'unknown')) @{} 1).States.Count 0 'activity-only records do not claim a live task'

$cloud=Session 'offline' 'Codex Work' 'running' -1800; $native=Session 'native' 'Codex' 'running'; $cache=@{}; $observed=@{}
$snapshot=@(Merge-WorkStatusSnapshot @($cloud,$native) $cache $true (At 0)); Update-DotObservations $snapshot $observed (At 0)
$snapshot=@(Merge-WorkStatusSnapshot @($native) $cache $false (At 119)); Update-DotObservations $snapshot $observed (At 119)
Check @($snapshot | Where-Object { $_.State -eq 'running' }).Count 2 'brief catalog failures preserve the last known cloud status'
$snapshot=@(Merge-WorkStatusSnapshot @($native) $cache $false (At 120)); Update-DotObservations $snapshot $observed (At 120)
Check @($snapshot | Where-Object { $_.State -eq 'unknown' }).Count 1 'after two minutes unavailable cloud status becomes uncertain'
Check (Dots $snapshot @{} 132.99).States.Count 2 'cloud uncertainty receives a full thirteen-second grace'
Check (Dots $snapshot @{} 133).States.Count 1 'only the unavailable cloud dot expires'
$snapshot=@(Merge-WorkStatusSnapshot @($cloud,$native) $cache $true (At 140)); Update-DotObservations $snapshot $observed (At 140)
Check (Dots $snapshot @{} 140).States.Count 2 'catalog recovery restores the dot'
$cloud.State='completed'; $null=Merge-WorkStatusSnapshot @($cloud) $cache $true (At 141)
$snapshot=@(Merge-WorkStatusSnapshot @() $cache $false (At 400))
Check $snapshot[0].State 'completed' 'catalog failure does not erase an unread completion'

# A Work state-loss revision survives unchanged polls and application restarts.
$work=Session 'work' 'Codex Work' 'running' -1800; $observations=@{}
Update-DotObservations @($work) $observations (At 0)
$work.State='unknown'; Update-DotObservations @($work) $observations (At 1)
Check (Dots @($work) @{} 13.99).States.Count 1 'Work losing status gets a new grace period'
Update-DotObservations @($work) $observations (At 10)
Check $work.StateObservedAt (At 1) 'polling does not renew unknown Work status'
Check (Dots @($work) @{} 14).States.Count 0 'lost Work status expires once'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('tokcat-dot-test-' + [guid]::NewGuid().ToString('N'))
try {
    $path=Join-Path $testRoot 'observations.json'; Write-DotObservations $path $observations; $loaded=Read-DotObservations $path
    Update-DotObservations @($work) $loaded (At 15)
    Check (Dots @($work) @{} 15).States.Count 0 'restart cannot revive expired Work dots'
    $work.State='running'; Update-DotObservations @($work) $loaded (At 20)
    Check (Dots @($work) @{} 20).States.Count 1 'explicit running status restores a Work dot'
    $work.State='completed'; Update-DotObservations @($work) $loaded (At 21)
    $unread=@{'Codex Work:work'=$true}; $pending=@{}
    $null=Update-ViewedReminders @($work) $unread $pending 'Codex' (At 21)
    $work.Updated=At 22; Update-DotObservations @($work) $loaded (At 22)
    $null=Update-ViewedReminders @($work) $unread $pending 'Codex' (At 24)
    Check $unread.Count 0 'catalog metadata cannot postpone a completed Work reminder'
    $saved=@{}; Sync-ReminderStore @($work) $unread $saved (At 24); $reminderPath=Join-Path $testRoot 'reminders.json'; Write-ReminderStore $reminderPath $saved
    Check (Read-ReminderStore $reminderPath).Count 0 'automatic acknowledgement persists'
    Write-DotObservations $path @{}
    Check (Read-DotObservations $path).Count 0 'empty observation stores remain readable'
} finally {
    $resolved=[IO.Path]::GetFullPath($testRoot); $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if ($resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^tokcat-dot-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

Check ([TokcatForegroundAgent]::SourceForExecutable('C:\Program Files\WindowsApps\OpenAI.Codex_26.0_x64__package\app\ChatGPT.exe')) 'Codex' 'recognize the installed Codex GUI executable'
Check ([TokcatForegroundAgent]::SourceForExecutable('C:\Apps\ChatGPT\ChatGPT.exe')) $null 'unrelated ChatGPT is not Codex'
foreach ($name in @('WindowsTerminal.exe','powershell.exe','Code.exe','chrome.exe','msedge.exe')) { Check ([TokcatForegroundAgent]::SourceForExecutable($name)) $null 'generic editors terminals and browsers cannot identify an agent' }
Check ([TokcatForegroundAgent]::SourceForExecutable('WorkBuddy.exe')) 'WorkBuddy' 'WorkBuddy source identity'
Check ([TokcatForegroundAgent]::SourceForExecutable('WorkBuddy-AI.exe')) 'WorkBuddy AI' 'WorkBuddy AI is distinct'
Check ([TokcatForegroundAgent]::SourceForExecutable('WorkBuddyAI.exe')) 'WorkBuddy AI' 'recognize the installed WorkBuddy AI executable'
Check ([TokcatForegroundAgent]::SourceForExecutable('Claude.exe')) 'Claude Code' 'Claude source identity'
Check ([TokcatForegroundAgent]::SourceForExecutable('DSH Desktop.exe')) 'DeepSeek Harness' 'DSH desktop source identity'
Write-Output 'Agent dot lifecycle checks passed.'
