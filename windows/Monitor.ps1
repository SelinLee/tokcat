Set-StrictMode -Version 2

$script:codexCache = @{}
function Get-Field($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -ne $p) { return $p.Value }
    return $null
}

function Read-SharedLines([string]$Path, [int]$MaxBytes = 524288, [bool]$Tail = $true) {
    $stream = $null; $reader = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        $start = if ($Tail) { [Math]::Max(0, $stream.Length - $MaxBytes) } else { 0 }
        $stream.Seek($start, [IO.SeekOrigin]::Begin) | Out-Null
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
        if ($start -gt 0) { $null = $reader.ReadLine() }
        if (-not $Tail) { return @($reader.ReadLine()) }
        # Ignore an incomplete final record while another process is writing it.
        $content = $reader.ReadToEnd()
        $last = $content.LastIndexOf("`n")
        if ($last -lt 0) { return @() }
        return @($content.Substring(0, $last) -split "`n")
    } finally {
        if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() }
    }
}

function Convert-CodexSession([string]$Path) {
    $first = @(Read-SharedLines $Path 1048576 $false)
    if ($first.Count -eq 0 -or -not $first[0]) { return $null }
    try { $meta = $first[0] | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    $metadata = Get-Field $meta 'payload'
    if ((Get-Field $meta 'type') -ne 'session_meta') { return $null }
    $source = Get-Field $metadata 'source'
    if ((Get-Field $metadata 'thread_source') -in @('subagent','guardian_review') -or $null -ne (Get-Field $source 'subagent')) { return $null }
    $id = Get-Field $metadata 'id'
    if (-not $id) { $id = Get-Field $metadata 'session_id' }
    if (-not $id) { $id = [IO.Path]::GetFileNameWithoutExtension($Path) }
    $session = [ordered]@{ Id = $id; Source = 'Codex'; Path = $Path; Project = (Get-Field $metadata 'cwd'); Model = $null; State = 'unknown'; Phase = ''; Updated = [datetimeoffset]::MinValue; Started = $null; OutputTokens = $null; TurnId = $null }
    $pending = @{}; $nativeUsage = $false
    foreach ($line in @(Read-SharedLines $Path)) {
        if (-not $line.Trim()) { continue }
        try { $record = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $payload = Get-Field $record 'payload'; $type = Get-Field $record 'type'; $kind = Get-Field $payload 'type'
        $stamp = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse([string](Get-Field $record 'timestamp'), [ref]$stamp)) { continue }
        if ($type -eq 'turn_context') {
            if (Get-Field $payload 'cwd') { $session.Project = Get-Field $payload 'cwd' }
            if (Get-Field $payload 'model') { $session.Model = Get-Field $payload 'model' }
            continue
        }
        if ($type -eq 'token_usage_record') {
            $usage = Get-Field $payload 'turn_token_usage'
            $tokens = Get-Field $usage 'output_tokens'
            if ($null -ne $tokens) { $session.OutputTokens = $tokens; $nativeUsage = $true }
            continue
        }
        $turn = Get-Field $payload 'turn_id'
        if ($kind -ne 'task_started' -and $turn -and $session.TurnId -and $turn -ne $session.TurnId) { continue }
        if ($type -eq 'event_msg') {
            switch ($kind) {
                'task_started' { $session.State = 'running'; $session.Phase = '处理请求'; $session.Started = $stamp; $session.TurnId = $turn; $session.OutputTokens = $null; $nativeUsage = $false; $pending.Clear(); $session.Updated = $stamp }
                'task_complete' { $session.State = 'completed'; $session.Phase = '本轮结束'; $session.Updated = $stamp }
                'task_failed' { $session.State = 'failed'; $session.Phase = '本轮失败'; $session.Updated = $stamp }
                'turn_aborted' { $session.State = 'interrupted'; $session.Phase = '已中断'; $session.Updated = $stamp }
                'token_count' { $info = Get-Field $payload 'info'; $usage = Get-Field $info 'total_token_usage'; $count = Get-Field $usage 'output_tokens'; if ($null -ne $count -and -not $nativeUsage) { $session.OutputTokens = $count } }
            }
        } elseif ($type -eq 'response_item' -and $session.State -in @('running','waiting')) {
            if ($kind -in @('function_call','custom_tool_call')) {
                $name = [string](Get-Field $payload 'name')
                if ($name.EndsWith('request_user_input')) { $session.State = 'waiting'; $session.Phase = '等待回答'; $call = Get-Field $payload 'call_id'; if ($call) { $pending[$call] = $true } }
                elseif ($session.State -eq 'running') { $session.Phase = '调用工具 · ' + $name }
                $session.Updated = $stamp
            } elseif ($kind -in @('function_call_output','custom_tool_call_output')) {
                $call = Get-Field $payload 'call_id'
                if ($pending.Count -eq 0 -or ($call -and $pending.ContainsKey($call))) {
                    if ($call) { $pending.Remove($call) }
                    if ($pending.Count -eq 0) { $session.State = 'running'; $session.Phase = '处理工具结果' }
                    $session.Updated = $stamp
                }
            } elseif ($kind -eq 'reasoning' -or ($kind -eq 'message' -and (Get-Field $payload 'role') -eq 'assistant')) {
                if ($session.State -eq 'running') { $session.Phase = if ($kind -eq 'reasoning') { '思考中' } else { '生成回复' }; $session.Updated = $stamp }
            }
        }
    }
    if ($session.State -eq 'unknown') { $session.Updated = [datetimeoffset]([IO.File]::GetLastWriteTimeUtc($Path)); $session.Phase = '近期日志中没有状态事件' }
    return [pscustomobject]$session
}

function Get-CodexSessions([string]$CodexHome) {
    $root = Join-Path $CodexHome 'sessions'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $titles = @{}; $index = Join-Path $CodexHome 'session_index.jsonl'
    if (Test-Path -LiteralPath $index) {
        try { foreach ($line in @(Read-SharedLines $index 2097152)) { try { $item = $line | ConvertFrom-Json -ErrorAction Stop; $id = Get-Field $item 'id'; if ($id) { $titles[$id] = Get-Field $item 'thread_name' } } catch {} } } catch {}
    }
    $byId = @{}; $seenFiles = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter 'rollout-*.jsonl' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -gt [datetime]::UtcNow.AddDays(-7) })) {
        try {
            $seenFiles[$file.FullName] = $true
            $cached = $script:codexCache[$file.FullName]
            if ($cached -and $cached.Length -eq $file.Length -and $cached.Modified -eq $file.LastWriteTimeUtc) { $item = $cached.Item }
            else { $item = Convert-CodexSession $file.FullName; $script:codexCache[$file.FullName] = @{ Length = $file.Length; Modified = $file.LastWriteTimeUtc; Item = $item } }
            if ($null -ne $item -and (-not $byId.ContainsKey($item.Id) -or $item.Updated -gt $byId[$item.Id].Updated)) { $byId[$item.Id] = $item }
        } catch { continue }
    }
    foreach ($path in @($script:codexCache.Keys)) { if (-not $seenFiles.ContainsKey($path)) { $script:codexCache.Remove($path) } }
    foreach ($item in $byId.Values) {
        $title = $titles[$item.Id]
        if (-not $title) { $title = if ($item.Project) { Split-Path $item.Project -Leaf } else { $item.Id } }
        $item | Add-Member -NotePropertyName Title -NotePropertyValue $title -Force
    }
    return @($byId.Values | Sort-Object Updated -Descending)
}

function Get-ProjectionValue($Rows, [string]$Name) {
    return Get-Field (Get-Field $Rows $Name) 'val'
}

function Convert-DshSession([string]$Path) {
    try { $root = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    $record = Get-Field $root 'record'; $identity = Get-Field $record 'identity'; $rows = Get-Field $record 'rows'
    if ($null -eq $identity -or $null -eq $rows) { return $null }
    if (Get-Field (Get-ProjectionValue $rows 'subagent') 'identity') { return $null }
    $stats = Get-ProjectionValue $rows 'sessionStats'
    $questions = Get-Field (Get-ProjectionValue $rows 'userQuestions') 'questions'
    $asking = @((Get-Field $questions 'active') | Where-Object { $null -ne $_ -and (Get-Field $_ 'state') -ne 'continued' }).Count -gt 0
    $pending = Get-Field $stats 'pendingCalls'
    $boundary = Get-Field (Get-Field (Get-ProjectionValue $rows 'turnBoundary') 'lastStepBoundary') 'kind'
    $state = if ($asking) { 'waiting' } elseif ($null -ne (Get-Field $stats 'openStep') -or ($pending -and @($pending.PSObject.Properties).Count -gt 0) -or $boundary -eq 'start') { 'running' } elseif ($boundary -eq 'end') { 'completed' } else { 'unknown' }
    $model = Get-Field (Get-Field (Get-ProjectionValue $rows 'modelSelection') 'lastUsed') 'model'
    $output = Get-Field (Get-Field (Get-ProjectionValue $rows 'tokenUsage') 'totals') 'outputTokens'
    $title = Get-ProjectionValue $rows 'title'; $project = Get-Field $identity 'cwd'
    if (-not $title) { $title = if ($project) { Split-Path $project -Leaf } else { [IO.Path]::GetFileNameWithoutExtension($Path) } }
    return [pscustomobject]@{ Id = [IO.Path]::GetFileNameWithoutExtension($Path); Source = 'DeepSeek Harness'; Path = $Path; Project = $project; Model = $model; State = $state; Phase = if ($state -eq 'running') { '运行中' } elseif ($state -eq 'waiting') { '等待回答' } else { '' }; Updated = [datetimeoffset]([IO.File]::GetLastWriteTimeUtc($Path)); Started = $null; OutputTokens = $output; Title = $title }
}

function Get-DshSessions([string[]]$Homes) {
    $seen = @{}
    foreach ($dshRoot in $Homes) {
        if (-not $dshRoot) { continue }
        $directory = Join-Path $dshRoot 'storages\session_projcache\sessions'
        if (-not (Test-Path -LiteralPath $directory)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -gt [datetime]::UtcNow.AddDays(-7) })) {
            $item = Convert-DshSession $file.FullName
            if ($item -and (-not $seen.ContainsKey($item.Id) -or $item.Updated -gt $seen[$item.Id].Updated)) { $seen[$item.Id] = $item }
        }
    }
    return @($seen.Values)
}

function Get-WorkSessions([string]$CodexHome) {
    $database = Join-Path $CodexHome 'sqlite\codex-dev.db'
    if (-not (Test-Path -LiteralPath $database)) { return @() }
    if (-not ('TokcatWorkCatalog' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'WorkCatalog.cs') }
    $cutoff = [datetimeoffset]::UtcNow.AddDays(-7).ToUnixTimeSeconds()
    foreach ($row in [TokcatWorkCatalog]::Read($database, $cutoff)) {
        $state = switch ($row.Status) { 3 {'running'} 6 {'running'} 7 {'running'} 4 {'completed'} default {'unknown'} }
        [pscustomobject]@{ Id = $row.Host + ':' + $row.Id; Source = 'Codex Work'; Path = $null; Project = $null; Model = $null; State = $state; Phase = if ($state -eq 'unknown') { '客户端未提供当前状态' } else { 'Work' }; Updated = [datetimeoffset]::FromUnixTimeSeconds([long]$row.Updated); Started = $null; OutputTokens = $null; Title = if ($row.Title) { $row.Title } else { $row.Id }; Url = 'https://chatgpt.com/c/' + $row.Id }
    }
}
