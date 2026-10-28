# Read local Codex counters only. Never store or return message/tool content.
function Get-UsagePricePath([string]$BaseDirectory, [string]$LocalDirectory, [bool]$CreateOverride = $false) {
    $defaultPath = Join-Path $BaseDirectory 'UsagePricing.json'
    $folder = Join-Path $LocalDirectory 'Tokcat'; $overridePath = Join-Path $folder 'usage-pricing.json'
    if ($CreateOverride -and -not [IO.File]::Exists($overridePath)) {
        [IO.Directory]::CreateDirectory($folder) | Out-Null
        try { [IO.File]::Copy($defaultPath, $overridePath, $false) } catch [IO.IOException] { if (-not [IO.File]::Exists($overridePath)) { throw } }
    }
    if ([IO.File]::Exists($overridePath)) { return $overridePath }
    return $defaultPath
}

function Get-UsageNumber($Object, [string]$Name) {
    $value = Get-Field $Object $Name
    if ($value -isnot [ValueType] -or $value -is [bool]) { return $null }
    try { $number = [double]$value } catch { return $null }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0 -or $number -gt 9007199254740991 -or [math]::Floor($number) -ne $number) { return $null }
    return [long]$number
}

function Get-UsageCounts($Value) {
    $inputCount = Get-UsageNumber $Value 'input_tokens'; $cache = Get-UsageNumber $Value 'cached_input_tokens'; $output = Get-UsageNumber $Value 'output_tokens'
    if ($null -eq $inputCount -or $null -eq $output) { return $null }
    if ($null -eq $cache) { $cache = 0 }
    if ($cache -gt $inputCount) { return $null }
    return [pscustomobject]@{ Input=$inputCount - $cache; Cache=$cache; Output=$output }
}

function Get-PriceCatalog([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return @() }
    $catalog = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    if ((Get-Field $catalog 'version') -ne 1 -or $null -eq $catalog.PSObject.Properties['models'] -or $catalog.models -isnot [array]) { throw '参考单价文件格式无效。' }
    $entries = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in $catalog.models) {
        $model = Get-Field $entry 'model'; $provider = Get-Field $entry 'provider'
        $inputRate = Convert-QuotaNumber (Get-Field $entry 'input'); $cacheRate = Convert-QuotaNumber (Get-Field $entry 'cache_read'); $outputRate = Convert-QuotaNumber (Get-Field $entry 'output'); $writeValue = Get-Field $entry 'cache_write'; $writeRate = Convert-QuotaNumber $writeValue
        if ($model -isnot [string] -or [string]::IsNullOrWhiteSpace($model) -or $null -eq $inputRate -or $null -eq $cacheRate -or $null -eq $outputRate -or $inputRate -lt 0 -or $cacheRate -lt 0 -or $outputRate -lt 0 -or ($null -ne $writeValue -and ($null -eq $writeRate -or $writeRate -lt 0))) { throw '参考单价文件包含无效条目。' }
        $entries.Add([pscustomobject]@{ Model=$model.ToLowerInvariant(); Provider=([string]$provider).ToLowerInvariant(); Input=$inputRate; Cache=$cacheRate; CacheWrite=$writeRate; Output=$outputRate })
    }
    return $entries.ToArray()
}

function Find-UsagePrice([object[]]$Prices, [string]$Model, [string]$Provider) {
    if (-not $Model) { return $null }
    $modelKey = $Model.ToLowerInvariant(); $providerKey = ([string]$Provider).ToLowerInvariant()
    $best = $null; $bestScore = -1
    foreach ($price in $Prices) {
        if ($modelKey -ne $price.Model -and $modelKey -notmatch ('^' + [regex]::Escape($price.Model) + '-(?:\d{4}-\d{2}-\d{2}|\d{8})$')) { continue }
        if ($price.Provider -and $providerKey -ne $price.Provider) { continue }
        if (-not $price.Provider -and $providerKey -and $providerKey -notin @('openai','anthropic')) { continue }
        if (-not $price.Provider -and $providerKey -eq 'openai' -and $price.Model.StartsWith('claude', [StringComparison]::Ordinal)) { continue }
        if (-not $price.Provider -and $providerKey -eq 'anthropic' -and -not $price.Model.StartsWith('claude', [StringComparison]::Ordinal)) { continue }
        $score = $price.Model.Length + $(if ($price.Provider) { 10000 } else { 0 })
        if ($score -gt $bestScore) { $best = $price; $bestScore = $score }
    }
    return $best
}

function Get-CodexUsage([string]$CodexHome, [int]$Days, [string]$PricePath, [datetimeoffset]$Now = [datetimeoffset]::Now) {
    $days = [math]::Max(1, [math]::Min(30, $Days))
    $start = $Now.LocalDateTime.Date.AddDays(1 - $days)
    $prices = @(Get-PriceCatalog $PricePath)
    if (-not ('TokcatCodexLogReader' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'CodexLogReader.cs') }
    $observations = New-Object 'System.Collections.Generic.List[object]'; $readErrors = 0; $filesScanned = 0
    foreach ($folder in @('sessions','archived_sessions')) {
        $directory = Join-Path $CodexHome $folder
        if (-not (Test-Path -LiteralPath $directory)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $start })) {
            $id = $null; $model = ''; $provider = ''
            try {
                foreach ($line in [TokcatCodexLogReader]::Read($file.FullName)) {
                    if (-not ($line.Contains('"session_meta"') -or $line.Contains('"turn_context"') -or $line.Contains('"token_count"'))) { continue }
                    try { $row = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                    $type = Get-Field $row 'type'; $payload = Get-Field $row 'payload'
                    if ($type -eq 'session_meta') { $id = Get-Field $payload 'id'; if (-not $id) { $id = Get-Field $payload 'session_id' }; $provider = [string](Get-Field $payload 'model_provider'); continue }
                    if ($type -eq 'turn_context') { $nextModel = Get-Field $payload 'model'; if ($nextModel -is [string]) { $model = $nextModel }; continue }
                    if ($type -ne 'event_msg' -or (Get-Field $payload 'type') -ne 'token_count' -or -not $id) { continue }
                    $time = [datetimeoffset]::MinValue
                    if (-not [datetimeoffset]::TryParse([string](Get-Field $row 'timestamp'), [ref]$time) -or $time -gt $Now.AddMinutes(5)) { continue }
                    $info = Get-Field $payload 'info'; $totals = Get-UsageCounts (Get-Field $info 'total_token_usage')
                    if ($null -eq $totals) { continue }
                    $last = Get-UsageCounts (Get-Field $info 'last_token_usage')
                    $observations.Add([pscustomobject]@{ Id=[string]$id; At=$time; Model=$model; Provider=$provider; Total=$totals; Last=$last })
                }
                $filesScanned++
            } catch { $readErrors++ }
        }
    }
    $groups = @{}; $baseline = @{}; $seen = @{}
    foreach ($entry in @($observations | Sort-Object Id, At)) {
        $identity = $entry.Id + '|' + $entry.At.ToUniversalTime().ToString('o')
        if ($seen.ContainsKey($identity)) { continue }; $seen[$identity] = $true
        $old = $baseline[$entry.Id]; $counts = $entry.Total
        $delta = $null
        if ($old -and $counts.Input -ge $old.Input -and $counts.Cache -ge $old.Cache -and $counts.Output -ge $old.Output) {
            $delta = [pscustomobject]@{ Input=$counts.Input - $old.Input; Cache=$counts.Cache - $old.Cache; Output=$counts.Output - $old.Output }
        } elseif (($null -eq $old -or $counts.Input -lt $old.Input -or $counts.Cache -lt $old.Cache -or $counts.Output -lt $old.Output) -and $entry.Last -and $entry.Last.Input -eq $counts.Input -and $entry.Last.Cache -eq $counts.Cache -and $entry.Last.Output -eq $counts.Output) { $delta = $counts }
        $baseline[$entry.Id] = $counts
        if ($null -eq $delta -or $entry.At.LocalDateTime -lt $start -or $entry.At -gt $Now -or ($delta.Input + $delta.Cache + $delta.Output) -eq 0) { continue }
        $day = $entry.At.LocalDateTime.ToString('yyyy-MM-dd'); $modelName = if ($entry.Model) { $entry.Model } else { '未知模型' }
        $providerName = if ($entry.Provider) { $entry.Provider } else { '未标注' }
        $key = $day + "`n" + $modelName + "`n" + $providerName
        if (-not $groups.ContainsKey($key)) { $groups[$key] = [pscustomobject]@{ Date=$day; Source='Codex'; Model=$modelName; Provider=$providerName; Input=[long]0; Cache=[long]0; CacheWrite=[long]0; Output=[long]0; EstimatedUSD=[double]0; UnpricedTokens=[long]0 } }
        $group = $groups[$key]; $group.Input += $delta.Input; $group.Cache += $delta.Cache; $group.Output += $delta.Output
        $price = Find-UsagePrice $prices $entry.Model $entry.Provider
        if ($null -eq $price) { $group.UnpricedTokens += $delta.Input + $delta.Cache + $delta.Output }
        else { $group.EstimatedUSD += ($delta.Input * $price.Input + $delta.Cache * $price.Cache + $delta.Output * $price.Output) / 1000000.0 }
    }
    return [pscustomobject]@{ Days=$days; Start=$start.ToString('yyyy-MM-dd'); End=$Now.LocalDateTime.ToString('yyyy-MM-dd'); Rows=@($groups.Values | Sort-Object Date, Model, Provider); FilesScanned=$filesScanned; ReadErrors=$readErrors }
}

function Get-ClaudeUsage([string]$UserDirectory, [int]$Days, [string]$PricePath, [datetimeoffset]$Now = [datetimeoffset]::Now) {
    $days = [math]::Max(1, [math]::Min(30, $Days)); $start = $Now.LocalDateTime.Date.AddDays(1 - $days)
    $prices = @(Get-PriceCatalog $PricePath)
    if (-not ('TokcatCodexLogReader' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'CodexLogReader.cs') }
    $root = Join-Path (Join-Path $UserDirectory '.claude') 'projects'
    $requests = @{}; $readErrors = 0; $filesScanned = 0
    if (Test-Path -LiteralPath $root) {
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $start })) {
            $lineNumber = 0
            try {
                foreach ($line in [TokcatCodexLogReader]::Read($file.FullName)) {
                    $lineNumber++
                    if (-not $line.Contains('"usage"') -or -not $line.Contains('"assistant"')) { continue }
                    try { $row = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                    if ((Get-Field $row 'type') -ne 'assistant') { continue }
                    $message = Get-Field $row 'message'; $model = Get-Field $message 'model'; $usage = Get-Field $message 'usage'
                    if ($model -isnot [string] -or -not $model -or $null -eq $usage) { continue }
                    $at = [datetimeoffset]::MinValue
                    if (-not [datetimeoffset]::TryParse([string](Get-Field $row 'timestamp'), [ref]$at) -or $at.LocalDateTime -lt $start -or $at -gt $Now) { continue }
                    $values = @{}; $valid = $true
                    foreach ($field in @('input_tokens','cache_read_input_tokens','cache_creation_input_tokens','output_tokens')) {
                        $raw = Get-Field $usage $field; $count = Get-UsageNumber $usage $field
                        if ($null -eq $count -and $null -ne $raw) { $valid = $false; break }
                        $values[$field] = if ($null -eq $count) { [long]0 } else { $count }
                    }
                    if (-not $valid) { continue }
                    $id = Get-Field $message 'id'; if (-not $id) { $id = Get-Field $row 'uuid' }; if (-not $id) { $id = $file.FullName + ':' + $lineNumber }
                    $total = $values.input_tokens + $values.cache_read_input_tokens + $values.cache_creation_input_tokens + $values.output_tokens
                    if ($total -eq 0) { continue }
                    $old = $requests[[string]$id]
                    if ($old) {
                        # A streamed update can omit or temporarily reduce a field.
                        # Preserve the largest observed cumulative value per request.
                        if ($old.Model -ne $model) { continue }
                        $values.input_tokens = [math]::Max($values.input_tokens, $old.Input)
                        $values.cache_read_input_tokens = [math]::Max($values.cache_read_input_tokens, $old.Cache)
                        $values.cache_creation_input_tokens = [math]::Max($values.cache_creation_input_tokens, $old.CacheWrite)
                        $values.output_tokens = [math]::Max($values.output_tokens, $old.Output)
                        if ($old.At -gt $at) { $at = $old.At }
                        $total = $values.input_tokens + $values.cache_read_input_tokens + $values.cache_creation_input_tokens + $values.output_tokens
                    }
                    $requests[[string]$id] = [pscustomobject]@{ At=$at; Model=$model; Input=$values.input_tokens; Cache=$values.cache_read_input_tokens; CacheWrite=$values.cache_creation_input_tokens; Output=$values.output_tokens; Total=$total }
                }
                $filesScanned++
            } catch { $readErrors++ }
        }
    }
    $groups = @{}
    foreach ($entry in $requests.Values) {
        $day = $entry.At.LocalDateTime.ToString('yyyy-MM-dd'); $key = $day + "`n" + $entry.Model
        if (-not $groups.ContainsKey($key)) { $groups[$key] = [pscustomobject]@{ Date=$day; Source='Claude Code'; Model=$entry.Model; Provider='未标注'; Input=[long]0; Cache=[long]0; CacheWrite=[long]0; Output=[long]0; EstimatedUSD=[double]0; UnpricedTokens=[long]0 } }
        $group = $groups[$key]; $group.Input += $entry.Input; $group.Cache += $entry.Cache; $group.CacheWrite += $entry.CacheWrite; $group.Output += $entry.Output
        $price = Find-UsagePrice $prices $entry.Model ''
        if ($null -eq $price -or ($entry.CacheWrite -gt 0 -and $null -eq $price.CacheWrite)) { $group.UnpricedTokens += $entry.Total }
        else { $group.EstimatedUSD += ($entry.Input * $price.Input + $entry.Cache * $price.Cache + $entry.CacheWrite * $price.CacheWrite + $entry.Output * $price.Output) / 1000000.0 }
    }
    return [pscustomobject]@{ Days=$days; Rows=@($groups.Values | Sort-Object Date, Model); FilesScanned=$filesScanned; ReadErrors=$readErrors }
}

function Get-FirstUsageNumber($Object, [string[]]$Names) {
    foreach ($name in $Names) {
        if ($null -ne (Get-Field $Object $name)) { return Get-UsageNumber $Object $name }
    }
    return [long]0
}

function Get-ActivityUsage([string[]]$Roots, [string]$Source, [int]$Days, [string]$PricePath, [datetimeoffset]$Now = [datetimeoffset]::Now) {
    if ($Source -notin @('OpenClaw','Kimi')) { throw 'Unsupported activity usage source.' }
    $start = $Now.LocalDateTime.Date.AddDays(1 - [math]::Max(1, [math]::Min(30, $Days)))
    $prices = @(Get-PriceCatalog $PricePath)
    if (-not ('TokcatCodexLogReader' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'CodexLogReader.cs') }
    $groups = @{}; $seen = @{}; $filesScanned = 0; $readErrors = 0
    foreach ($root in $Roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $start -and $(if ($Source -eq 'OpenClaw') { $_.Name -like '*trajectory*.jsonl' } else { $_.Name -like '*wire.jsonl' }) })) {
            if ($seen.ContainsKey($file.FullName)) { continue }; $seen[$file.FullName] = $true
            try {
                foreach ($line in [TokcatCodexLogReader]::Read($file.FullName)) {
                    if ($Source -eq 'OpenClaw' -and -not $line.Contains('model.completed')) { continue }
                    if ($Source -eq 'Kimi' -and -not $line.Contains('usage.record')) { continue }
                    try { $row = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                    $kind = Get-Field $row 'type'
                    if (($Source -eq 'OpenClaw' -and $kind -ne 'model.completed') -or ($Source -eq 'Kimi' -and $kind -ne 'usage.record')) { continue }
                    $at = [datetimeoffset]::MinValue
                    $time = if ($Source -eq 'Kimi') { Get-Field $row 'time' } else { Get-Field $row 'ts' }
                    if ($Source -eq 'Kimi' -and $time -is [ValueType] -and $time -isnot [bool]) {
                        try { $at = [datetimeoffset]::FromUnixTimeMilliseconds([long]$time) } catch { continue }
                    } else {
                        if (-not $time) { $time = Get-Field $row 'timestamp' }
                        if (-not [datetimeoffset]::TryParse([string]$time, [ref]$at)) { continue }
                    }
                    if ($at.LocalDateTime -lt $start -or $at -gt $Now) { continue }
                    if ($Source -eq 'OpenClaw') {
                        $data = Get-Field $row 'data'; $usage = Get-Field (Get-Field $data 'promptCache') 'lastCallUsage'; if ($null -eq $usage) { $usage = Get-Field $data 'usage' }
                        $inputCount = Get-FirstUsageNumber $usage @('input'); $output = Get-FirstUsageNumber $usage @('output'); $cache = Get-FirstUsageNumber $usage @('cacheRead'); $write = Get-FirstUsageNumber $usage @('cacheWrite')
                        $model = Get-Field $row 'modelId'; if (-not $model) { $model = Get-Field $row 'model' }; $provider = Get-Field $row 'provider'
                    } else {
                        $usage = Get-Field $row 'usage'
                        $inputCount = Get-FirstUsageNumber $usage @('inputOther','input','input_tokens','prompt_tokens'); $output = Get-FirstUsageNumber $usage @('output','output_tokens','completion_tokens'); $cache = Get-FirstUsageNumber $usage @('inputCacheRead','cacheRead','cached_tokens'); $write = Get-FirstUsageNumber $usage @('inputCacheCreation','cacheWrite','cache_creation_input_tokens')
                        $model = Get-Field $row 'model'; if (-not $model) { $model = Get-Field $row 'modelName' }; $provider = $null
                    }
                    if ($null -eq $usage -or $null -eq $inputCount -or $null -eq $output -or $null -eq $cache -or $null -eq $write) { continue }
                    $total = $inputCount + $output + $cache + $write; if ($total -eq 0) { continue }
                    if ($model -isnot [string] -or -not $model) { $model = $Source.ToLowerInvariant() }
                    if ($provider -isnot [string]) { $provider = '' }
                    $providerName = if ($provider) { $provider } else { '未标注' }; $day = $at.LocalDateTime.ToString('yyyy-MM-dd')
                    $key = $day + "`n" + $model + "`n" + $providerName
                    if (-not $groups.ContainsKey($key)) { $groups[$key] = [pscustomobject]@{ Date=$day; Source=$Source; Model=$model; Provider=$providerName; Input=[long]0; Cache=[long]0; CacheWrite=[long]0; Output=[long]0; EstimatedUSD=[double]0; UnpricedTokens=[long]0 } }
                    $group = $groups[$key]; $group.Input += $inputCount; $group.Cache += $cache; $group.CacheWrite += $write; $group.Output += $output
                    $price = Find-UsagePrice $prices $model $provider
                    if ($null -eq $price -or ($write -gt 0 -and $null -eq $price.CacheWrite)) { $group.UnpricedTokens += $total }
                    else { $group.EstimatedUSD += ($inputCount * $price.Input + $cache * $price.Cache + $write * $price.CacheWrite + $output * $price.Output) / 1000000.0 }
                }
                $filesScanned++
            } catch { $readErrors++ }
        }
    }
    return [pscustomobject]@{ Rows=@($groups.Values | Sort-Object Date,Model,Provider); FilesScanned=$filesScanned; ReadErrors=$readErrors }
}

function Get-WorkBuddyCounts($Usage) {
    if ($null -eq $Usage) { return $null }
    $inputCount = Get-FirstUsageNumber $Usage @('prompt_tokens','input_tokens','input'); $output = Get-FirstUsageNumber $Usage @('completion_tokens','output_tokens','output')
    $details = Get-Field $Usage 'prompt_tokens_details'; if ($null -ne $details) { $cache = Get-FirstUsageNumber $details @('cached_tokens') } else { $cache = Get-FirstUsageNumber $Usage @('cached_tokens','cacheRead') }
    if ($null -eq $inputCount -or $null -eq $output -or $null -eq $cache -or $cache -gt $inputCount -or ($inputCount + $output) -eq 0) { return $null }
    return [pscustomobject]@{ Input=$inputCount; Output=$output; Cache=$cache }
}

function Get-WorkBuddyUsage([string]$UserDirectory, [int]$Days, [string]$PricePath, [datetimeoffset]$Now = [datetimeoffset]::Now) {
    $start = $Now.LocalDateTime.Date.AddDays(1 - [math]::Max(1, [math]::Min(30, $Days)))
    $prices = @(Get-PriceCatalog $PricePath); $groups = @{}; $filesScanned = 0; $readErrors = 0; $skipped = 0
    foreach ($config in @(@('.workbuddy','WorkBuddy'), @('.workbuddy-ai','WorkBuddy AI'))) {
        $root = Join-Path (Join-Path $UserDirectory $config[0]) 'traces'
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter 'trace_*.json' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $start })) {
            try {
                $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
                try {
                    if ($stream.Length -gt 4194304) { $skipped++; continue }
                    $bytes = New-Object byte[] ([int]$stream.Length); $count = 0
                    while ($count -lt $bytes.Length) { $n = $stream.Read($bytes, $count, $bytes.Length - $count); if ($n -eq 0) { break }; $count += $n }
                    if ($count -ne $bytes.Length) { throw 'Incomplete trace snapshot' }
                    $traceFile = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
                } finally { $stream.Dispose() }
                $trace = Get-Field $traceFile 'trace'; $modelInfo = Get-Field $trace 'modelInfo'; $models = @(Get-Field $modelInfo 'models'); $fallback = if ($models.Count -gt 0 -and $models[0] -is [string]) { $models[0] } else { Get-Field $trace 'agentName' }; if (-not $fallback) { $fallback = 'workbuddy' }
                $seen = @{}
                foreach ($span in @(Get-Field $traceFile 'spans')) {
                    if ((Get-Field $span 'type') -ne 'generation' -and (Get-Field $span 'name') -ne 'generation') { continue }
                    $spanId = Get-Field $span 'spanId'; if ($spanId -and $seen.ContainsKey([string]$spanId)) { continue }
                    $time = Get-Field $span 'endedAt'; if (-not $time) { $time = Get-Field $span 'startedAt' }
                    $at = [datetimeoffset]::MinValue; if (-not [datetimeoffset]::TryParse([string]$time, [ref]$at) -or $at.LocalDateTime -lt $start -or $at -gt $Now) { continue }
                    $toolOutput = Get-Field $span 'toolOutput'
                    if ($toolOutput -is [string]) { try { $toolOutput = $toolOutput | ConvertFrom-Json -ErrorAction Stop } catch { $toolOutput = $null } }
                    $candidates = @($toolOutput); [array]::Reverse($candidates)
                    $counts = $null; $model = $fallback
                    foreach ($candidate in $candidates) {
                        $candidateCounts = Get-WorkBuddyCounts (Get-Field $candidate 'usage')
                        if ($null -eq $candidateCounts) { continue }
                        $counts = $candidateCounts; $candidateModel = Get-Field $candidate 'model'; if ($candidateModel -is [string] -and $candidateModel) { $model = $candidateModel }; break
                    }
                    if ($null -eq $counts) { $counts = Get-WorkBuddyCounts (Get-Field $span 'usage') }; if ($null -eq $counts) { continue }
                    $inputCount = $counts.Input; $cache = $counts.Cache; $output = $counts.Output
                    $uncached = $inputCount - $cache; $total = $inputCount + $output; if ($total -eq 0) { continue }; if ($spanId) { $seen[[string]$spanId] = $true }
                    $day = $at.LocalDateTime.ToString('yyyy-MM-dd'); $key = $day + "`n" + $config[1] + "`n" + $model
                    if (-not $groups.ContainsKey($key)) { $groups[$key] = [pscustomobject]@{ Date=$day; Source=$config[1]; Model=$model; Provider='未标注'; Input=[long]0; Cache=[long]0; CacheWrite=[long]0; Output=[long]0; EstimatedUSD=[double]0; UnpricedTokens=[long]0 } }
                    $group = $groups[$key]; $group.Input += $uncached; $group.Cache += $cache; $group.Output += $output
                    $price = Find-UsagePrice $prices $model ''
                    if ($null -eq $price) { $group.UnpricedTokens += $total }
                    else { $group.EstimatedUSD += ($uncached * $price.Input + $cache * $price.Cache + $output * $price.Output) / 1000000.0 }
                }
                $filesScanned++
            } catch { $readErrors++ }
        }
    }
    return [pscustomobject]@{ Rows=@($groups.Values | Sort-Object Date,Source,Model); FilesScanned=$filesScanned; ReadErrors=$readErrors; Skipped=$skipped }
}

function Save-DshUsage([object[]]$Sessions, [hashtable]$Baseline, [string]$Path, [datetimeoffset]$Now = [datetimeoffset]::Now) {
    foreach ($session in $Sessions) {
        $usage = Get-Field $session 'Usage'; $id = Get-Field $session 'Id'; if (-not $id -or $null -eq $usage) { continue }
        $inputCount = if ($null -ne (Get-Field $usage 'uncachedInputTokens')) { Get-UsageNumber $usage 'uncachedInputTokens' } else { Get-UsageNumber $usage 'inputTokens' }
        $output = Get-UsageNumber $usage 'outputTokens'; $cache = Get-UsageNumber $usage 'cacheReadTokens'; $write = Get-UsageNumber $usage 'cacheWriteTokens'
        if ($null -eq $inputCount -or $null -eq $output -or $null -eq $cache -or $null -eq $write) { continue }
        $model = [string](Get-Field $session 'Model'); $provider = [string](Get-Field $session 'Provider')
        $current = [pscustomobject]@{ Input=$inputCount; Output=$output; Cache=$cache; CacheWrite=$write; Model=$model; Provider=$provider }
        $old = $Baseline[[string]$id]
        if ($old -and $inputCount -ge $old.Input -and $output -ge $old.Output -and $cache -ge $old.Cache -and $write -ge $old.CacheWrite) {
            $delta = [pscustomobject]@{ timestamp=$Now.ToUniversalTime().ToString('o'); model=$(if ($model -and $model -eq $old.Model -and $provider -eq $old.Provider) { $model } else { '' }); provider=$(if ($model -and $model -eq $old.Model -and $provider -eq $old.Provider) { $provider } else { '' }); input_tokens=$inputCount-$old.Input; output_tokens=$output-$old.Output; cache_read_tokens=$cache-$old.Cache; cache_write_tokens=$write-$old.CacheWrite }
            if (($delta.input_tokens + $delta.output_tokens + $delta.cache_read_tokens + $delta.cache_write_tokens) -gt 0) {
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
                $line = ($delta | ConvertTo-Json -Compress) + "`n"
                $stream = [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
                try {
                    if ($stream.Length -gt 0) { [void]$stream.Seek(-1, [IO.SeekOrigin]::End); if ($stream.ReadByte() -ne 10) { $line = "`n" + $line } }
                    [void]$stream.Seek(0, [IO.SeekOrigin]::End); $bytes = [Text.Encoding]::UTF8.GetBytes($line); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
                } finally { $stream.Dispose() }
            }
        }
        $Baseline[[string]$id] = $current
    }
}

function Get-DshRecordedUsage([string]$LocalDirectory, [int]$Days, [string]$PricePath, [datetimeoffset]$Now = [datetimeoffset]::Now) {
    $path = Join-Path $LocalDirectory 'Tokcat\dsh-usage.jsonl'; $start = $Now.LocalDateTime.Date.AddDays(1 - [math]::Max(1, [math]::Min(30, $Days)))
    if (-not [IO.File]::Exists($path)) { return [pscustomobject]@{ Rows=@(); FilesScanned=0; ReadErrors=0 } }
    $prices = @(Get-PriceCatalog $PricePath)
    if (-not ('TokcatCodexLogReader' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'CodexLogReader.cs') }
    $groups = @{}
    foreach ($line in [TokcatCodexLogReader]::Read($path)) {
        try { $entry = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $at = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse([string](Get-Field $entry 'timestamp'), [ref]$at) -or $at.LocalDateTime -lt $start -or $at -gt $Now) { continue }
        $inputCount = Get-UsageNumber $entry 'input_tokens'; $output = Get-UsageNumber $entry 'output_tokens'; $cache = Get-UsageNumber $entry 'cache_read_tokens'; $write = Get-UsageNumber $entry 'cache_write_tokens'
        if ($null -eq $inputCount -or $null -eq $output -or $null -eq $cache -or $null -eq $write) { continue }
        $total = $inputCount + $output + $cache + $write; if ($total -eq 0) { continue }
        $model = [string](Get-Field $entry 'model'); $provider = [string](Get-Field $entry 'provider'); $modelName = if ($model) { $model } else { '未知模型' }; $providerName = if ($provider) { $provider } else { '未标注' }
        $day = $at.LocalDateTime.ToString('yyyy-MM-dd'); $key = $day + "`n" + $modelName + "`n" + $providerName
        if (-not $groups.ContainsKey($key)) { $groups[$key] = [pscustomobject]@{ Date=$day; Source='DeepSeek Harness'; Model=$modelName; Provider=$providerName; Input=[long]0; Cache=[long]0; CacheWrite=[long]0; Output=[long]0; EstimatedUSD=[double]0; UnpricedTokens=[long]0 } }
        $group = $groups[$key]; $group.Input += $inputCount; $group.Output += $output; $group.Cache += $cache; $group.CacheWrite += $write
        $price = Find-UsagePrice $prices $model $provider
        if ($null -eq $price -or ($write -gt 0 -and $null -eq $price.CacheWrite)) { $group.UnpricedTokens += $total }
        else { $group.EstimatedUSD += ($inputCount * $price.Input + $output * $price.Output + $cache * $price.Cache + $write * $price.CacheWrite) / 1000000.0 }
    }
    return [pscustomobject]@{ Rows=@($groups.Values | Sort-Object Date,Model,Provider); FilesScanned=1; ReadErrors=0 }
}

function Get-CombinedUsage([string]$CodexHome, [string]$UserDirectory, [int]$Days, [string]$PricePath, [datetimeoffset]$Now = [datetimeoffset]::Now, [string]$LocalDirectory = $env:LOCALAPPDATA) {
    $codex = Get-CodexUsage $CodexHome $Days $PricePath $Now
    $claude = Get-ClaudeUsage $UserDirectory $Days $PricePath $Now
    $openclaw = Get-ActivityUsage @((Join-Path $UserDirectory '.openclaw\agents')) 'OpenClaw' $Days $PricePath $Now
    $kimiRoots = @((Join-Path $UserDirectory '.kimi-work'), (Join-Path $UserDirectory '.kimi-webbridge'))
    if ($env:APPDATA) { $kimiRoots += @((Join-Path $env:APPDATA 'kimi-desktop'), (Join-Path $env:APPDATA 'kimi')) }
    $kimi = Get-ActivityUsage $kimiRoots 'Kimi' $Days $PricePath $Now
    $buddy = Get-WorkBuddyUsage $UserDirectory $Days $PricePath $Now
    $dsh = Get-DshRecordedUsage $LocalDirectory $Days $PricePath $Now
    return [pscustomobject]@{ Days=$codex.Days; Start=$codex.Start; End=$codex.End; Rows=@(@($codex.Rows) + @($claude.Rows) + @($openclaw.Rows) + @($kimi.Rows) + @($buddy.Rows) + @($dsh.Rows) | Sort-Object Date,Source,Model,Provider); FilesScanned=$codex.FilesScanned + $claude.FilesScanned + $openclaw.FilesScanned + $kimi.FilesScanned + $buddy.FilesScanned + $dsh.FilesScanned; ReadErrors=$codex.ReadErrors + $claude.ReadErrors + $openclaw.ReadErrors + $kimi.ReadErrors + $buddy.ReadErrors + $dsh.ReadErrors; Skipped=$buddy.Skipped }
}

# This view is deliberately separate: proxy records can also occur in agent logs.
function Get-CCSwitchUsage([string]$UserDirectory, [int]$Days, [datetimeoffset]$Now = [datetimeoffset]::Now) {
    $days = [math]::Max(1, [math]::Min(30, $Days))
    $start = $Now.LocalDateTime.Date.AddDays(1 - $days)
    $from = [datetimeoffset]::new($start).ToUnixTimeSeconds()
    $until = $Now.ToUnixTimeSeconds() + 1
    $path = Join-Path $UserDirectory '.cc-switch\cc-switch.db'
    if (-not [IO.File]::Exists($path)) { return [pscustomobject]@{ Rows=@(); FilesScanned=0; ReadErrors=0; Present=$false; Truncated=$false; Invalid=0 } }
    if (-not ('TokcatWorkCatalog' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'WorkCatalog.cs') }
    $records = @([TokcatWorkCatalog]::ReadProxy($path, $from, $until)); $truncated = $records.Count -gt 100000
    $groups = @{}; $invalid = 0
    foreach ($entry in @($records | Select-Object -First 100000)) {
        $counts = @(); $valid = $true
        foreach ($raw in @($entry.Input, $entry.CacheRead, $entry.CacheWrite, $entry.Output)) {
            $number = [long]0
            if ($null -ne $raw -and (-not [long]::TryParse($raw, [ref]$number) -or $number -lt 0)) { $valid = $false; break }
            $counts += $number
        }
        if (-not $valid) { $invalid++; continue }
        $total = [double]$counts[0] + $counts[1] + $counts[2] + $counts[3]
        if ($total -eq 0) { continue }
        $at = [datetimeoffset]::FromUnixTimeSeconds($entry.CreatedAt)
        $day = $at.LocalDateTime.ToString('yyyy-MM-dd')
        $app = if ($entry.App) { $entry.App } else { '未知应用' }; $provider = if ($entry.Provider) { $entry.Provider } else { '未标注' }; $model = if ($entry.Model) { $entry.Model } else { '未知模型' }
        $key = $day + "`n" + $app + "`n" + $provider + "`n" + $model
        if (-not $groups.ContainsKey($key)) { $groups[$key] = [pscustomobject]@{ Date=$day; Source=$app; Model=$model; Provider=$provider; Input=[long]0; Cache=[long]0; CacheWrite=[long]0; Output=[long]0; EstimatedUSD=[double]0; UnpricedTokens=[long]0 } }
        $group = $groups[$key]; $group.Input += $counts[0]; $group.Cache += $counts[1]; $group.CacheWrite += $counts[2]; $group.Output += $counts[3]
        $cost = [double]0
        if ([double]::TryParse($entry.ReportedCost, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$cost) -and $cost -gt 0 -and -not [double]::IsInfinity($cost) -and -not [double]::IsNaN($cost)) { $group.EstimatedUSD += $cost }
        else { $group.UnpricedTokens += $total }
    }
    return [pscustomobject]@{ Rows=@($groups.Values | Sort-Object Date,Source,Model,Provider); FilesScanned=1; ReadErrors=0; Present=$true; Truncated=$truncated; Invalid=$invalid }
}
