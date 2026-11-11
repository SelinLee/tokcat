function Get-DesktopStateLabel([string]$State) {
    switch ($State) {
        'running' { '运行中' } 'waiting' { '等待回答' } 'approval' { '等待授权' }
        'stalled' { '长时间无活动' } 'completed' { '本轮结束' } 'failed' { '失败' }
        'interrupted' { '中断' } default { '未知' }
    }
}

function Select-DesktopSessions([object[]]$Sessions, [string]$Query, [string]$Source, [int]$StateIndex, [datetimeoffset]$Now) {
    $queryText = $Query.Trim()
    $matches = foreach ($session in $Sessions) {
        if ($Source -and $Source -ne '全部 Agent' -and $session.Source -ne $Source) { continue }
        $state = Get-SessionDisplayState $session $Now
        $allowed = @(switch ($StateIndex) {
            1 { @('running') } 2 { @('waiting','approval') } 3 { @('completed') }
            4 { @('failed','stalled') } 5 { @('unknown','interrupted') } default { @() }
        })
        if ($allowed.Count -gt 0 -and $state -notin $allowed) { continue }
        $haystack = @($session.Title, $session.Project, $session.Source, $session.Model, $session.Phase) -join ' '
        # Literal matching: brackets, question marks and paths are not wildcards.
        if ($queryText -and $haystack.IndexOf($queryText, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $priority = switch ($state) { 'waiting' {0} 'approval' {0} 'failed' {1} 'stalled' {2} 'running' {3} 'completed' {4} default {5} }
        [pscustomobject]@{ Session=$session; State=$state; Priority=$priority; Updated=$session.Updated; Key=($session.Source + ':' + $session.Id) }
    }
    $matches | Sort-Object Priority, @{Expression='Updated'; Descending=$true}, Key
}
