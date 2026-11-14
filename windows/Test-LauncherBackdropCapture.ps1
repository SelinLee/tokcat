$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Launcher.ps1')
function Assert-Backdrop($condition,[string]$message) { if(-not $condition) { throw $message } }
function Wait-Backdrop($capture,[int]$expectedX) {
    $deadline=[Diagnostics.Stopwatch]::StartNew()
    while($deadline.ElapsedMilliseconds -lt 3000) {
        $frame=$capture.TakeLatest()
        if($frame) { if($frame.Bounds.X -eq $expectedX) { return $frame }; $frame.Dispose() }
        Start-Sleep -Milliseconds 5
    }
    throw ('Background sampler did not deliver the newest request: '+$capture.LastError)
}
$black=[TokcatRadialBackdropCapture+Frame]::new([Drawing.Color]::Black,[Drawing.Rectangle]::new(0,0,100,100))
$white=[TokcatRadialBackdropCapture+Frame]::new([Drawing.Color]::White,[Drawing.Rectangle]::new(0,0,100,100))
Assert-Backdrop ($black.Luminance -eq 0 -and [Math]::Abs($white.Luminance-1) -lt 0.0001) 'Coarse colors retain reliable automatic text contrast.'
Assert-Backdrop ($null -eq $black.GetType().GetField('Image')) 'Published samples retain an average color, never a detailed desktop image.'
$capture=[TokcatRadialBackdropCapture]::new()
try {
    $capture.Begin()
    $screen=[Windows.Forms.SystemInformation]::VirtualScreen
    foreach($i in 0..200) { $capture.Enqueue([Drawing.Rectangle]::new($screen.Left+$i,$screen.Top,200,200),$screen,[Drawing.Color]::Black,[IntPtr[]]@(),$true) }
    $latest=Wait-Backdrop $capture ($screen.Left+200)
    Assert-Backdrop ($latest.Bounds.X -eq $screen.Left+200) 'A burst of motion coalesces into the newest request without building a frame queue.'
    $latest.Dispose()
    $workerField=$capture.GetType().GetField('worker',[Reflection.BindingFlags]'Instance,NonPublic')
    Assert-Backdrop ($workerField.GetValue($capture).ManagedThreadId -ne [Threading.Thread]::CurrentThread.ManagedThreadId) 'Desktop reads stay off the UI thread.'
    $capture.Enqueue([Drawing.Rectangle]::new($screen.Left+300,$screen.Top,200,200),$screen,[Drawing.Color]::Black,[IntPtr[]]@(),$true)
    $capture.Stop(); Start-Sleep -Milliseconds 100
    Assert-Backdrop ($null -eq $capture.TakeLatest()) 'Closing the launcher discards pending and late samples.'
    $capture.Begin()
    $capture.Enqueue([Drawing.Rectangle]::new($screen.Left+400,$screen.Top,200,200),$screen,[Drawing.Color]::Black,[IntPtr[]]@(),$true)
    $latest=Wait-Backdrop $capture ($screen.Left+400); $latest.Dispose()
    $capture.Stop()
} finally { $capture.Dispose() }

# Regression for the slow path: pointer motion and a new fog color reuse the
# circular mask, glow and curved text instead of rebuilding them every frame.
$palette=[Drawing.Color[]]@([Drawing.Color]::Black,[Drawing.Color]::FromArgb(32,35,40),[Drawing.Color]::White,[Drawing.Color]::Silver,[Drawing.Color]::DarkCyan)
$window=[TokcatLauncherWindow]::new($palette); $window.IsPreview=$true
try {
    $window.Appearance.Configure('radial',$false); $window.Query.Text='applications'
    $window.SetResults([TokcatLauncherResult[]]@(0..8 | ForEach-Object {[TokcatLauncherResult]@{Title=('Application '+$_);Kind='settings';Key=('performance:'+$_)}}),'')
    $window.Radial.Motion.Finish()
    $frame=$window.Radial.Render(); $frame.Dispose()
    $masks=$window.Radial.MaskBuildCount; $content=$window.Radial.ContentBuildCount
    $source=[Drawing.Bitmap]::new($window.Width,$window.Height)
    try {
        $graphics=[Drawing.Graphics]::FromImage($source)
        try { $graphics.Clear([Drawing.Color]::FromArgb(40,90,100)) } finally { $graphics.Dispose() }
        $window.Appearance.UsePreviewBackground($source)
    } finally { $source.Dispose() }
    $times=[Collections.Generic.List[double]]::new()
    foreach($iteration in 1..20) {
        $window.Location=[Drawing.Point]::new($iteration*2,$iteration)
        $watch=[Diagnostics.Stopwatch]::StartNew(); $frame=$window.Radial.Render(); $frame.Dispose(); $watch.Stop()
        $times.Add($watch.Elapsed.TotalMilliseconds)
    }
    Assert-Backdrop ($window.Radial.MaskBuildCount -eq $masks -and $window.Radial.ContentBuildCount -eq $content) 'Background and position changes reuse the cached mask and contents.'
    $ordered=@($times | Sort-Object); $median=$ordered[$ordered.Count/2]
    Assert-Backdrop ($median -lt 25) ('A settled 450-pixel wheel must stay below 25 ms per frame; observed '+[Math]::Round($median,2)+' ms.')
    Write-Output ('450 px cached render median: '+[Math]::Round($median,2)+' ms.')
} finally { $window.Dispose() }
Write-Output 'Windows lightweight backdrop checks passed.'
