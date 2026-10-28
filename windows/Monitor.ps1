Set-StrictMode -Version 2

$script:codexCache = @{}
$script:activityCache = @{}
$script:rateSamples = @{}
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
    $session = [ordered]@{ Id = $id; Source = 'Codex'; Path = $Path; Project = (Get-Field $metadata 'cwd'); Model = $null; State = 'unknown'; Phase = ''; Updated = [datetimeoffset]::MinValue; Started = $null; OutputTokens = $null; OutputScope = $null; TurnId = $null }
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
            $usageTurn = Get-Field $payload 'turn_id'
            if ($usageTurn -and $session.TurnId -and $usageTurn -ne $session.TurnId) { continue }
            $usage = Get-Field $payload 'turn_token_usage'
            $tokens = Get-Field $usage 'output_tokens'
            if ($null -ne $tokens) { $session.OutputTokens = $tokens; $session.OutputScope = 'turn'; $nativeUsage = $true }
            continue
        }
        $turn = Get-Field $payload 'turn_id'
        if ($kind -ne 'task_started' -and $turn -and $session.TurnId -and $turn -ne $session.TurnId) { continue }
        if ($type -eq 'event_msg') {
            switch ($kind) {
                'task_started' { $session.State = 'running'; $session.Phase = '处理请求'; $session.Started = $stamp; $session.TurnId = $turn; $session.OutputTokens = $null; $session.OutputScope = $null; $nativeUsage = $false; $pending.Clear(); $session.Updated = $stamp }
                'task_complete' { $session.State = 'completed'; $session.Phase = '本轮结束'; $session.Updated = $stamp }
                'task_failed' { $session.State = 'failed'; $session.Phase = '本轮失败'; $session.Updated = $stamp }
                'turn_aborted' { $session.State = 'interrupted'; $session.Phase = '已中断'; $session.Updated = $stamp }
                'token_count' { $info = Get-Field $payload 'info'; $usage = Get-Field $info 'total_token_usage'; $count = Get-Field $usage 'output_tokens'; if ($null -ne $count -and -not $nativeUsage) { $session.OutputTokens = $count; $session.OutputScope = 'session' } }
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

function Get-WorkBuddySessions([string]$BuddyHome, [string]$Source = 'WorkBuddy') {
    $database = Join-Path $BuddyHome 'workbuddy.db'
    if (-not (Test-Path -LiteralPath $database)) { return @() }
    if (-not ('TokcatWorkCatalog' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'WorkCatalog.cs') }
    $cutoff = [datetimeoffset]::UtcNow.AddDays(-7).ToUnixTimeSeconds()
    foreach ($row in [TokcatWorkCatalog]::ReadBuddy($database, $cutoff)) {
        $state = switch ($row.Status) { { $_ -in @('running','working') } { 'running' } 'completed' { 'completed' } { $_ -in @('failed','error') } { 'failed' } 'terminated' { 'interrupted' } default { 'unknown' } }
        $title = if ($row.Title) { $row.Title } elseif ($row.Project) { Split-Path $row.Project -Leaf } else { $row.Id }
        # Windows project encodings can differ; do not invent a transcript path.
        [pscustomobject]@{ Id = $row.Id; Source = $Source; Path = $null; Project = $row.Project; Model = $row.Model; State = $state; Phase = "$Source 会话状态"; Updated = [datetimeoffset]::FromUnixTimeMilliseconds([long]($row.Updated * 1000)); Started = $null; OutputTokens = $null; Title = $title }
    }
}

function Get-ClaudeSessions([string]$StateDirectory) {
    if (-not (Test-Path -LiteralPath $StateDirectory)) { return @() }
    foreach ($file in @(Get-ChildItem -LiteralPath $StateDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -gt [datetime]::UtcNow.AddDays(-7) })) {
        try {
            $item = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
            $id = Get-Field $item 'id'; $guid = [guid]::Empty; $updated = [datetimeoffset]::MinValue
            if (-not [guid]::TryParse([string]$id, [ref]$guid) -or -not [datetimeoffset]::TryParse([string](Get-Field $item 'updated'), [ref]$updated) -or $updated -lt [datetimeoffset]::UtcNow.AddDays(-7)) { continue }
            $project = Get-Field $item 'project'; $title = if ($project) { Split-Path $project -Leaf } else { $id }
            [pscustomobject]@{ Id = $id; Source = 'Claude Code'; Path = $null; Project = $project; Model = $null; State = Get-Field $item 'state'; Phase = Get-Field $item 'phase'; Updated = $updated; Started = Get-Field $item 'started'; OutputTokens = $null; Title = $title }
        } catch { continue }
    }
}

function Convert-ActivitySession([string]$Path, [string]$Source) {
    $id = $null; $project = $null; $model = $null; $latest = [datetimeoffset]::MinValue
    foreach ($line in @(Read-SharedLines $Path 262144)) {
        if (-not $line.Trim()) { continue }
        try { $row = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ((Get-Field $row 'isSidechain') -eq $true) { continue }
        $kind = Get-Field $row 'type'
        if (($Source -eq 'OpenClaw' -and $kind -notin @('prompt.submitted','model.completed')) -or ($Source -eq 'Kimi' -and $kind -ne 'usage.record')) { continue }
        $timestamp = Get-Field $row 'timestamp'
        if ($null -eq $timestamp) { $timestamp = Get-Field $row 'ts' }
        if ($null -eq $timestamp) { $timestamp = Get-Field $row 'time' }
        $date = [datetimeoffset]::MinValue
        if ($timestamp -is [ValueType] -and $timestamp -isnot [bool]) {
            try { $date = [datetimeoffset]::FromUnixTimeMilliseconds([long]$timestamp) } catch { continue }
        } elseif (-not [datetimeoffset]::TryParse([string]$timestamp, [ref]$date)) { continue }
        if ($date -lt $latest -or $date -gt [datetimeoffset]::UtcNow.AddMinutes(5)) { continue }
        $latest = $date
        $nextId = Get-Field $row 'sessionId'; if (-not $nextId) { $nextId = Get-Field $row 'session_id' }
        if ($nextId) { $id = [string]$nextId }
        $nextProject = Get-Field $row 'cwd'; if ($nextProject) { $project = [string]$nextProject }
        $nextModel = Get-Field $row 'modelId'; if (-not $nextModel) { $nextModel = Get-Field $row 'model' }
        if ($nextModel -is [string]) { $model = $nextModel }
    }
    if ($latest -eq [datetimeoffset]::MinValue -or $latest -lt [datetimeoffset]::UtcNow.AddDays(-7)) { return $null }
    if (-not $id) { $id = if ($Source -eq 'Kimi') { Split-Path $Path -Parent } else { [IO.Path]::GetFileNameWithoutExtension($Path) } }
    $title = if ($project) { Split-Path $project -Leaf } else { [IO.Path]::GetFileName((Split-Path $Path -Parent)) }
    return [pscustomobject]@{ Id = $id; Source = $Source; Path = $Path; Project = $project; Model = $model; State = 'unknown'; Phase = '仅发现活动记录'; Updated = $latest; Started = $null; OutputTokens = $null; Title = $title }
}

function Get-ActivitySessions([string[]]$Roots, [string]$Source) {
    $byId = @{}; $seenFiles = @{}
    foreach ($root in $Roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $files = @(Get-ChildItem -LiteralPath $root -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.LastWriteTimeUtc -gt [datetime]::UtcNow.AddDays(-7) -and $_.FullName -notmatch '[\\/]subagents[\\/]' -and
            (($Source -eq 'OpenClaw' -and $_.Name -like '*trajectory*.jsonl') -or ($Source -eq 'Kimi' -and $_.Name -like '*wire.jsonl'))
        } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 30)
        foreach ($file in $files) {
            try {
                $key = $Source + ':' + $file.FullName; $cached = $script:activityCache[$key]
                $seenFiles[$key] = $true
                if ($cached -and $cached.Length -eq $file.Length -and $cached.Modified -eq $file.LastWriteTimeUtc) { $item = $cached.Item }
                else { $item = Convert-ActivitySession $file.FullName $Source; $script:activityCache[$key] = @{ Length=$file.Length; Modified=$file.LastWriteTimeUtc; Item=$item } }
                if ($item -and (-not $byId.ContainsKey($item.Id) -or $item.Updated -gt $byId[$item.Id].Updated)) { $byId[$item.Id] = $item }
            } catch { continue }
        }
    }
    foreach ($key in @($script:activityCache.Keys)) { if ($key.StartsWith($Source + ':') -and -not $seenFiles.ContainsKey($key)) { $script:activityCache.Remove($key) } }
    return @($byId.Values)
}

# Samples are observations of agent-reported output counters, not decoding speed.
# NowSeconds must be monotonic and is injectable so rollover/idle can be tested.
function Get-OutputRates([object[]]$Sessions, [double]$NowSeconds) {
    $rates = @{}; $seen = @{}
    foreach ($session in $Sessions) {
        $key = $session.Source + ':' + $session.Id; $seen[$key] = $true
        if ($session.State -in @('completed','failed','interrupted','unknown')) { $script:rateSamples.Remove($key); continue }
        $tokens = Get-Field $session 'OutputTokens'
        if ($null -eq $tokens -or $tokens -isnot [ValueType] -or $tokens -is [bool]) { $script:rateSamples.Remove($key); continue }
        try { $numeric = [double]$tokens } catch { $script:rateSamples.Remove($key); continue }
        if ([double]::IsNaN($numeric) -or [double]::IsInfinity($numeric) -or $numeric -lt 0) { $script:rateSamples.Remove($key); continue }
        $turn = Get-Field $session 'TurnId'; $start = Get-Field $session 'Started'
        $counterScope = Get-Field $session 'OutputScope'
        $scope = [string]$counterScope + ':' + $(if ($turn) { [string]$turn } elseif ($start) { [string]$start } else { '' })
        $entry = $script:rateSamples[$key]
        if ($null -eq $entry -or $entry.Scope -ne $scope -or [double]$tokens -lt $entry.Last -or $NowSeconds -lt $entry.LastTime) {
            $entry = @{ Scope=$scope; Last=[double]$tokens; LastTime=$NowSeconds; Samples=(New-Object 'System.Collections.Generic.List[object]') }
            $entry.Samples.Add([pscustomobject]@{ Time=$NowSeconds; Value=[double]$tokens })
            $script:rateSamples[$key] = $entry
            continue
        }
        $entry.Last = [double]$tokens; $entry.LastTime = $NowSeconds
        $entry.Samples.Add([pscustomobject]@{ Time=$NowSeconds; Value=[double]$tokens })
        while ($entry.Samples.Count -gt 1 -and $entry.Samples[1].Time -le $NowSeconds - 60) { $entry.Samples.RemoveAt(0) }
        $first = $entry.Samples[0]; $duration = $NowSeconds - $first.Time
        if ($duration -gt 0) {
            $rates[$key] = if ($session.State -in @('waiting','approval')) { 0.0 } else { [math]::Max(0, ([double]$tokens - $first.Value) / $duration) }
        }
    }
    foreach ($key in @($script:rateSamples.Keys)) { if (-not $seen.ContainsKey($key)) { $script:rateSamples.Remove($key) } }
    return $rates
}
