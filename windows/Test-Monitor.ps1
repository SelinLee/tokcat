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
}
'@
    [TokcatTestDatabase]::Create((Join-Path $dbDir 'codex-dev.db'))
    $work = @(Get-WorkSessions $workRoot)
    Assert-Equal $work.Count 1 'only Work conversations included'
    Assert-Equal $work[0].State 'running' 'Work streaming status'
    Assert-Equal $work[0].Title 'Work test' 'Work title'
    Assert-Equal $work[0].Url 'https://chatgpt.com/c/00000000-0000-0000-0000-000000000001' 'Work link'
    Write-Host 'Windows monitor parser checks passed.'
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
