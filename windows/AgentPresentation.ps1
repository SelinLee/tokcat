# Keep these deadlines in sync with AgentSession and AgentViewingTracker on macOS.
function Merge-WorkStatusSnapshot([object[]]$Sessions, [hashtable]$Cache, [bool]$Available, [datetimeoffset]$Now) {
    if (-not $Cache.ContainsKey('LastAvailable')) { $Cache.LastAvailable=$Now; $Cache.Sessions=@() }
    if ($Available) { $Cache.LastAvailable=$Now; $Cache.Sessions=@($Sessions | Where-Object { $_.Source -eq 'Codex Work' }) }
    else {
        $Cache.Sessions=@(foreach ($session in $Cache.Sessions) {
            if ($session.Updated -lt $Now.AddDays(-7)) { continue }
            if (($Now-$Cache.LastAvailable).TotalSeconds -ge 120 -and $session.State -notin @('completed','failed','interrupted','unknown')) {
                $session=$session | Select-Object *; $session.State='unknown'
            }
            $session
        })
    }
    return @($Sessions | Where-Object { $_.Source -ne 'Codex Work' }) + @($Cache.Sessions)
}

function Update-DotObservations([object[]]$Sessions, [hashtable]$Observations, [datetimeoffset]$Now) {
    foreach ($session in $Sessions) {
        $key = $session.Source + ':' + $session.Id; $old = $Observations[$key]
        $since = if ($old -and $old.State -eq $session.State) { $old.ObservedAt } elseif ($old -or $session.State -ne 'unknown') { $Now } else { $session.Updated }
        $Observations[$key] = [pscustomobject]@{ State=$session.State; Updated=$session.Updated; ObservedAt=$since }
        $session | Add-Member -NotePropertyName StateObservedAt -NotePropertyValue $since -Force
    }
    foreach ($key in @($Observations.Keys)) { if ($Observations[$key].Updated -lt $Now.AddDays(-7)) { $Observations.Remove($key) } }
}

function Read-DotObservations([string]$Path) {
    $saved = @{}
    if (-not [IO.File]::Exists($Path)) { return $saved }
    $doc = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    $items=if ($doc) { $doc.PSObject.Properties['items'] } else { $null }
    if ((Get-Field $doc 'version') -ne 1 -or $null -eq $items -or $items.Value -isnot [array]) { throw 'Dot observations have an unsupported format.' }
    foreach ($item in $doc.items) {
        $updated=[datetimeoffset]::MinValue; $observed=[datetimeoffset]::MinValue
        if ((Get-Field $item 'key') -notlike 'Codex Work:*' -or (Get-Field $item 'state') -notin @('running','waiting','approval','completed','failed','interrupted','unknown','stalled') -or
            -not [datetimeoffset]::TryParse([string](Get-Field $item 'updated'),[ref]$updated) -or -not [datetimeoffset]::TryParse([string](Get-Field $item 'observedAt'),[ref]$observed)) { throw 'Invalid dot observation.' }
        $saved[$item.key]=[pscustomobject]@{ State=$item.state; Updated=$updated; ObservedAt=$observed }
    }
    return $saved
}

function Write-DotObservations([string]$Path, [hashtable]$Observations) {
    $items=@($Observations.Keys | Where-Object { $_ -like 'Codex Work:*' } | Sort-Object | ForEach-Object {
        $item=$Observations[$_]; [pscustomobject]@{ key=$_; state=$item.State; updated=$item.Updated.ToString('o'); observedAt=$item.ObservedAt.ToString('o') }
    })
    $json=[pscustomobject]@{version=1; items=$items} | ConvertTo-Json -Depth 4
    if ([IO.File]::Exists($Path) -and [IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8) -eq $json) { return }
    $directory=[IO.Path]::GetDirectoryName($Path); [void][IO.Directory]::CreateDirectory($directory)
    $temp=Join-Path $directory ('.dot-observations-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($temp,$Path) }
}

function Get-ReminderRevision($Session) {
    $catalog=$Session.Source -in @('Codex Work','WorkBuddy','WorkBuddy AI','DeepSeek Harness')
    $stamp=if ($catalog -and (Get-Field $Session 'StateObservedAt')) { $Session.StateObservedAt } else { $Session.Updated }
    return $Session.State + '|' + ([datetimeoffset]$stamp).UtcDateTime.Ticks + '|' + [string](Get-Field $Session 'TurnId')
}

function Update-ViewedReminders([object[]]$Sessions, [hashtable]$Unread, [hashtable]$Pending, [string]$ForegroundSource, [datetimeoffset]$Now) {
    $visible=@{}; $flashing=@{}; $changed=$false
    foreach ($session in $Sessions) {
        $key=$session.Source + ':' + $session.Id
        $source=if ($session.Source -eq 'Codex Work') { 'Codex' } else { $session.Source }
        if (-not $ForegroundSource -or $source -ne $ForegroundSource -or $session.State -notin @('completed','failed') -or -not $Unread.ContainsKey($key)) { continue }
        $visible[$key]=$true; $revision=Get-ReminderRevision $session; $previous=$Pending[$key]
        if (-not $previous -or $previous.Revision -ne $revision) { $Pending[$key]=[pscustomobject]@{ Revision=$revision; SeenAt=$Now } }
        if (($Now-$Pending[$key].SeenAt).TotalSeconds -ge 3) { $Unread.Remove($key); $Pending.Remove($key); $changed=$true }
        else { $flashing[$key]=$Pending[$key].SeenAt }
    }
    foreach ($key in @($Pending.Keys)) { if (-not $visible.ContainsKey($key)) { $Pending.Remove($key) } }
    return [pscustomobject]@{ Changed=$changed; FlashingSince=$flashing }
}

function Get-SessionDisplayState($Session, [datetimeoffset]$Now) {
    if ($Session.State -eq 'running' -and ($Now-$Session.Updated).TotalSeconds -ge 120) { return 'stalled' }
    return $Session.State
}

function Get-TaskbarDotPresentation([object[]]$Sessions, [hashtable]$Unread, [hashtable]$FlashingSince, [datetimeoffset]$Now, [bool]$ReduceMotion=$false) {
    $dots=@(foreach ($session in $Sessions) {
        if ($session.Source -in @('OpenClaw','Kimi')) { continue }
        $key=$session.Source + ':' + $session.Id
        if ($session.State -in @('completed','failed','interrupted') -and -not $Unread.ContainsKey($key)) { continue }
        $state=Get-SessionDisplayState $session $Now; $dim=$false
        if ($state -in @('unknown','interrupted')) {
            $since=$session.Updated
            if ($state -eq 'unknown' -and $session.Source -eq 'Codex Work' -and (Get-Field $session 'StateObservedAt') -gt $since) { $since=$session.StateObservedAt }
            $age=[math]::Max(0.0,($Now-$since).TotalSeconds)
            if ($age -ge 13) { continue }
            if ($age -ge 10) { $dim=-not $ReduceMotion -and ([math]::Floor(($age-10)/0.4)%2 -eq 1) }
        } elseif ($state -in @('completed','failed') -and $FlashingSince.ContainsKey($key)) {
            $dim=-not $ReduceMotion -and ([math]::Floor([math]::Max(0.0,($Now-$FlashingSince[$key]).TotalSeconds)/0.4)%2 -eq 1)
        }
        $priority=switch ($state) { 'waiting' {0} 'approval' {0} 'failed' {1} 'completed' {2} default {3} }
        [pscustomobject]@{ Key=$key; State=$state; Dimmed=$dim; Priority=$priority }
    })
    $dots=@($dots | Sort-Object Priority,Key)
    return [pscustomobject]@{ States=[string[]]@($dots | ForEach-Object { $_.State }); Dimmed=[bool[]]@($dots | ForEach-Object { $_.Dimmed }) }
}
