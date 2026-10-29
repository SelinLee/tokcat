Set-StrictMode -Version 2

$script:codexCache = @{}
$script:activityCache = @{}
$script:rateSamples = @{}
$script:quotaCache = @{}
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

function Convert-CodexSession([string]$Path, [bool]$FullScan = $false) {
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
    if ($FullScan) {
        if (-not ('TokcatCodexLogReader' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'CodexLogReader.cs') }
        $lines = [TokcatCodexLogReader]::Read($Path)
    } else { $lines = @(Read-SharedLines $Path) }
    foreach ($line in $lines) {
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
        if ($stamp -lt $session.Updated) { continue }
        if ($type -eq 'token_usage_record') {
            $usageTurn = Get-Field $payload 'turn_id'
            if ($usageTurn -and $session.TurnId -and $usageTurn -ne $session.TurnId) { continue }
            $usage = Get-Field $payload 'turn_token_usage'
            $tokens = Get-Field $usage 'output_tokens'
            if ($null -ne $tokens) {
                if ($session.State -eq 'running' -and ($session.OutputScope -ne 'turn' -or $null -eq $session.OutputTokens -or $tokens -gt $session.OutputTokens)) { $session.Updated = $stamp }
                $session.OutputTokens = $tokens; $session.OutputScope = 'turn'; $nativeUsage = $true
            }
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
                'token_count' { $info = Get-Field $payload 'info'; $usage = Get-Field $info 'total_token_usage'; $count = Get-Field $usage 'output_tokens'; if ($null -ne $count -and -not $nativeUsage) { if ($session.State -eq 'running' -and ($session.OutputScope -ne 'session' -or $null -eq $session.OutputTokens -or $count -gt $session.OutputTokens)) { $session.Updated = $stamp }; $session.OutputTokens = $count; $session.OutputScope = 'session' } }
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
    if ($session.State -eq 'unknown' -and -not $FullScan -and (Get-Item -LiteralPath $Path).Length -gt 524288) { return Convert-CodexSession $Path $true }
    if ($session.State -eq 'unknown') { $session.Updated = [datetimeoffset]([IO.File]::GetLastWriteTimeUtc($Path)); $session.Phase = '日志中没有可读取的状态事件' }
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

function New-AgentSnapshotReader([string]$Directory) {
    $runspace = [runspacefactory]::CreateRunspace(); $runspace.Open(); $worker = [PowerShell]::Create(); $worker.Runspace = $runspace
    try {
        [void]$worker.AddScript({ param($directory) . (Join-Path $directory 'Monitor.ps1') }.ToString()).AddArgument($Directory)
        $null = $worker.Invoke(); if ($worker.HadErrors) { throw 'Unable to initialize agent reader.' }
        $worker.Commands.Clear()
        return [pscustomobject]@{ Worker=$worker; Runspace=$runspace; Handle=$null }
    } catch { $worker.Dispose(); $runspace.Dispose(); throw }
}

function Request-AgentSnapshot($Reader, [string]$CodexHome, [string]$ProfileDirectory, [string]$AppDataDirectory, [string]$LocalDirectory) {
    if ($Reader.Handle) { return $false }
    $Reader.Worker.Commands.Clear(); $Reader.Worker.Streams.Error.Clear()
    [void]$Reader.Worker.AddCommand('Get-AgentSnapshot').AddParameter('CodexHome',$CodexHome).AddParameter('ProfileDirectory',$ProfileDirectory).AddParameter('AppDataDirectory',$AppDataDirectory).AddParameter('LocalDirectory',$LocalDirectory)
    $Reader.Handle = $Reader.Worker.BeginInvoke()
    return $true
}

function Receive-AgentSnapshot($Reader) {
    if (-not $Reader.Handle -or -not $Reader.Handle.IsCompleted) { return $null }
    try {
        $result = @($Reader.Worker.EndInvoke($Reader.Handle))
        if ($Reader.Worker.HadErrors -or $result.Count -ne 1) { throw 'Agent background read failed.' }
        return $result[0]
    } finally { $Reader.Handle = $null }
}

function Close-AgentSnapshotReader($Reader) {
    if (-not $Reader) { return }
    try { if ($Reader.Handle -and -not $Reader.Handle.IsCompleted) { $Reader.Worker.Stop() } } finally { $Reader.Worker.Dispose(); $Reader.Runspace.Dispose() }
}

function Get-AgentSnapshot([string]$CodexHome, [string]$ProfileDirectory, [string]$AppDataDirectory, [string]$LocalDirectory) {
    $dshHomes = @((Join-Path $ProfileDirectory '.dsh'), $env:DSH_HOME)
    if ($AppDataDirectory) { $dshHomes += @((Join-Path $AppDataDirectory 'DSH Desktop\.dsh'), (Join-Path $AppDataDirectory 'dsh-desktop\.dsh'), (Join-Path $AppDataDirectory '@deepseek-ai\dsh-desktop\.dsh')) }
    $workError = $false; $buddyError = $false
    try { $workSessions = @(Get-WorkSessions $CodexHome) } catch { $workSessions = @(); $workError = $true }
    try { $buddySessions = @(Get-WorkBuddySessions (Join-Path $ProfileDirectory '.workbuddy') 'WorkBuddy') } catch { $buddySessions = @(); $buddyError = $true }
    try { $buddySessions += @(Get-WorkBuddySessions (Join-Path $ProfileDirectory '.workbuddy-ai') 'WorkBuddy AI') } catch { $buddyError = $true }
    $claudeSessions = @(Get-ClaudeSessions (Join-Path $LocalDirectory 'Tokcat\claude'))
    $kimiRoots = @((Join-Path $ProfileDirectory '.kimi-work'), (Join-Path $ProfileDirectory '.kimi-webbridge'))
    if ($AppDataDirectory) { $kimiRoots += @((Join-Path $AppDataDirectory 'kimi-desktop'), (Join-Path $AppDataDirectory 'kimi')) }
    $activity = @(Get-ActivitySessions @((Join-Path $ProfileDirectory '.openclaw\agents')) 'OpenClaw') + @(Get-ActivitySessions $kimiRoots 'Kimi')
    $dshSessions = @(Get-DshSessions $dshHomes)
    $sessions = @(@(Get-CodexSessions $CodexHome) + $dshSessions + $workSessions + $buddySessions + $claudeSessions + $activity | Sort-Object Updated -Descending)
    $workAvailable=-not $workError -and (Test-Path -LiteralPath (Join-Path $CodexHome 'sqlite\codex-dev.db'))
    return [pscustomobject]@{ Sessions=$sessions; DshSessions=$dshSessions; Quota=(Get-CodexQuota $CodexHome); WorkError=$workError; WorkAvailable=$workAvailable; BuddyError=$buddyError }
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
    $selection = Get-Field (Get-ProjectionValue $rows 'modelSelection') 'lastUsed'
    $model = Get-Field $selection 'model'; $provider = Get-Field $selection 'provider'
    $usage = Get-Field (Get-ProjectionValue $rows 'tokenUsage') 'totals'; $output = Get-Field $usage 'outputTokens'
    $title = Get-ProjectionValue $rows 'title'; $project = Get-Field $identity 'cwd'
    if (-not $title) { $title = if ($project) { Split-Path $project -Leaf } else { [IO.Path]::GetFileNameWithoutExtension($Path) } }
    return [pscustomobject]@{ Id = [IO.Path]::GetFileNameWithoutExtension($Path); Source = 'DeepSeek Harness'; Path = $Path; Project = $project; Model = $model; Provider = $provider; Usage = $usage; State = $state; Phase = if ($state -eq 'running') { '运行中' } elseif ($state -eq 'waiting') { '等待回答' } else { '' }; Updated = [datetimeoffset]([IO.File]::GetLastWriteTimeUtc($Path)); Started = $null; OutputTokens = $output; Title = $title }
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

function Update-ReminderStates([object[]]$Sessions, [hashtable]$Seen, [hashtable]$Unread, [bool]$Bootstrapped, [datetimeoffset]$LaunchedAt) {
    $present = @{}
    foreach ($session in $Sessions) {
        $key = $session.Source + ':' + $session.Id
        $present[$key] = $true; $old = $Seen[$key]
        if ($session.State -in @('running','waiting','approval')) { $Unread.Remove($key) }
        elseif ($Bootstrapped -and $session.State -in @('completed','failed','interrupted')) {
            $newSession = $null -eq $old -and $session.Updated -ge $LaunchedAt
            $changedState = $null -ne $old -and $old.State -ne $session.State
            # Codex and Claude report turn-ending events; catalog timestamps for
            # Work, WorkBuddy and DSH can change for unrelated metadata edits.
            $newTurnEnd = $null -ne $old -and $session.Source -in @('Codex','Claude Code') -and $old.State -eq $session.State -and $session.Updated -gt $old.Updated
            if ($newSession -or $changedState -or $newTurnEnd) { $Unread[$key] = $true }
        }
        $Seen[$key] = @{ State=$session.State; Updated=$session.Updated }
    }
    foreach ($key in @($Seen.Keys)) { if (-not $present.ContainsKey($key)) { $Seen.Remove($key); $Unread.Remove($key) } }
}

function Get-NewSessionAlerts([object[]]$Sessions, [hashtable]$Seen, [bool]$Bootstrapped, [datetimeoffset]$LaunchedAt) {
    if (-not $Bootstrapped) { return @() }
    foreach ($session in $Sessions) {
        if ($session.State -notin @('waiting','approval','completed','failed')) { continue }
        $key = $session.Source + ':' + $session.Id; $old = $Seen[$key]
        $newSession = $null -eq $old -and $session.Updated -ge $LaunchedAt
        $changedState = $null -ne $old -and $old.State -ne $session.State
        $newTurnEnd = $null -ne $old -and $session.State -in @('completed','failed') -and $session.Source -in @('Codex','Claude Code') -and $old.State -eq $session.State -and $session.Updated -gt $old.Updated
        if ($newSession -or $changedState -or $newTurnEnd) { $session }
    }
}

function Read-NotificationPreference([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return $false }
    $doc = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    $enabled = Get-Field $doc 'notifications'
    if ((Get-Field $doc 'version') -ne 1 -or $enabled -isnot [bool]) { throw 'Notification settings have an unsupported format.' }
    return $enabled
}

function Write-NotificationPreference([string]$Path, [bool]$Enabled) {
    # Refuse to overwrite malformed or newer settings.
    if ([IO.File]::Exists($Path)) { $null = Read-NotificationPreference $Path }
    $directory = [IO.Path]::GetDirectoryName($Path); [IO.Directory]::CreateDirectory($directory) | Out-Null
    $json = [pscustomobject]@{ version=1; notifications=$Enabled } | ConvertTo-Json -Depth 3
    $tmp = Join-Path $directory ('.preferences-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, [System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($tmp, $Path) }
}

function Read-StatusStripPreference([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return $true }
    $doc = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    $visible = Get-Field $doc 'visible'
    if ((Get-Field $doc 'version') -ne 1 -or $visible -isnot [bool]) { throw 'Status strip settings have an unsupported format.' }
    return $visible
}

function Write-StatusStripPreference([string]$Path, [bool]$Visible) {
    if ([IO.File]::Exists($Path)) { $null = Read-StatusStripPreference $Path }
    $directory = [IO.Path]::GetDirectoryName($Path); [IO.Directory]::CreateDirectory($directory) | Out-Null
    $json = [pscustomobject]@{ version=1; visible=$Visible } | ConvertTo-Json -Depth 3
    $tmp = Join-Path $directory ('.strip-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, [System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($tmp, $Path) }
}

function Format-TaskbarNetworkRate($BytesPerSecond) {
    if ($null -eq $BytesPerSecond) { return '—' }
    $divisor=1024; $unit='K/s'
    if ($BytesPerSecond -ge 1073741824) { $divisor=1073741824; $unit='G/s' }
    elseif ($BytesPerSecond -ge 1048576) { $divisor=1048576; $unit='M/s' }
    $value=$BytesPerSecond/$divisor
    if ($value -ge 100) { return ('{0:0} {1}' -f $value,$unit) }
    return ('{0:0.#} {1}' -f $value,$unit)
}

function Read-TaskbarMetricsPreference([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return [pscustomobject]@{ Cpu=$false; Gpu=$false; Memory=$false } }
    $doc = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    if ((Get-Field $doc 'version') -ne 1) { throw 'Taskbar metric settings have an unsupported format.' }
    foreach ($name in @('Cpu','Gpu','Memory')) { if ((Get-Field $doc $name) -isnot [bool]) { throw 'Taskbar metric settings must be boolean.' } }
    return [pscustomobject]@{ Cpu=$doc.Cpu; Gpu=$doc.Gpu; Memory=$doc.Memory }
}

function Write-TaskbarMetricsPreference([string]$Path, [bool]$Cpu, [bool]$Gpu, [bool]$Memory) {
    $directory = [IO.Path]::GetDirectoryName($Path); [IO.Directory]::CreateDirectory($directory) | Out-Null
    $json = [pscustomobject]@{ version=1; Cpu=$Cpu; Gpu=$Gpu; Memory=$Memory } | ConvertTo-Json
    $tmp = Join-Path $directory ('.metrics-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, [System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($tmp, $Path) }
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}

function Convert-QuotaNumber($Value) {
    if ($null -eq $Value -or $Value -is [bool]) { return $null }
    $number = 0.0
    if ($Value -is [ValueType]) { try { $number = [double]$Value } catch { return $null } }
    elseif (-not [double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $null }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return $null }
    return $number
}

function Convert-CodexQuotaEvent($Record) {
    $payload = Get-Field $Record 'payload'
    if ((Get-Field $Record 'type') -ne 'event_msg' -or (Get-Field $payload 'type') -ne 'token_count') { return $null }
    $limits = Get-Field $payload 'rate_limits'; $limitId = Get-Field $limits 'limit_id'
    if ($null -eq $limits -or ($limitId -and $limitId -ne 'codex')) { return $null }
    $time = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string](Get-Field $Record 'timestamp'), [ref]$time) -or $time -gt [datetimeoffset]::UtcNow.AddMinutes(5)) { return $null }
    $short = $null; $week = $null
    foreach ($name in @('primary','secondary')) {
        $window = Get-Field $limits $name
        $used = Convert-QuotaNumber (Get-Field $window 'used_percent')
        $minutes = Convert-QuotaNumber (Get-Field $window 'window_minutes')
        if ($null -eq $used -or $null -eq $minutes -or $minutes -le 0 -or $minutes -gt 525600) { continue }
        $reset = Convert-QuotaNumber (Get-Field $window 'resets_at'); $resetAt = $null
        if ($null -ne $reset -and $reset -ge 0 -and $reset -le 253402300799) { $resetAt = [datetimeoffset]::FromUnixTimeSeconds([long]$reset) }
        $item = [pscustomobject]@{ Remaining = 100 - [math]::Round([math]::Min(100, [math]::Max(0, $used)), 0, [MidpointRounding]::AwayFromZero); ResetAt = $resetAt }
        if ($minutes -le 2880) { $short = $item } else { $week = $item }
    }
    if ($null -eq $short -and $null -eq $week) { return $null }
    return [pscustomobject]@{ ObservedAt=$time; FiveHour=$short; Weekly=$week }
}

function Get-CodexQuota([string]$CodexHome) {
    $latest = $null; $seen = @{}
    foreach ($folder in @('sessions','archived_sessions')) {
        $directory = Join-Path $CodexHome $folder
        if (-not (Test-Path -LiteralPath $directory)) { continue }
        $files = @(Get-ChildItem -LiteralPath $directory -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -gt [datetime]::UtcNow.AddDays(-7) } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 20)
        foreach ($file in $files) {
            try {
                $seen[$file.FullName] = $true; $cached = $script:quotaCache[$file.FullName]
                if ($cached -and $cached.Length -eq $file.Length -and $cached.Modified -eq $file.LastWriteTimeUtc) { $snapshot = $cached.Snapshot }
                else {
                    $snapshot = $null; $first = @(Read-SharedLines $file.FullName 1048576 $false)
                    $meta = $first[0] | ConvertFrom-Json -ErrorAction Stop
                    $provider = Get-Field (Get-Field $meta 'payload') 'model_provider'
                    if (-not $provider -or $provider -eq 'openai') {
                        foreach ($line in @(Read-SharedLines $file.FullName)) {
                            if (-not $line.Contains('"rate_limits"')) { continue }
                            try { $record = $line | ConvertFrom-Json -ErrorAction Stop; $candidate = Convert-CodexQuotaEvent $record } catch { continue }
                            if ($candidate -and ($null -eq $snapshot -or $candidate.ObservedAt -gt $snapshot.ObservedAt)) { $snapshot = $candidate }
                        }
                    }
                    $script:quotaCache[$file.FullName] = @{ Length=$file.Length; Modified=$file.LastWriteTimeUtc; Snapshot=$snapshot }
                }
                if ($snapshot -and ($null -eq $latest -or $snapshot.ObservedAt -gt $latest.ObservedAt)) { $latest = $snapshot }
            } catch { continue }
        }
    }
    foreach ($key in @($script:quotaCache.Keys)) { if (-not $seen.ContainsKey($key)) { $script:quotaCache.Remove($key) } }
    return $latest
}

function Format-CodexQuota($Snapshot, [datetimeoffset]$Now) {
    $short = '—'; $week = '—'
    if ($Snapshot) {
        if ($Snapshot.FiveHour -and ($null -eq $Snapshot.FiveHour.ResetAt -or $Snapshot.FiveHour.ResetAt -gt $Now)) { $short = "$($Snapshot.FiveHour.Remaining)%" }
        if ($Snapshot.Weekly -and ($null -eq $Snapshot.Weekly.ResetAt -or $Snapshot.Weekly.ResetAt -gt $Now)) { $week = "$($Snapshot.Weekly.Remaining)%" }
    }
    return "5h $short / 周 $week"
}

# Persist only reminder identifiers and state revisions, never conversation text.
function Read-ReminderStore([string]$Path) {
    $saved = @{}
    if (-not [IO.File]::Exists($Path)) { return $saved }
    $doc = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    $itemsProperty = if ($null -ne $doc) { $doc.PSObject.Properties['items'] } else { $null }
    if ((Get-Field $doc 'version') -ne 1 -or $null -eq $itemsProperty -or $itemsProperty.Value -isnot [array]) { throw 'Reminder store has an unsupported format.' }
    foreach ($item in $doc.items) {
        $key = Get-Field $item 'key'; $state = Get-Field $item 'state'; $updated = [datetimeoffset]::MinValue
        if (-not ($key -is [string]) -or -not $key -or $state -notin @('completed','failed','interrupted') -or -not [datetimeoffset]::TryParse([string](Get-Field $item 'updated'), [ref]$updated)) { throw 'Reminder store contains an invalid entry.' }
        $saved[$key] = [pscustomobject]@{ State=$state; Updated=$updated }
    }
    return $saved
}

function Restore-Reminders([object[]]$Sessions, [hashtable]$Seen, [hashtable]$Unread, [hashtable]$Saved) {
    foreach ($session in $Sessions) {
        $key = $session.Source + ':' + $session.Id
        $previous = $Saved[$key]
        # Catalog-backed sources publish session state rather than turn IDs;
        # their metadata timestamp can change while the same result is unread.
        $sameRevision = $previous -and ($previous.Updated -eq $session.Updated -or $session.Source -in @('Codex Work','WorkBuddy','WorkBuddy AI','DeepSeek Harness'))
        if (-not $Seen.ContainsKey($key) -and $previous -and $previous.State -eq $session.State -and $sameRevision) { $Unread[$key] = $true }
    }
}

function Sync-ReminderStore([object[]]$Sessions, [hashtable]$Unread, [hashtable]$Saved, [datetimeoffset]$Now) {
    foreach ($session in $Sessions) {
        $key = $session.Source + ':' + $session.Id
        if ($Unread.ContainsKey($key) -and $session.State -in @('completed','failed','interrupted')) { $Saved[$key] = [pscustomobject]@{ State=$session.State; Updated=$session.Updated } }
        else { $Saved.Remove($key) }
    }
    # Unavailable sources do not erase unread reminders, but old records expire.
    foreach ($key in @($Saved.Keys)) { if ($Saved[$key].Updated -lt $Now.AddDays(-7)) { $Saved.Remove($key) } }
}

function Write-ReminderStore([string]$Path, [hashtable]$Saved) {
    $items = @($Saved.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ key=$_; state=$Saved[$_].State; updated=$Saved[$_].Updated.ToString('o') } })
    $json = [pscustomobject]@{ version=1; items=$items } | ConvertTo-Json -Depth 5
    if ([IO.File]::Exists($Path) -and [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) -eq $json) { return }
    $directory = [IO.Path]::GetDirectoryName($Path)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $tmp = Join-Path $directory ('.reminders-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, [System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($tmp, $Path) }
}
