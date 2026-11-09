function Get-ConversationText($Content) {
    if ($Content -is [string]) { return $Content }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($block in @($Content)) {
        if ($null -eq $block) { continue }
        switch (Get-Field $block 'type') {
            { $_ -in @('text','input_text','output_text') } { $text = Get-Field $block 'text'; if ($text -is [string] -and $text) { $parts.Add($text) } }
            { $_ -in @('image','input_image','output_image') } { $parts.Add('[图片]') }
            { $_ -in @('document','input_file') } { $parts.Add('[附件]') }
        }
    }
    return [string]::Join("`n`n", $parts.ToArray())
}

function Resolve-ConversationPath($Session, [string]$UserDirectory) {
    $path = Get-Field $Session 'Path'
    if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
    if ($Session.Source -notin @('Claude Code','WorkBuddy','WorkBuddy AI')) { return $null }
    $guid = [guid]::Empty
    if (-not [guid]::TryParse([string]$Session.Id, [ref]$guid)) { return $null }
    $folder = switch ($Session.Source) { 'Claude Code' { '.claude' } 'WorkBuddy' { '.workbuddy' } 'WorkBuddy AI' { '.workbuddy-ai' } }
    $root = Join-Path (Join-Path $UserDirectory $folder) 'projects'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    # Refuse ambiguity rather than choosing an unrelated conversation.
    $matches = @(Get-ChildItem -LiteralPath $root -Filter ($guid.ToString() + '.jsonl') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/]subagents[\\/]' } | Select-Object -First 2)
    if ($matches.Count -eq 1) { return $matches[0].FullName }
    return $null
}

function Read-AgentConversation($Session, [string]$Path, [int]$MaxMessages = 200, [int]$MaxBytes = 4194304) {
    if ($Session.Source -notin @('Codex','Claude Code','WorkBuddy','WorkBuddy AI','DeepSeek Harness')) { throw '此来源不提供本地对话。' }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw '尚未找到此会话的本地对话记录。' }
    $maxMessages = [math]::Max(1, [math]::Min(200, $MaxMessages)); $maxBytes = [math]::Max(1, [math]::Min(4194304, $MaxBytes))
    $messages = New-Object 'System.Collections.Generic.List[object]'
    $state = [pscustomobject]@{ Truncated=$false; Characters=0 }
    function Add-ConversationMessage([string]$Id, [string]$Role, [string]$Text) {
        if ($Role -notin @('user','assistant') -or [string]::IsNullOrWhiteSpace($Text)) { return }
        if ($Text.Length -gt 20000) { $Text = $Text.Substring(0, 20000) + "`n[消息较长，仅显示前 20,000 字]"; $state.Truncated = $true }
        if ($Id) {
            for ($j = $messages.Count - 1; $j -ge 0; $j--) { if ($messages[$j].Id -eq $Id) { $state.Characters -= $messages[$j].Text.Length; $messages.RemoveAt($j) } }
        }
        $messages.Add([pscustomobject]@{ Id=$Id; Role=$Role; Text=$Text })
        $state.Characters += $Text.Length
        while ($messages.Count -gt $maxMessages -or $state.Characters -gt 200000) { $state.Characters -= $messages[0].Text.Length; $messages.RemoveAt(0); $state.Truncated = $true }
    }
    if ($Session.Source -eq 'DeepSeek Harness') {
        if ([IO.Path]::GetFileNameWithoutExtension($Path) -ne [string]$Session.Id) { throw '对话记录与所选会话不匹配。' }
        $file = Get-Item -LiteralPath $Path
        if ($file.Length -gt 16777216) { throw '对话投影过大，无法安全打开。' }
        $root = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
        $rows = Get-Field (Get-Field $root 'record') 'rows'; $outline = Get-ProjectionValue $rows 'turnOutline'
        if ($null -eq $outline) { throw '此会话尚未提供对话记录。' }
        foreach ($turn in @(Get-Field $outline 'turns')) {
            if ($null -eq $turn) { continue }
            $number = Get-Field $turn 'turn'
            Add-ConversationMessage "dsh:$($number):user" 'user' (Get-Field $turn 'prompt')
            Add-ConversationMessage "dsh:$($number):assistant" 'assistant' (Get-Field $turn 'response')
        }
        Add-ConversationMessage 'dsh:draft' 'assistant' (Get-Field $outline 'draft')
    } else {
        if ([IO.Path]::GetExtension($Path) -ne '.jsonl') { throw '对话记录格式不受支持。' }
        if ($Session.Source -eq 'Codex') {
            $first = @(Read-SharedLines $Path 1048576 $false)
            if ($first.Count -eq 0 -or -not $first[0]) { throw '对话记录为空。' }
            $header = $first[0] | ConvertFrom-Json -ErrorAction Stop
            if ((Get-Field $header 'type') -ne 'session_meta') { throw '对话记录缺少会话信息。' }
            $meta = Get-Field $header 'payload'; $id = Get-Field $meta 'id'; if (-not $id) { $id = Get-Field $meta 'session_id' }
            if ($id -and $id -ne $Session.Id) { throw '对话记录与所选会话不匹配。' }
        }
        if ((Get-Item -LiteralPath $Path).Length -gt $maxBytes) { $state.Truncated = $true }
        $sequence = 0
        foreach ($line in @(Read-SharedLines $Path $maxBytes)) {
            $sequence++
            try { $record = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            $kind = Get-Field $record 'type'; $message = $null
            if ($Session.Source -eq 'Codex') {
                $message = Get-Field $record 'payload'
                if ($kind -ne 'response_item' -or (Get-Field $message 'type') -ne 'message') { continue }
            } elseif ($Session.Source -in @('WorkBuddy','WorkBuddy AI')) {
                if ($kind -ne 'message') { continue }; $message = $record
            } else {
                if ((Get-Field $record 'isSidechain') -eq $true -or $kind -notin @('user','assistant')) { continue }
                $message = Get-Field $record 'message'
            }
            if ($Session.Source -ne 'Codex') { $recordId = Get-Field $record 'sessionId'; if ($recordId -and $recordId -ne $Session.Id) { continue } }
            $role = Get-Field $message 'role'; if ($role -notin @('user','assistant')) { continue }
            $id = Get-Field $record 'uuid'; if (-not $id) { $id = Get-Field $record 'id' }; if (-not $id) { $id = Get-Field $message 'id' }; if (-not $id) { $id = "line:$sequence" }
            Add-ConversationMessage ([string]$id) $role (Get-ConversationText (Get-Field $message 'content'))
        }
    }
    return [pscustomobject]@{ Messages=$messages.ToArray(); Truncated=$state.Truncated }
}
