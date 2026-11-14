$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Launcher.ps1')
function Assert-Animation($condition,[string]$message) { if(-not $condition) { throw $message } }
function New-AnimationRows([int]$count,[int]$shift,[int]$catalog=24) {
    ,[TokcatLauncherResult[]]@(0..($count-1) | ForEach-Object {
        $id=($_+$shift)%$catalog
        [TokcatLauncherResult]@{Title=('Application '+$id);Kind='settings';Key=('animate:'+$id);RadialWeight=(2/(1+$_*.25))}
    })
}
function Measure-SettleChange($before,$after) {
    # Align on the input arc when the outer rings retire and the canvas shrinks.
    $side=[Math]::Min($before.Width,$after.Width)
    $first=[int](($before.Width-$side)/2); $second=[int](($after.Width-$side)/2)
    $changed=0; $samples=0
    for($y=1;$y -lt $side;$y+=4) {
        for($x=1;$x -lt $side;$x+=4) {
            $a=$before.GetPixel($first+$x,$first+$y); $b=$after.GetPixel($second+$x,$second+$y)
            if ($a.A -eq 0 -and $b.A -eq 0) { continue }
            $samples++
            if ([Math]::Abs([int]$a.A-$b.A) -gt 8 -or
                [Math]::Abs($a.R*$a.A-$b.R*$b.A) -gt 8*255 -or
                [Math]::Abs($a.G*$a.A-$b.G*$b.A) -gt 8*255 -or
                [Math]::Abs($a.B*$a.A-$b.B*$b.A) -gt 8*255) { $changed++ }
        }
    }
    return 100.0*$changed/[Math]::Max(1,$samples)
}
$palette=[Drawing.Color[]]@([Drawing.Color]::Black,[Drawing.Color]::FromArgb(32,35,40),[Drawing.Color]::White,[Drawing.Color]::Silver,[Drawing.Color]::DarkCyan)
$window=[TokcatLauncherWindow]::new($palette);$window.IsPreview=$true
try {
    $window.Appearance.Configure('radial',$false);$window.Query.Text='application'
    $window.SetResults((New-AnimationRows 9 0),'');$frame=$window.Radial.Render();$frame.Dispose()
    $window.IsPreview=$false;$window.SetResults((New-AnimationRows 9 3 9),'')
    if([TokcatRadialMotion]::ReducedMotion) {
        Assert-Animation (-not $window.Radial.Motion.IsAnimating) 'Windows reduced-motion preferences must be respected.'
        Write-Output 'Animation performance checks skipped because Windows reduced motion is enabled.'
    } else {
        Assert-Animation $window.Radial.Motion.IsAnimating 'Result changes must retain the continuous spring reflow.'
        $times=[Collections.Generic.List[double]]::new();$tailBuilds=0
        foreach($step in 1..57) {
            $watch=[Diagnostics.Stopwatch]::StartNew();$window.Radial.Motion.Advance($step/60.0)
            $frame=$window.Radial.Render();$frame.Dispose();$watch.Stop()
            if($step -gt 6) { $times.Add($watch.Elapsed.TotalMilliseconds) }
            if($step -eq 45) { $tailBuilds=$window.Radial.SpriteBuildCount }
        }
        $sorted=@($times | Sort-Object);$median=$sorted[$sorted.Count/2];$p95=$sorted[[int]($sorted.Count*.95)]
        Assert-Animation ($median -lt 16 -and $p95 -lt 30) ('Reflow rendering exceeds the frame budget: median '+[Math]::Round($median,2)+' ms; p95 '+[Math]::Round($p95,2)+' ms.')
        Assert-Animation ($window.Radial.SpriteBuildCount -eq $tailBuilds) 'Moving and fading existing labels must reuse their glyph outlines.'
        Write-Output ('Reflow render median: '+[Math]::Round($median,2)+' ms; p95: '+[Math]::Round($p95,2)+' ms.')

        foreach($count in @(9,4,1)) {
            $window.SetResults((New-AnimationRows $count 8),'')
            $window.Radial.Motion.Advance(.9599)
            $before=$window.Radial.Render()
            try {
                $window.Radial.Motion.Advance(.96); $window.Radial.Update($false)
                $after=$window.Radial.Render()
                try { $changed=Measure-SettleChange $before $after } finally { $after.Dispose() }
            } finally { $before.Dispose() }
            Write-Output ('Changed visible samples on settling ('+$count+' results): '+[Math]::Round($changed,2)+'%.')
            Assert-Animation ($changed -lt 2) 'Settling may finish minor spring motion but must not repaint the whole wheel differently.'
        }

        # Interrupt before settling, with both replacements and different ring
        # counts. Departing entries, masks and glyph caches must stay bounded.
        foreach($generation in 1..24) {
            $count=@(9,4,9,2,8,9)[($generation-1)%6]
            $window.Query.Text='query '+$generation;$window.SetResults((New-AnimationRows $count $generation),'')
            foreach($step in 1..6) {
                $window.Radial.Motion.Advance($step/60.0);$frame=$window.Radial.Render();$frame.Dispose()
                Assert-Animation ($window.Radial.Motion.Entries.Length -le 18 -and $window.Radial.Motion.Bands.Length -le 6) 'Interrupted reflows must not accumulate retired entries or arcs.'
                Assert-Animation (@($window.Radial.Motion.Entries | Where-Object Ring -ge 3).Count -eq 0) 'Moving and retiring results must remain within three rings.'
                Assert-Animation ($window.Radial.CachedSpriteCount -le 192) 'The glyph and icon cache must remain bounded.'
            }
        }
        $window.Radial.Motion.Advance(.96);$window.Radial.Update($false)
        Assert-Animation (-not $window.Radial.Motion.IsAnimating -and @($window.Radial.Motion.Entries | Where-Object Departing).Count -eq 0) 'The latest reflow must settle without a queued animation backlog.'

        # Observe actual native presentation timestamps, including typing, fog
        # sampling, frame scheduling and UpdateLayeredWindow. Polling only the
        # latest timestamp can incorrectly count missed observations as drops.
        $window.Appearance.Prepare();[void]$window.Show();$window.Activate();[void]$window.Query.Focus();$window.Appearance.Presented()
        $surface=$window.Radial.GetType().GetField('surface',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($window.Radial)
        $clock=[Diagnostics.Stopwatch]::StartNew();$lastInput=0.0;$generation=0
        $inputTimes=[Collections.Generic.List[double]]::new()
        while($clock.ElapsedMilliseconds -lt 2400) {
            if($clock.ElapsedMilliseconds -gt $lastInput+100 -and $generation -lt 16) {
                $generation++;$lastInput=$clock.ElapsedMilliseconds
                $watch=[Diagnostics.Stopwatch]::StartNew();$window.Query.Text='typing '+$generation
                $window.SetResults((New-AnimationRows 9 $generation 12),'');$watch.Stop();$inputTimes.Add($watch.Elapsed.TotalMilliseconds)
            }
            [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 1
        }
        $stamps=$surface.PresentationTimestamps
        Assert-Animation ($stamps.Length -gt 60) 'The native wheel must keep presenting during continuous input.'
        $intervals=@(10..($stamps.Length-1) | ForEach-Object {($stamps[$_]-$stamps[$_-1])*1000.0/[Diagnostics.Stopwatch]::Frequency} | Sort-Object)
        $median=$intervals[$intervals.Count/2];$p95=$intervals[[int]($intervals.Count*.95)]
        Assert-Animation ($median -lt 24 -and $p95 -lt 50) ('Native presentation cadence is uneven: median '+[Math]::Round($median,2)+' ms; p95 '+[Math]::Round($p95,2)+' ms.')
        $inputMax=($inputTimes | Measure-Object -Maximum).Maximum
        Assert-Animation ($inputMax -lt 35) 'Typing must update the current results without waiting for the animation.'
        Write-Output ('Native continuous-input frame interval median: '+[Math]::Round($median,2)+' ms; p95: '+[Math]::Round($p95,2)+' ms. Input update maximum: '+[Math]::Round($inputMax,2)+' ms.')
    }
    $window.Hide()
    Assert-Animation ($window.Radial.CachedSpriteCount -eq 0) 'Closing the wheel must release cached glyph paths and icons.'
    Assert-Animation (-not $window.Radial.GetType().GetField('preciseTimer',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($window.Radial)) 'Closing the wheel must release its timer-resolution request.'
    Write-Output 'Windows continuous reflow checks passed.'
} finally {$window.Dispose()}
