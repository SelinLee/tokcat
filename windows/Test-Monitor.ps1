$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Monitor.ps1')
. (Join-Path $PSScriptRoot 'Conversation.ps1')
. (Join-Path $PSScriptRoot 'Usage.ps1')
. (Join-Path $PSScriptRoot 'Instance.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('tokcat-test-' + [guid]::NewGuid())
$sessions = Join-Path $root 'sessions'
New-Item -ItemType Directory -Path $sessions | Out-Null
function Assert-Equal($actual, $expected, $label) { if ($actual -ne $expected) { throw "$label : expected '$expected', got '$actual'" } }
try {
    $instanceName = 'tokcat-test-instance-' + [guid]::NewGuid()
    $firstInstance = Open-TokcatInstance $instanceName; $secondInstance = $null
    try {
        Assert-Equal $firstInstance.IsFirst $true 'first application instance owns guard'
        $secondInstance = Open-TokcatInstance $instanceName
        Assert-Equal $secondInstance.IsFirst $false 'duplicate application instance detected'
        [void]$secondInstance.Event.Set()
        Assert-Equal ($firstInstance.Event.WaitOne(0)) $true 'duplicate launch signals existing instance'
    } finally { if ($secondInstance) { Close-TokcatInstance $secondInstance }; Close-TokcatInstance $firstInstance }
    $log = Join-Path $sessions 'rollout-test.jsonl'
    $rows = @(
        '{"type":"session_meta","payload":{"id":"s1","cwd":"C:\\demo"}}',
        '{"timestamp":"2026-10-28T01:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}',
        '{"timestamp":"2026-10-28T01:00:01Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"q1"}}',
        '{"timestamp":"2026-10-28T01:00:02Z","type":"response_item","payload":{"type":"function_call_output","call_id":"unrelated"}}'
    )
    [IO.File]::WriteAllText($log, ($rows -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $s = Convert-CodexSession $log
    Assert-Equal $s.State 'waiting' 'unrelated tool does not resolve question'
    [IO.File]::AppendAllText($log, '{"timestamp":"2026-10-28T01:00:03Z","type":"response_item","payload":{"type":"function_call_output","call_id":"q1"}}' + "`n")
    Assert-Equal (Convert-CodexSession $log).State 'running' 'question response resumes'
    [IO.File]::AppendAllText($log, '{"timestamp":"2026-10-28T01:00:04Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1"}}' + "`n" + '{"timestamp":"2026-10-28T01:00:05Z","type":"response_item","payload":{"type":"reasoning"}}' + "`n")
    Assert-Equal (Convert-CodexSession $log).State 'completed' 'trailing activity does not reopen'
    [IO.File]::AppendAllText($log, '{"timestamp":"2026-10-28T01:00:06Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t2"}}' + "`n" + '{"timestamp":"2026-10-28T01:00:07Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1"}}' + "`n")
    Assert-Equal (Convert-CodexSession $log).State 'running' 'old turn cannot complete new turn'
    [IO.File]::AppendAllText($log, '{"timestamp":"2026-10-28T01:00:08Z","type":"event_msg","payload":{"type":"task_complete"}}')
    Assert-Equal (Convert-CodexSession $log).State 'running' 'partial record ignored'
    $longLog = Join-Path $sessions 'rollout-long.jsonl'
    $largePadding = '{"type":"ignored","padding":"' + ('x' * 2200000) + '"}'
    $longRows = @(
        '{"type":"session_meta","payload":{"id":"long"}}',
        '{"timestamp":"2026-10-28T01:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"long-turn"}}',
        $largePadding,
        '{"timestamp":"2026-10-28T01:00:01Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"q"}}'
    )
    [IO.File]::WriteAllText($longLog, ($longRows -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    Assert-Equal (Convert-CodexSession $longLog).State 'waiting' 'long log recovers the turn start and skips oversized record'
    # Keep the later session-list test scoped to its original single fixture.
    Remove-Item -LiteralPath $longLog -Force
    $usageLog = Join-Path $sessions 'rollout-usage.jsonl'
    $usageRows = @(
        '{"type":"session_meta","payload":{"id":"usage"}}',
        '{"timestamp":"2026-10-28T01:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"new"}}',
        '{"timestamp":"2026-10-28T01:00:02Z","type":"token_usage_record","payload":{"turn_id":"new","turn_token_usage":{"output_tokens":20}}}',
        '{"timestamp":"2026-10-28T01:00:05Z","type":"token_usage_record","payload":{"turn_id":"new","turn_token_usage":{"output_tokens":20}}}',
        '{"timestamp":"2026-10-28T01:00:06Z","type":"token_usage_record","payload":{"turn_id":"old","turn_token_usage":{"output_tokens":999}}}'
    )
    [IO.File]::WriteAllText($usageLog, ($usageRows -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $usageSession = Convert-CodexSession $usageLog
    Assert-Equal $usageSession.OutputTokens 20 'stale turn usage ignored'
    Assert-Equal $usageSession.Updated ([datetimeoffset]::Parse('2026-10-28T01:00:02Z')) 'only increasing output refreshes activity'
    Remove-Item -LiteralPath $usageLog -Force
    $internal = Join-Path $sessions 'rollout-internal.jsonl'
    [IO.File]::WriteAllText($internal, '{"type":"session_meta","payload":{"id":"s2","thread_source":"subagent"}}' + "`n")
    Assert-Equal (Convert-CodexSession $internal) $null 'subagent excluded'
    [IO.File]::WriteAllText((Join-Path $root 'session_index.jsonl'), '{"id":"s1","thread_name":"Test title"}' + "`n")
    $all = @(Get-CodexSessions $root)
    Assert-Equal $all.Count 1 'one visible session'
    Assert-Equal $all[0].Title 'Test title' 'index title'
    $dshHome = Join-Path $root 'dsh'
    $dshDir = Join-Path $dshHome 'storages\session_projcache\sessions'
    New-Item -ItemType Directory -Path $dshDir -Force | Out-Null
    $dsh = Join-Path $dshDir 'example.json'
    [IO.File]::WriteAllText($dsh, '{"record":{"identity":{"cwd":"C:\\demo"},"rows":{"title":{"val":"DSH task"},"sessionStats":{"val":{"openStep":{}}},"userQuestions":{"val":{"questions":{"active":[{"state":"open"}]}}},"tokenUsage":{"val":{"totals":{"outputTokens":42}}}}}}')
    $dshItems = @(Get-DshSessions @($dshHome))
    Assert-Equal $dshItems.Count 1 'DSH session'
    Assert-Equal $dshItems[0].State 'waiting' 'DSH open question takes priority'
    Assert-Equal $dshItems[0].OutputTokens 42 'DSH output tokens'
    Assert-Equal $dshItems[0].Title 'DSH task' 'DSH title'
    $workRoot = Join-Path $root 'work'
    $dbDir = Join-Path $workRoot 'sqlite'
    New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class TokcatTestDatabase {
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] path, out IntPtr db, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_exec(IntPtr db, byte[] sql, IntPtr callback, IntPtr arg, IntPtr error);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    public static void Create(string path) {
        IntPtr db; if (sqlite3_open_v2(Encoding.UTF8.GetBytes(path + "\0"), out db, 6, IntPtr.Zero) != 0) throw new Exception("open failed");
        try {
            string sql = "CREATE TABLE local_thread_catalog(host_id TEXT,thread_id TEXT,display_title TEXT,source_kind TEXT,source_updated_at REAL,conversation_origin TEXT,chatgpt_async_status INTEGER);" +
                "INSERT INTO local_thread_catalog VALUES('chatgpt:test','00000000-0000-0000-0000-000000000001','Work test','chatgpt'," + DateTimeOffset.UtcNow.ToUnixTimeSeconds() + ",'tpp',3);" +
                "INSERT INTO local_thread_catalog VALUES('chatgpt:test','00000000-0000-0000-0000-000000000002','Chat','chatgpt'," + DateTimeOffset.UtcNow.ToUnixTimeSeconds() + ",'chat',4);";
            if (sqlite3_exec(db, Encoding.UTF8.GetBytes(sql + "\0"), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) != 0) throw new Exception("fixture failed");
        } finally { sqlite3_close(db); }
    }
    public static void CreateBuddy(string path) {
        IntPtr db; if (sqlite3_open_v2(Encoding.UTF8.GetBytes(path + "\0"), out db, 6, IntPtr.Zero) != 0) throw new Exception("open failed");
        try {
            string now = (DateTimeOffset.UtcNow.ToUnixTimeSeconds() * 1000).ToString();
            string sql = "CREATE TABLE sessions(id TEXT,cwd TEXT,custom_title TEXT,title TEXT,status TEXT,updated_at INTEGER,last_activity_at INTEGER,model TEXT,deleted_at INTEGER);" +
                "INSERT INTO sessions VALUES('00000000-0000-0000-0000-000000000001','C:\\demo','Named task','Fallback','working'," + now + ",NULL,'model-a',NULL);" +
                "INSERT INTO sessions VALUES('00000000-0000-0000-0000-000000000002','C:\\demo',NULL,'Finished','completed'," + now + ",NULL,NULL,NULL);" +
                "INSERT INTO sessions VALUES('00000000-0000-0000-0000-000000000003','C:\\demo',NULL,'Archived','archived'," + now + ",NULL,NULL,NULL);" +
                "INSERT INTO sessions VALUES('00000000-0000-0000-0000-000000000004','C:\\demo',NULL,'Deleted','running'," + now + ",NULL,NULL,1);";
            if (sqlite3_exec(db, Encoding.UTF8.GetBytes(sql + "\0"), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) != 0) throw new Exception("fixture failed");
        } finally { sqlite3_close(db); }
    }
}
'@
    [TokcatTestDatabase]::Create((Join-Path $dbDir 'codex-dev.db'))
    $work = @(Get-WorkSessions $workRoot)
    Assert-Equal $work.Count 1 'only Work conversations included'
    Assert-Equal $work[0].State 'running' 'Work streaming status'
    Assert-Equal $work[0].Title 'Work test' 'Work title'
    Assert-Equal $work[0].Url 'https://chatgpt.com/c/00000000-0000-0000-0000-000000000001' 'Work link'
    $buddyRoot = Join-Path $root 'buddy'
    New-Item -ItemType Directory -Path $buddyRoot | Out-Null
    [TokcatTestDatabase]::CreateBuddy((Join-Path $buddyRoot 'workbuddy.db'))
    $buddy = @(Get-WorkBuddySessions $buddyRoot 'WorkBuddy AI')
    Assert-Equal $buddy.Count 2 'archived and deleted WorkBuddy sessions excluded'
    $active = @($buddy | Where-Object { $_.State -eq 'running' })
    Assert-Equal $active.Count 1 'WorkBuddy working state'
    Assert-Equal $active[0].Title 'Named task' 'WorkBuddy custom title'
    Assert-Equal $active[0].Source 'WorkBuddy AI' 'WorkBuddy source separation'
    Assert-Equal @($buddy | Where-Object { $_.State -eq 'completed' }).Count 1 'WorkBuddy completion'
    $claudeDir = Join-Path $root 'claude-state'
    $hook = Join-Path $PSScriptRoot 'ClaudeHook.ps1'
    $claudeId = '00000000-0000-0000-0000-000000000010'
    ('{"session_id":"' + $claudeId + '","hook_event_name":"UserPromptSubmit","cwd":"C:\\demo","prompt":"private sample"}') | & powershell.exe -NoProfile -File $hook -StateDirectory $claudeDir
    Assert-Equal $LASTEXITCODE 0 'Claude hook exit'
    $claude = @(Get-ClaudeSessions $claudeDir)
    Assert-Equal $claude.Count 1 'Claude session created'
    Assert-Equal $claude[0].State 'running' 'Claude prompt starts task'
    $rawClaude = [IO.File]::ReadAllText((Join-Path $claudeDir ($claudeId + '.json')))
    if ($rawClaude.Contains('private sample')) { throw 'Claude hook persisted prompt content' }
    ('{"session_id":"' + $claudeId + '","hook_event_name":"PermissionRequest","cwd":"C:\\demo"}') | & powershell.exe -NoProfile -File $hook -StateDirectory $claudeDir
    Assert-Equal @(Get-ClaudeSessions $claudeDir)[0].State 'approval' 'Claude permission request'
    ('{"session_id":"' + $claudeId + '","hook_event_name":"Stop","cwd":"C:\\demo"}') | & powershell.exe -NoProfile -File $hook -StateDirectory $claudeDir
    ('{"session_id":"' + $claudeId + '","hook_event_name":"SessionEnd","cwd":"C:\\demo"}') | & powershell.exe -NoProfile -File $hook -StateDirectory $claudeDir
    Assert-Equal @(Get-ClaudeSessions $claudeDir)[0].State 'completed' 'Claude session end preserves completion'
    ('{"session_id":"' + $claudeId + '","agent_id":"internal","hook_event_name":"UserPromptSubmit"}') | & powershell.exe -NoProfile -File $hook -StateDirectory $claudeDir
    Assert-Equal @(Get-ClaudeSessions $claudeDir)[0].State 'completed' 'Claude internal agent excluded'
    $configDir = Join-Path $root 'Claude settings with spaces'
    New-Item -ItemType Directory -Path $configDir | Out-Null
    $config = Join-Path $configDir 'settings.json'
    [IO.File]::WriteAllText($config, '{"custom":"keep","hooks":{"Stop":[{"matcher":"*","hooks":[{"type":"command","command":"other-tool"}]}]}}')
    $installer = Join-Path $PSScriptRoot 'Configure-ClaudeHooks.ps1'
    & powershell.exe -NoProfile -File $installer -SettingsPath $config | Out-Null
    Assert-Equal $LASTEXITCODE 0 'Claude hook configuration'
    & powershell.exe -NoProfile -File $installer -SettingsPath $config | Out-Null
    Assert-Equal $LASTEXITCODE 0 'Claude hook reconfiguration'
    $configured = [IO.File]::ReadAllText($config) | ConvertFrom-Json
    Assert-Equal $configured.custom 'keep' 'Claude unrelated setting preserved'
    Assert-Equal @($configured.hooks.Stop).Count 2 'Claude hook installation is idempotent'
    Assert-Equal $configured.hooks.Stop[0].hooks[0].command 'other-tool' 'unrelated hook preserved'
    Assert-Equal $configured.hooks.Stop[1].hooks[0].args[-1] $hook 'hook path passed as a separate argument'
    Assert-Equal $configured.hooks.Stop[1].hooks[0].onFailure 'continue' 'monitor failures do not block Claude'
    & powershell.exe -NoProfile -File $installer -SettingsPath $config -Remove | Out-Null
    Assert-Equal $LASTEXITCODE 0 'Claude hook removal'
    $configured = [IO.File]::ReadAllText($config) | ConvertFrom-Json
    Assert-Equal @($configured.hooks.Stop).Count 1 'Claude removal preserves other hooks'
    if (@(Get-ChildItem -LiteralPath $configDir -Filter 'settings.json.tokcat-backup-*').Count -lt 1) { throw 'Claude settings backup missing' }
    $invalidConfig = Join-Path $configDir 'invalid.json'
    $invalidContent = '{"hooks":{"Stop":"invalid"},"other":"preserve"}'
    [IO.File]::WriteAllText($invalidConfig, $invalidContent)
    $rejected = $false
    try { & $installer -SettingsPath $invalidConfig | Out-Null } catch { $rejected = $true }
    Assert-Equal $rejected $true 'invalid Claude hooks rejected'
    Assert-Equal ([IO.File]::ReadAllText($invalidConfig)) $invalidContent 'invalid settings not overwritten'
    $activityDir = Join-Path $root 'activity'
    New-Item -ItemType Directory -Path $activityDir | Out-Null
    $timestamp = [datetimeoffset]::UtcNow.ToString('o')
    $clawLog = Join-Path $activityDir 'test.trajectory.jsonl'
    [IO.File]::WriteAllText($clawLog, ('{"type":"prompt.submitted","timestamp":"' + $timestamp + '","sessionId":"claw-1","cwd":"C:\\project","prompt":"private"}' + "`n"))
    $claw = @(Get-ActivitySessions @($activityDir) 'OpenClaw')
    Assert-Equal $claw.Count 1 'OpenClaw activity found'
    Assert-Equal $claw[0].State 'unknown' 'activity does not imply a live state'
    Assert-Equal $claw[0].Phase '仅发现活动记录' 'activity-only explanation'
    $wire = Join-Path $activityDir 'wire.jsonl'
    [IO.File]::WriteAllText($wire, ('{"type":"usage.record","timestamp":"' + $timestamp + '","session_id":"kimi-1","model":"model-x"}' + "`n"))
    $kimi = @(Get-ActivitySessions @($activityDir) 'Kimi')
    Assert-Equal $kimi.Count 1 'Kimi activity found'
    Assert-Equal $kimi[0].State 'unknown' 'Kimi activity remains unknown'
    Assert-Equal $kimi[0].Model 'model-x' 'Kimi model'
    $rateSession = [pscustomobject]@{ Source='Codex'; Id='rate-test'; State='running'; OutputTokens=100; OutputScope='session'; TurnId='turn-a' }
    $rates = Get-OutputRates @($rateSession) 0
    Assert-Equal $rates.ContainsKey('Codex:rate-test') $false 'rate needs two samples'
    $rateSession.OutputTokens = 120
    $rates = Get-OutputRates @($rateSession) 10
    Assert-Equal $rates['Codex:rate-test'] 2 'observed output rate'
    $rateSession.OutputScope = 'turn'; $rateSession.OutputTokens = 150
    $rates = Get-OutputRates @($rateSession) 12
    Assert-Equal $rates.ContainsKey('Codex:rate-test') $false 'switching counter scope resets baseline'
    $rateSession.State = 'waiting'
    $rates = Get-OutputRates @($rateSession) 15
    Assert-Equal $rates['Codex:rate-test'] 0 'waiting rate'
    $rateSession.State = 'running'; $rateSession.TurnId = 'turn-b'; $rateSession.OutputTokens = 2
    $rates = Get-OutputRates @($rateSession) 20
    Assert-Equal $rates.ContainsKey('Codex:rate-test') $false 'new turn resets rate'
    $rateSession.OutputTokens = 12
    $rates = Get-OutputRates @($rateSession) 25
    Assert-Equal $rates['Codex:rate-test'] 2 'new turn rate'
    $rateSession.State = 'completed'
    $rates = Get-OutputRates @($rateSession) 30
    Assert-Equal $rates.ContainsKey('Codex:rate-test') $false 'completed rate is unavailable'
    $seen = @{}; $unread = @{}; $launch = [datetimeoffset]::UtcNow
    $finished = [pscustomobject]@{ Source='Codex'; Id='quick'; State='completed'; Updated=$launch.AddSeconds(1) }
    Assert-Equal @(Get-NewSessionAlerts @($finished) @{} $false $launch).Count 0 'historical tasks do not notify on startup'
    Assert-Equal @(Get-NewSessionAlerts @($finished) @{} $true $launch).Count 1 'fast completion notifies once'
    Update-ReminderStates @() $seen $unread $false $launch
    Update-ReminderStates @($finished) $seen $unread $true $launch
    Assert-Equal $unread.ContainsKey('Codex:quick') $true 'fast completed task gets a reminder'
    Assert-Equal @(Get-NewSessionAlerts @($finished) $seen $true $launch).Count 0 'unchanged completion does not notify again'
    $unread.Clear()
    $workCompleted = [pscustomobject]@{ Source='Codex Work'; Id='cloud'; State='completed'; Updated=$launch }
    Update-ReminderStates @($workCompleted) $seen $unread $false $launch
    $workCompleted.Updated = $launch.AddSeconds(1)
    Update-ReminderStates @($workCompleted) $seen $unread $true $launch
    Assert-Equal $unread.ContainsKey('Codex Work:cloud') $false 'catalog metadata alone does not repeat reminder'
    $workCompleted.State = 'running'
    Update-ReminderStates @($workCompleted) $seen $unread $true $launch
    $workCompleted.State = 'completed'
    Update-ReminderStates @($workCompleted) $seen $unread $true $launch
    Assert-Equal $unread.ContainsKey('Codex Work:cloud') $true 'catalog state transition produces reminder'
    $waiting = [pscustomobject]@{ Source='Codex'; Id='waiting'; State='approval'; Updated=$launch.AddSeconds(1) }
    $oldWaiting = @{ 'Codex:waiting'=@{ State='running'; Updated=$launch } }
    Assert-Equal @(Get-NewSessionAlerts @($waiting) $oldWaiting $true $launch).Count 1 'approval transition notifies'
    $preferencePath = Join-Path (Join-Path $root 'preferences') 'settings.json'
    Assert-Equal (Read-NotificationPreference $preferencePath) $false 'notifications default off'
    Write-NotificationPreference $preferencePath $true
    Assert-Equal (Read-NotificationPreference $preferencePath) $true 'notification preference saved'
    Write-NotificationPreference $preferencePath $false
    Assert-Equal (Read-NotificationPreference $preferencePath) $false 'notification preference can be disabled'
    $badPreferences = '{"version":2,"notifications":true}'
    [IO.File]::WriteAllText($preferencePath, $badPreferences)
    $badPreferenceRejected = $false
    try { Write-NotificationPreference $preferencePath $false } catch { $badPreferenceRejected = $true }
    Assert-Equal $badPreferenceRejected $true 'unsupported preferences rejected'
    Assert-Equal ([IO.File]::ReadAllText($preferencePath)) $badPreferences 'unsupported preferences preserved'
    $stripPreference = Join-Path (Join-Path $root 'preferences') 'strip.json'
    Assert-Equal (Read-StatusStripPreference $stripPreference) $true 'status strip visible by default'
    Write-StatusStripPreference $stripPreference $false
    Assert-Equal (Read-StatusStripPreference $stripPreference) $false 'status strip visibility persists'
    Write-StatusStripPreference $stripPreference $true
    Assert-Equal (Read-StatusStripPreference $stripPreference) $true 'status strip can be re-enabled'
    $badStrip = '{"version":2,"visible":false}'
    [IO.File]::WriteAllText($stripPreference, $badStrip)
    $badStripRejected = $false
    try { Write-StatusStripPreference $stripPreference $true } catch { $badStripRejected = $true }
    Assert-Equal $badStripRejected $true 'unsupported status strip settings rejected'
    Assert-Equal ([IO.File]::ReadAllText($stripPreference)) $badStrip 'unsupported status strip settings preserved'
    $reminderFile = Join-Path (Join-Path $root 'reminders') 'state.json'
    $saved = @{}
    Sync-ReminderStore @($workCompleted) $unread $saved $launch
    Write-ReminderStore $reminderFile $saved
    $loaded = Read-ReminderStore $reminderFile
    $restored = @{}; $newSeen = @{}
    Restore-Reminders @($workCompleted) $newSeen $restored $loaded
    Assert-Equal $restored.ContainsKey('Codex Work:cloud') $true 'unread survives restart'
    $changed = [pscustomobject]@{ Source='Codex Work'; Id='cloud'; State='completed'; Updated=$workCompleted.Updated.AddSeconds(1) }
    $mismatch = @{}
    Restore-Reminders @($changed) @{} $mismatch $loaded
    Assert-Equal $mismatch.ContainsKey('Codex Work:cloud') $true 'catalog metadata changes retain unread state'
    $oldCodex = [pscustomobject]@{ State='completed'; Updated=$launch }
    $changedCodex = [pscustomobject]@{ Source='Codex'; Id='changed'; State='completed'; Updated=$launch.AddSeconds(1) }
    $mismatch = @{}
    Restore-Reminders @($changedCodex) @{} $mismatch @{ 'Codex:changed'=$oldCodex }
    Assert-Equal $mismatch.Count 0 'changed Codex turn does not restore old reminder'
    Sync-ReminderStore @() @{} $saved $launch
    Assert-Equal $saved.ContainsKey('Codex Work:cloud') $true 'temporarily unavailable source preserves reminder'
    $unread.Clear()
    Sync-ReminderStore @($workCompleted) $unread $saved $launch
    Write-ReminderStore $reminderFile $saved
    Assert-Equal (Read-ReminderStore $reminderFile).Count 0 'mark read persists'
    [IO.File]::WriteAllText($reminderFile, '{"version":99,"items":[]}')
    $badStore = $false
    try { $null = Read-ReminderStore $reminderFile } catch { $badStore = $true }
    Assert-Equal $badStore $true 'unknown reminder store format rejected'
    $quotaRoot = Join-Path $root 'quota-test'
    $quotaDir = Join-Path $quotaRoot 'sessions'
    New-Item -ItemType Directory -Path $quotaDir -Force | Out-Null
    $quotaNow = [datetimeoffset]::UtcNow
    $futureReset = $quotaNow.AddHours(1).ToUnixTimeSeconds(); $expiredReset = $quotaNow.AddMinutes(-1).ToUnixTimeSeconds()
    $quotaFile = Join-Path $quotaDir 'rollout-quota.jsonl'
    $quotaRows = @(
        '{"type":"session_meta","payload":{"id":"quota","model_provider":"openai"}}',
        ('{"type":"event_msg","timestamp":"' + $quotaNow.ToString('o') + '","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":25,"window_minutes":300,"resets_at":' + $futureReset + '},"secondary":{"used_percent":30,"window_minutes":10080,"resets_at":' + $expiredReset + '}}}}'),
        ('{"type":"event_msg","timestamp":"' + $quotaNow.AddSeconds(1).ToString('o') + '","payload":{"type":"token_count","rate_limits":{"limit_id":"other","primary":{"used_percent":99,"window_minutes":300}}}}')
    )
    [IO.File]::WriteAllText($quotaFile, ($quotaRows -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $quota = Get-CodexQuota $quotaRoot
    Assert-Equal $quota.FiveHour.Remaining 75 'Codex quota remaining'
    Assert-Equal (Format-CodexQuota $quota $quotaNow) '5h 75% / 周 —' 'expired quota remains unavailable'
    Assert-Equal (Format-CodexQuota $quota $quotaNow.AddHours(2)) '5h — / 周 —' 'passed reset does not imply replenishment'
    Assert-Equal (Format-CodexQuota $null $quotaNow) '5h — / 周 —' 'missing quota is unavailable'
    $conversationFile = Join-Path $root 'conversation.jsonl'
    $conversationLines = @(
        '{"type":"session_meta","payload":{"id":"conversation"}}',
        '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"question"},{"type":"input_image","image_url":"private binary"}]}}',
        '{"type":"response_item","payload":{"type":"message","role":"system","content":"hidden system"}}',
        '{"type":"response_item","payload":{"type":"reasoning","text":"hidden reasoning"}}',
        '{"type":"response_item","payload":{"type":"function_call_output","output":"hidden tool"}}',
        '{"id":"reply","type":"response_item","payload":{"type":"message","role":"assistant","content":"first"}}',
        '{"id":"reply","type":"response_item","payload":{"type":"message","role":"assistant","content":"final"}}'
    )
    [IO.File]::WriteAllText($conversationFile, ($conversationLines -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $conversationSession = [pscustomobject]@{ Source='Codex'; Id='conversation'; Path=$conversationFile }
    $conversation = Read-AgentConversation $conversationSession $conversationFile
    Assert-Equal $conversation.Messages.Count 2 'conversation roles and deduplication'
    Assert-Equal $conversation.Messages[0].Text "question`n`n[图片]" 'attachment placeholder'
    Assert-Equal $conversation.Messages[1].Text 'final' 'latest streaming message wins'
    $shortConversation = Read-AgentConversation $conversationSession $conversationFile 1
    Assert-Equal $shortConversation.Messages.Count 1 'conversation message limit'
    Assert-Equal $shortConversation.Truncated $true 'truncation is reported'
    $wrong = [pscustomobject]@{ Source='Codex'; Id='other'; Path=$conversationFile }; $rejected = $false
    try { $null = Read-AgentConversation $wrong $conversationFile } catch { $rejected = $true }
    Assert-Equal $rejected $true 'conversation session mismatch rejected'
    $dshConversation = Join-Path $root 'dsh-conversation.json'
    [IO.File]::WriteAllText($dshConversation, '{"record":{"rows":{"turnOutline":{"val":{"turns":[{"turn":1,"prompt":"hello","response":"answer"}],"draft":"draft"}}}}}')
    $dshTask = [pscustomobject]@{ Source='DeepSeek Harness'; Id='dsh-conversation'; Path=$dshConversation }
    $outline = Read-AgentConversation $dshTask $dshConversation
    Assert-Equal $outline.Messages.Count 3 'DeepSeek turn outline and draft'
    Assert-Equal $outline.Messages[2].Text 'draft' 'DeepSeek streaming draft'
    $sourceId = '00000000-0000-0000-0000-000000000020'
    $claudeProject = Join-Path $root '.claude\projects\project-a'
    New-Item -ItemType Directory -Path $claudeProject -Force | Out-Null
    $claudeLog = Join-Path $claudeProject ($sourceId + '.jsonl')
    $claudeRows = @(
        ('{"type":"user","sessionId":"' + $sourceId + '","message":{"role":"user","content":"hello"}}'),
        '{"type":"assistant","sessionId":"other","message":{"role":"assistant","content":"wrong session"}}',
        ('{"type":"assistant","sessionId":"' + $sourceId + '","message":{"role":"assistant","content":[{"type":"thinking","thinking":"secret"},{"type":"text","text":"answer"}]}}'),
        ('{"type":"assistant","isSidechain":true,"sessionId":"' + $sourceId + '","message":{"role":"assistant","content":"internal"}}')
    )
    [IO.File]::WriteAllText($claudeLog, ($claudeRows -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $claudeTask = [pscustomobject]@{ Source='Claude Code'; Id=$sourceId; Path=$null }
    Assert-Equal (Resolve-ConversationPath $claudeTask $root) $claudeLog 'Claude transcript resolved by session ID'
    $claudeConversation = Read-AgentConversation $claudeTask $claudeLog
    Assert-Equal $claudeConversation.Messages.Count 2 'Claude session and sidechain isolation'
    Assert-Equal $claudeConversation.Messages[1].Text 'answer' 'Claude thinking excluded'
    $secondProject = Join-Path $root '.claude\projects\project-b'
    New-Item -ItemType Directory -Path $secondProject -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $secondProject ($sourceId + '.jsonl')), '')
    Assert-Equal (Resolve-ConversationPath $claudeTask $root) $null 'ambiguous transcript paths rejected'
    $buddyLog = Join-Path $root 'buddy-conversation.jsonl'
    $buddyRows = @(
        ('{"type":"message","id":"a","sessionId":"' + $sourceId + '","role":"user","content":"inspect"}'),
        '{"type":"reasoning","content":"hidden"}',
        ('{"type":"message","id":"b","sessionId":"' + $sourceId + '","role":"assistant","content":"done"}')
    )
    [IO.File]::WriteAllText($buddyLog, ($buddyRows -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $buddyTask = [pscustomobject]@{ Source='WorkBuddy'; Id=$sourceId; Path=$buddyLog }
    $buddyConversation = Read-AgentConversation $buddyTask $buddyLog
    Assert-Equal $buddyConversation.Messages.Count 2 'WorkBuddy conversation excludes non-message records'
    Assert-Equal $buddyConversation.Messages[1].Text 'done' 'WorkBuddy assistant text'
    $usageRoot = Join-Path $root 'usage-test'; $usageDir = Join-Path $usageRoot 'sessions'; $archiveDir = Join-Path $usageRoot 'archived_sessions'
    New-Item -ItemType Directory -Path $usageDir,$archiveDir -Force | Out-Null
    $usageNow = [datetimeoffset]::Now
    $row1 = '{"type":"event_msg","timestamp":"' + $usageNow.AddMinutes(-3).ToString('o') + '","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10},"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10}}}}'
    $row2 = '{"type":"event_msg","timestamp":"' + $usageNow.AddMinutes(-2).ToString('o') + '","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":160,"cached_input_tokens":50,"output_tokens":30}}}}'
    $row3 = '{"type":"event_msg","timestamp":"' + $usageNow.AddMinutes(-1).ToString('o') + '","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":170,"cached_input_tokens":50,"output_tokens":31}}}}'
    $header = '{"type":"session_meta","payload":{"id":"usage-session","model_provider":"openai"}}'
    $context = '{"type":"turn_context","payload":{"model":"gpt-5.6-sol"}}'
    [IO.File]::WriteAllText((Join-Path $usageDir 'rollout-usage.jsonl'), (@($header,$context,$row1,$row2,$row3) -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $archiveDir 'rollout-copy.jsonl'), (@($header,$context,$row1,$row2,$row3) -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $usageResult = Get-CodexUsage $usageRoot 7 (Join-Path $PSScriptRoot 'UsagePricing.json') $usageNow
    Assert-Equal $usageResult.Rows.Count 1 'usage groups duplicated rollouts once'
    Assert-Equal $usageResult.Rows[0].Input 120 'uncached input deltas'
    Assert-Equal $usageResult.Rows[0].Cache 50 'cache-read deltas'
    Assert-Equal $usageResult.Rows[0].Output 31 'output deltas'
    if ([math]::Abs($usageResult.Rows[0].EstimatedUSD - 0.00046625) -gt 0.000000001) { throw 'estimated cost is incorrect' }
    $prices = @(Get-PriceCatalog (Join-Path $PSScriptRoot 'UsagePricing.json'))
    Assert-Equal (Find-UsagePrice $prices 'gpt-5.6-sol' 'private-relay') $null 'official prices not assigned to relays'
    Assert-Equal (Find-UsagePrice $prices 'gpt-5.6-sol-custom' 'openai') $null 'unknown model variant is not priced'
    Assert-Equal (Find-UsagePrice $prices 'gpt-5.6-sol' 'anthropic') $null 'official price is not assigned to a different vendor'
    Assert-Equal (Find-UsagePrice $prices 'claude-3-5-sonnet-20241022' 'openai') $null 'Claude price is not assigned to OpenAI provider'
    $resumeRows = @(
        '{"type":"session_meta","payload":{"id":"resumed","model_provider":"private-relay"}}',
        $context,
        ('{"type":"event_msg","timestamp":"' + $usageNow.AddMinutes(-4).ToString('o') + '","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100},"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":1}}}}'),
        ('{"type":"event_msg","timestamp":"' + $usageNow.AddMinutes(-3).ToString('o') + '","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1010,"cached_input_tokens":205,"output_tokens":102}}}}'),
        ('{"type":"event_msg","timestamp":"' + $usageNow.AddMinutes(-2).ToString('o') + '","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5,"cached_input_tokens":0,"output_tokens":1},"last_token_usage":{"input_tokens":2,"cached_input_tokens":0,"output_tokens":1}}}}'),
        ('{"type":"event_msg","timestamp":"' + $usageNow.AddMinutes(-1).ToString('o') + '","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":1,"output_tokens":3}}}}')
    )
    [IO.File]::WriteAllText((Join-Path $usageDir 'rollout-resumed.jsonl'), ($resumeRows -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $usageResult = Get-CodexUsage $usageRoot 7 (Join-Path $PSScriptRoot 'UsagePricing.json') $usageNow
    $unpricedRow = @($usageResult.Rows | Where-Object { $_.Provider -eq 'private-relay' })
    Assert-Equal $unpricedRow.Count 1 'relay usage retained'
    Assert-Equal $unpricedRow[0].Input 9 'partial and reset baselines are not billed'
    Assert-Equal $unpricedRow[0].Cache 6 'cache delta after reset'
    Assert-Equal $unpricedRow[0].Output 4 'output delta after reset'
    Assert-Equal $unpricedRow[0].UnpricedTokens 19 'unpriced tokens reported separately'
    $customPrices = Join-Path $usageRoot 'custom-prices.json'
    [IO.File]::WriteAllText($customPrices, '{"version":1,"models":[{"model":"gpt-5.6-sol","provider":"private-relay","input":2,"cache_read":0.5,"output":4}]}')
    $scoped = @(Get-PriceCatalog $customPrices)
    Assert-Equal (Find-UsagePrice $scoped 'gpt-5.6-sol' 'private-relay').Output 4 'provider-scoped price matches'
    Assert-Equal (Find-UsagePrice $scoped 'gpt-5.6-sol' 'another-relay') $null 'provider-scoped price is isolated'
    [IO.File]::WriteAllText($customPrices, '{"version":1,"models":[{"model":"x","input":-1,"cache_read":0,"output":0}]}')
    $badPriceRejected = $false
    try { $null = Get-PriceCatalog $customPrices } catch { $badPriceRejected = $true }
    Assert-Equal $badPriceRejected $true 'invalid pricing is rejected'
    $priceLocal = Join-Path $root 'price-local'
    Assert-Equal (Get-UsagePricePath $PSScriptRoot $priceLocal $false) (Join-Path $PSScriptRoot 'UsagePricing.json') 'default reference prices used until edited'
    $priceOverride = Get-UsagePricePath $PSScriptRoot $priceLocal $true
    [IO.File]::WriteAllText($priceOverride, '{"version":1,"models":[]}')
    Assert-Equal (Get-UsagePricePath $PSScriptRoot $priceLocal $true) $priceOverride 'custom reference prices preserved'
    Assert-Equal ([IO.File]::ReadAllText($priceOverride)) '{"version":1,"models":[]}' 'editing does not overwrite custom prices'
    $claudeUsageFile = Join-Path $claudeProject 'claude-usage.jsonl'
    $claudeUsageRows = @(
        ('{"type":"assistant","timestamp":"' + $usageNow.AddMinutes(-3).ToString('o') + '","message":{"id":"msg-one","model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":100,"cache_read_input_tokens":80,"cache_creation_input_tokens":20,"output_tokens":50}}}'),
        ('{"type":"assistant","timestamp":"' + $usageNow.AddMinutes(-2).ToString('o') + '","message":{"id":"msg-one","model":"claude-3-5-sonnet-20241022","usage":{"output_tokens":55}}}'),
        ('{"type":"assistant","timestamp":"' + $usageNow.AddMinutes(-1).ToString('o') + '","message":{"id":"msg-two","model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":10,"output_tokens":5}}}'),
        ('{"type":"user","timestamp":"' + $usageNow.ToString('o') + '","message":{"id":"ignore","model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":999,"output_tokens":999}}}')
    )
    [IO.File]::WriteAllText($claudeUsageFile, ($claudeUsageRows -join "`n") + "`n" + '{"type":"assistant"', (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $secondProject 'claude-copy.jsonl'), ($claudeUsageRows -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $claudeUsage = Get-ClaudeUsage $root 7 (Join-Path $PSScriptRoot 'UsagePricing.json') $usageNow
    Assert-Equal $claudeUsage.Rows.Count 1 'Claude duplicate message IDs merged across files'
    Assert-Equal $claudeUsage.Rows[0].Input 110 'Claude input tokens'
    Assert-Equal $claudeUsage.Rows[0].Cache 80 'Claude cache reads'
    Assert-Equal $claudeUsage.Rows[0].CacheWrite 20 'Claude cache writes'
    Assert-Equal $claudeUsage.Rows[0].Output 60 'Claude latest streaming output'
    if ([math]::Abs($claudeUsage.Rows[0].EstimatedUSD - 0.001329) -gt 0.000000001) { throw 'Claude reference estimate is incorrect' }
    $noWritePrice = Join-Path $usageRoot 'no-write.json'
    [IO.File]::WriteAllText($noWritePrice, '{"version":1,"models":[{"model":"claude-3-5-sonnet","input":3,"cache_read":0.3,"output":15}]}')
    $claudeUnpriced = Get-ClaudeUsage $root 7 $noWritePrice $usageNow
    Assert-Equal $claudeUnpriced.Rows[0].UnpricedTokens 255 'cache writes without a price remain unpriced'
    $combined = Get-CombinedUsage $usageRoot $root 7 (Join-Path $PSScriptRoot 'UsagePricing.json') $usageNow
    Assert-Equal @($combined.Rows | Where-Object { $_.Source -eq 'Claude Code' }).Count 1 'combined usage includes Claude'
    Assert-Equal @($combined.Rows | Where-Object { $_.Source -eq 'Codex' }).Count 2 'combined usage keeps Codex provider groups'
    Add-Type -Path (Join-Path $PSScriptRoot 'SystemMetrics.cs')
    $firstMetrics = [TokcatSystemMetrics]::Sample()
    Assert-Equal $firstMetrics.CpuPercent $null 'CPU requires a baseline'
    if ($null -eq $firstMetrics.MemoryPercent -or $firstMetrics.MemoryPercent -lt 0 -or $firstMetrics.MemoryPercent -gt 100) { throw 'physical memory percentage is invalid' }
    Start-Sleep -Milliseconds 150
    $nextMetrics = [TokcatSystemMetrics]::Sample()
    if ($null -eq $nextMetrics.CpuPercent -or $nextMetrics.CpuPercent -lt 0 -or $nextMetrics.CpuPercent -gt 100) { throw 'CPU percentage is invalid' }
    if (($null -eq $nextMetrics.NetworkDown) -ne ($null -eq $nextMetrics.NetworkUp)) { throw 'Network rates must be available together' }
    if ($null -ne $nextMetrics.NetworkDown -and ($nextMetrics.NetworkDown -lt 0 -or $nextMetrics.NetworkUp -lt 0)) { throw 'Network rate is invalid' }
    $sampler = New-Object TokcatNetworkRateSampler
    $before = New-Object 'System.Collections.Generic.Dictionary[string,long[]]'
    $before.Add('one', [long[]]@(100,200))
    Assert-Equal ($sampler.Observe($before, 0)) $null 'network needs a baseline'
    $after = New-Object 'System.Collections.Generic.Dictionary[string,long[]]'
    $after.Add('one', [long[]]@(300,300)); $after.Add('new', [long[]]@(900000,900000))
    $network = $sampler.Observe($after, 10)
    Assert-Equal $network.Down 20 'new adapter does not create a download spike'
    Assert-Equal $network.Up 10 'new adapter does not create an upload spike'
    $reset = New-Object 'System.Collections.Generic.Dictionary[string,long[]]'
    $reset.Add('one', [long[]]@(10,10)); $reset.Add('new', [long[]]@(900100,900200))
    $network = $sampler.Observe($reset, 20)
    Assert-Equal $network.Down 10 'reset adapter is rebased'
    Assert-Equal $network.Up 20 'unaffected adapter remains measured'
    $previousProfile = $env:USERPROFILE; $previousAppData = $env:APPDATA; $previousLocalData = $env:LOCALAPPDATA
    try {
        [IO.File]::AppendAllText($log, "`n" + '{"type":"response_item","payload":{"type":"message","role":"user","content":"fixture conversation"}}' + "`n")
        $smokeTime = [datetimeoffset]::UtcNow.AddSeconds(-1).ToString('o')
        $smokeUsage = '{"type":"turn_context","payload":{"model":"gpt-5.6-sol"}}' + "`n" + '{"type":"event_msg","timestamp":"' + $smokeTime + '","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3},"last_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}}}}' + "`n"
        [IO.File]::AppendAllText($log, $smokeUsage)
        $env:USERPROFILE = $root; $env:APPDATA = $root; $env:LOCALAPPDATA = $root
        & powershell.exe -NoProfile -STA -File (Join-Path $PSScriptRoot 'Tokcat.ps1') -CodexHome $root -SmokeTest
        Assert-Equal $LASTEXITCODE 0 'window and notification-area initialization'
    } finally { $env:USERPROFILE = $previousProfile; $env:APPDATA = $previousAppData; $env:LOCALAPPDATA = $previousLocalData }
    Write-Host 'Windows monitor parser checks passed.'
} finally {
    if (Test-Path -LiteralPath $root) {
        $tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $resolved = (Resolve-Path -LiteralPath $root).Path
        if (-not $resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^tokcat-test-[0-9a-f-]{36}$') { throw 'Refusing to remove an unexpected test path.' }
        try { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop } catch { Write-Warning "Temporary test directory retained because a file is in use: $resolved" }
    }
}
