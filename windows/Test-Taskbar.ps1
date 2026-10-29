param([switch]$RealTaskbar)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Load-TaskbarWidget.ps1')
function Assert-Taskbar($Value, [string]$Message) { if (-not $Value) { throw $Message } }
$bar = New-Object Drawing.Rectangle(-1200,900,1200,48)
$occupied = [Drawing.Rectangle[]]@((New-Object Drawing.Rectangle(-800,900,300,48)), (New-Object Drawing.Rectangle(-160,900,160,48)))
$slot = [TokcatTaskbarWidget]::FindSlot($bar,$occupied,300,200,8)
Assert-Taskbar ($bar.Contains($slot) -and $slot.Width -eq 300) 'Taskbar slot must stay inside a negative-origin monitor.'
foreach ($button in $occupied) { Assert-Taskbar (-not $slot.IntersectsWith($button)) 'Taskbar slot overlaps buttons.' }
Assert-Taskbar ([TokcatTaskbarWidget]::FindSlot($bar, [Drawing.Rectangle[]]@($bar),300,200,8).IsEmpty) 'A full taskbar must not be covered.'
Assert-Taskbar ([TokcatTaskbarWidget]::FindSlot((New-Object Drawing.Rectangle(0,0,48,1000)), @(),300,200,8).IsEmpty) 'A vertical taskbar must report unsupported layout.'
$scaledBar=New-Object Drawing.Rectangle(0,0,2000,96)
$scaledSlot=[TokcatTaskbarWidget]::FindSlot($scaledBar,[Drawing.Rectangle[]]@((New-Object Drawing.Rectangle(1600,0,400,96))),960,540,16)
Assert-Taskbar ($scaledSlot.Width -eq 960 -and $scaledBar.Contains($scaledSlot) -and $scaledSlot.Right -lt 1600) 'Scaled placement must leave room for the tray.'
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class TokcatTaskbarTestInput { [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int message, IntPtr w, IntPtr l); }'
$hostForm = New-Object Windows.Forms.Form
$hostForm.FormBorderStyle='None'; $hostForm.Size=New-Object Drawing.Size(1000,48); $hostForm.ShowInTaskbar=$false
$widget = New-Object TokcatTaskbarWidget
try {
    $hostForm.Show(); $widget.AttachForTest($hostForm.Handle,(New-Object Drawing.Rectangle(500,0,300,48)))
    $widget.SetContent(@('running','waiting'), 'tokcat test', 'CPU 10%  MEM 20%')
    $script:taskbarClicked=$false; $widget.Add_Clicked({ $script:taskbarClicked=$true })
    [Windows.Forms.Application]::DoEvents()
    Assert-Taskbar ($widget.ParentHandle -eq $hostForm.Handle -and $widget.Visible) 'Widget must be a visible child of its host.'
    Assert-Taskbar ([TokcatTaskbarWidget]::Caption($widget.Handle).Contains('CPU 10%')) 'Taskbar metrics must be exposed as accessible window text.'
    [void][TokcatTaskbarTestInput]::SendMessage($widget.Handle,0x0202,[IntPtr]::Zero,[IntPtr]::Zero)
    Assert-Taskbar $script:taskbarClicked 'Clicking the taskbar widget must raise the details action.'
    $widget.SetMetrics(@('running','waiting','failed','completed','stalled','approval'),'17.0 tok/s','5h 80% / week 40%','15K/s','161K/s',$null,$null,$null)
    Assert-Taskbar ($widget.PreferredWidth(96) -lt 300) 'Default metrics must size tightly to their content.'
    Assert-Taskbar (-not [TokcatTaskbarWidget]::Caption($widget.Handle).Contains('CPU')) 'CPU must be omitted when disabled.'
    $preview=$widget.RenderPreview(96)
    try {
        Assert-Taskbar ($preview.GetPixel(0,0).A -eq 0) 'The taskbar background must be transparent.'
        Assert-Taskbar ($preview.GetPixel(6,8).ToArgb() -eq [Drawing.Color]::Goldenrod.ToArgb()) 'First dot must start the first vertical column.'
        Assert-Taskbar ($preview.GetPixel(6,24).ToArgb() -eq [Drawing.Color]::OrangeRed.ToArgb()) 'Second dot must be below the first dot.'
        Assert-Taskbar ($preview.GetPixel(17,8).ToArgb() -eq [Drawing.Color]::ForestGreen.ToArgb()) 'Fourth dot must start the second column.'
        $preview.Save((Join-Path $env:TEMP 'tokcat-taskbar-preview.png'),[Drawing.Imaging.ImageFormat]::Png)
    } finally { $preview.Dispose() }
    $widget.SetEnabled($false)
    Assert-Taskbar (-not $widget.Visible) 'Disabling the taskbar widget must hide it.'
    $hostForm.Close(); $hostForm.Dispose()
    $hostForm = New-Object Windows.Forms.Form; $hostForm.Size=New-Object Drawing.Size(1000,48); $hostForm.ShowInTaskbar=$false; $hostForm.Show()
    $widget.AttachForTest($hostForm.Handle,(New-Object Drawing.Rectangle(500,0,300,40)))
    Assert-Taskbar ($widget.ParentHandle -eq $hostForm.Handle) 'Widget must recover when the previous host is destroyed.'
} finally { $widget.Dispose(); $hostForm.Dispose() }
if ($RealTaskbar) {
    Assert-Taskbar ([TokcatTaskbarWidget]::PrimaryTaskbar -ne [IntPtr]::Zero) 'Explorer taskbar is not available.'
    $widget = New-Object TokcatTaskbarWidget
    $tick = New-Object Windows.Forms.Timer; $tick.Interval=300
    $context = New-Object Windows.Forms.ApplicationContext
    $deadline = [datetimeoffset]::UtcNow.AddSeconds(12); $outcome = [pscustomobject]@{ Passed=$false; Status='' }
    $tick.Add_Tick({
        $widget.RefreshAttachment()
        if ($widget.Embedded) {
            $outcome.Passed = [TokcatTaskbarWidget]::TaskbarBounds.Contains($widget.WindowBounds) -and -not $widget.OverlapsButtons
            $outcome.Status = $widget.Status; $tick.Stop(); $context.ExitThread()
        } elseif ([datetimeoffset]::UtcNow -gt $deadline) { $outcome.Status=$widget.Status; $tick.Stop(); $context.ExitThread() }
    })
    try {
        $widget.SetContent(@('running','waiting'),'tokcat taskbar test','CPU 10%  MEM 20%'); $widget.SetEnabled($true); $tick.Start()
        [Windows.Forms.Application]::Run($context)
        Assert-Taskbar $outcome.Passed ('Real taskbar embedding failed: ' + $outcome.Status)
        Write-Output ('Explorer taskbar child verified: ' + $widget.WindowBounds)
    } finally { $tick.Dispose(); $widget.Dispose(); $context.Dispose() }
}
Write-Output 'Taskbar embedding checks passed.'
