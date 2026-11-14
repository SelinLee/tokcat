$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Launcher.ps1')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TokcatPointerTestNative {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr handle,out Rect rectangle);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr handle);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr handle);
}
'@
function Assert-Pointer($condition,[string]$message) { if(-not $condition) { throw $message } }
function Wait-Pointer($predicate,[string]$message) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while($clock.ElapsedMilliseconds -lt 3000) { if(& $predicate) { return }; Start-Sleep -Milliseconds 5 }
    throw $message
}
$image=[Drawing.Bitmap]::new(96,96,[Drawing.Imaging.PixelFormat]::Format32bppPArgb)
$graphics=[Drawing.Graphics]::FromImage($image)
try { $graphics.Clear([Drawing.Color]::Transparent); $graphics.FillEllipse([Drawing.Brushes]::DarkCyan,12,12,72,72) } finally { $graphics.Dispose() }
$follower=[TokcatLauncherPointerFollower]::new($false)
try {
    $follower.Update($image,[Drawing.Point]::new(100,100),[IntPtr]::Zero)
    Wait-Pointer { -not $follower.Bounds.IsEmpty } 'The independent surface did not present.'
    Assert-Pointer ($follower.NativeThreadId -ne [Threading.Thread]::CurrentThread.ManagedThreadId) 'The visible wheel must have its own message pump.'
    $handle=$follower.Handle
    $area=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $point=[Drawing.Point]::new($area.Left+$area.Width/2,$area.Top+$area.Height/2)
    $before=$follower.NativeMoveCount
    foreach($offset in 1..200) { $follower.PublishPointer([Drawing.Point]::new($point.X+$offset,$point.Y)) }
    # Deliberately do NOT pump the main STA. The old WM_TIMER path cannot move
    # its window during this stall; the real native HWND must still get there.
    [Threading.Thread]::Sleep(250)
    $wanted=[Drawing.Point]::new([Math]::Min($area.Right-96,$point.X+200-48),[Math]::Min($area.Bottom-96,$point.Y-48))
    $actual=[TokcatPointerTestNative+Rect]::new()
    Assert-Pointer ([TokcatPointerTestNative]::GetWindowRect($handle,[ref]$actual)) 'The presented HWND must remain valid.'
    Assert-Pointer ($actual.Left -eq $wanted.X -and $actual.Top -eq $wanted.Y -and $follower.NativeMoveCount -gt $before) 'The real wheel must follow the latest mouse position even when the main UI is blocked for 250 ms.'
    Assert-Pointer ($follower.LastMoveLatencyMilliseconds -lt 80) ('The follower waited for the stalled main UI: '+$follower.LastMoveLatencyMilliseconds+' ms.')
    Write-Output ('Independent pointer update with main UI blocked: '+[Math]::Round($follower.LastMoveLatencyMilliseconds,2)+' ms.')
    $latencies=[Collections.Generic.List[double]]::new()
    $sampler=[TokcatRadialBackdropCapture]::new(); $sampler.Begin()
    try {
        foreach($offset in 1..20) {
            $sampler.Enqueue($follower.Bounds,[Windows.Forms.SystemInformation]::VirtualScreen,[Drawing.Color]::Gray,[IntPtr[]]@($handle),$true)
            $previous=$follower.NativeMoveCount
            $follower.PublishPointer([Drawing.Point]::new($point.X+$offset,$point.Y+$offset))
            Wait-Pointer { $follower.NativeMoveCount -gt $previous } 'A native mouse update was lost during background sampling.'
            $latencies.Add($follower.LastMoveLatencyMilliseconds)
        }
    } finally { $sampler.Stop();$sampler.Dispose() }
    $sorted=@($latencies | Sort-Object)
    Write-Output ('Pointer delivery during background sampling median: '+[Math]::Round($sorted[$sorted.Count/2],2)+' ms; p95: '+[Math]::Round($sorted[18],2)+' ms.')
    $follower.SetFollowing($false); Start-Sleep -Milliseconds 20
    $frozen=$follower.Bounds
    $follower.PublishPointer([Drawing.Point]::new($point.X+300,$point.Y+200)); Start-Sleep -Milliseconds 20
    Assert-Pointer ($follower.Bounds -eq $frozen) 'Keyboard/aiming freeze stops native following immediately.'
    $follower.Hide()
    Wait-Pointer { -not [TokcatPointerTestNative]::IsWindowVisible($handle) } 'Hiding must hide the independent HWND.'
} finally { $follower.Dispose() }
Wait-Pointer { -not [TokcatPointerTestNative]::IsWindow($handle) } 'Disposal must close the presentation thread window.'

$nativeInput=[TokcatLauncherPointerFollower]::new()
try {
    $nativeInput.Update($image,[Drawing.Point]::new(100,100),[IntPtr]::Zero)
    Wait-Pointer { $nativeInput.MouseHookActive } 'The real mouse event hook did not start.'
    $nativeInput.Hide()
    Wait-Pointer { -not $nativeInput.MouseHookActive } 'Closing the wheel must release the mouse hook.'
} finally { $nativeInput.Dispose(); $image.Dispose() }
Write-Output 'Windows independent mouse-following checks passed.'
