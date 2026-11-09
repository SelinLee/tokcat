param([string]$StateDirectory = (Join-Path $env:LOCALAPPDATA 'Tokcat\claude'))
# Claude invokes this hook for lifecycle events. Persist only the fields needed
# by the monitor; never copy prompts, tool inputs, responses or credentials.
try {
    $inputText = [Console]::In.ReadToEnd()
    if ($inputText.Length -gt 1048576) { exit 0 }
    $event = $inputText | ConvertFrom-Json -ErrorAction Stop
    if ($null -ne $event.PSObject.Properties['agent_id']) { exit 0 }
    $id = [string]$event.session_id; $guid = [guid]::Empty
    if (-not [guid]::TryParse($id, [ref]$guid)) { exit 0 }
    $kind = [string]$event.hook_event_name; $phase = ''; $state = ''
    switch ($kind) {
        'UserPromptSubmit' { $state = 'running'; $phase = '处理请求' }
        'PermissionRequest' { $state = 'approval'; $phase = '等待授权' }
        'Notification' {
            if ($event.notification_type -eq 'permission_prompt') { $state = 'approval'; $phase = '等待授权' }
            elseif ($event.notification_type -in @('idle_prompt','elicitation_dialog')) { $state = 'waiting'; $phase = '等待回答' }
        }
        'PreToolUse' { if ($event.tool_name -eq 'AskUserQuestion') { $state = 'waiting'; $phase = '等待回答' } else { $state = 'running'; $phase = '执行工具' } }
        'PostToolUse' { $state = 'running'; $phase = '处理工具结果' }
        'PostToolUseFailure' { $state = 'running'; $phase = '工具失败，等待后续处理' }
        'PermissionDenied' { $state = 'running'; $phase = '授权未通过，等待后续处理' }
        'Stop' { if (@($event.background_tasks | Where-Object { $null -ne $_ }).Count -gt 0) { $state = 'running'; $phase = '后台任务仍在运行' } else { $state = 'completed'; $phase = '本轮结束' } }
        'StopFailure' { $state = 'failed'; $phase = '本轮失败' }
        'SessionEnd' { $state = 'interrupted'; $phase = '会话结束' }
    }
    if (-not $state) { exit 0 }
    $observed = [datetimeoffset]::UtcNow
    [IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
    $mutex = New-Object Threading.Mutex($false, ('Local\TokcatClaude-' + $guid.ToString('N')))
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(3000) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { exit 0 }
        $path = Join-Path $StateDirectory ($guid.ToString() + '.json')
        $previous = $null
        if (Test-Path -LiteralPath $path) { try { $previous = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop } catch {} }
        if ($previous -and $previous.updated -and [datetimeoffset]$previous.updated -gt $observed) { exit 0 }
        if ($kind -eq 'SessionEnd' -and $previous -and $previous.state -in @('completed','failed')) { exit 0 }
        $started = if ($kind -eq 'UserPromptSubmit') { $observed.ToString('o') } elseif ($previous) { $previous.started } else { $null }
        $record = [ordered]@{ id = $guid.ToString(); state = $state; phase = $phase; project = [string]$event.cwd; updated = $observed.ToString('o'); started = $started }
        $json = $record | ConvertTo-Json -Compress
        $tmp = Join-Path $StateDirectory ('.' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($tmp, $path, [System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
    } finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
} catch { # A monitoring failure must never block a Claude session.
}
exit 0
