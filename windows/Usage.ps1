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

function Get-CombinedUsage([string]$CodexHome, [string]$UserDirectory, [int]$Days, [string]$PricePath, [datetimeoffset]$Now = [datetimeoffset]::Now) {
    $codex = Get-CodexUsage $CodexHome $Days $PricePath $Now
    $claude = Get-ClaudeUsage $UserDirectory $Days $PricePath $Now
    return [pscustomobject]@{ Days=$codex.Days; Start=$codex.Start; End=$codex.End; Rows=@(@($codex.Rows) + @($claude.Rows) | Sort-Object Date,Source,Model,Provider); FilesScanned=$codex.FilesScanned + $claude.FilesScanned; ReadErrors=$codex.ReadErrors + $claude.ReadErrors }
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
