$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Monitor.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('tokcat-test-' + [guid]::NewGuid())
$sessions = Join-Path $root 'sessions'
New-Item -ItemType Directory -Path $sessions | Out-Null
function Assert-Equal($actual, $expected, $label) { if ($actual -ne $expected) { throw "$label : expected '$expected', got '$actual'" } }
try {
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
    Add-Type -Path (Join-Path $PSScriptRoot 'SystemMetrics.cs')
    $firstMetrics = [TokcatSystemMetrics]::Sample()
    Assert-Equal $firstMetrics.CpuPercent $null 'CPU requires a baseline'
    if ($null -eq $firstMetrics.MemoryPercent -or $firstMetrics.MemoryPercent -lt 0 -or $firstMetrics.MemoryPercent -gt 100) { throw 'physical memory percentage is invalid' }
    Start-Sleep -Milliseconds 150
    $nextMetrics = [TokcatSystemMetrics]::Sample()
    if ($null -eq $nextMetrics.CpuPercent -or $nextMetrics.CpuPercent -lt 0 -or $nextMetrics.CpuPercent -gt 100) { throw 'CPU percentage is invalid' }
    $previousProfile = $env:USERPROFILE; $previousAppData = $env:APPDATA; $previousLocalData = $env:LOCALAPPDATA
    try {
        $env:USERPROFILE = $root; $env:APPDATA = $root; $env:LOCALAPPDATA = $root
        & powershell.exe -NoProfile -STA -File (Join-Path $PSScriptRoot 'Tokcat.ps1') -CodexHome $root -SmokeTest
        Assert-Equal $LASTEXITCODE 0 'window and notification-area initialization'
    } finally { $env:USERPROFILE = $previousProfile; $env:APPDATA = $previousAppData; $env:LOCALAPPDATA = $previousLocalData }
    Write-Host 'Windows monitor parser checks passed.'
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
