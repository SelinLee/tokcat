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
Add-Type -ReferencedAssemblies System.Drawing.dll -TypeDefinition 'using System; using System.Drawing; public static class TokcatTaskbarTestPixels { public static int[] Ink(Bitmap b,int left,int right) { int top=b.Height,bottom=-1; for(int y=0;y<b.Height;y++) for(int x=left;x<right;x++) if(b.GetPixel(x,y).A>0) {top=Math.Min(top,y);bottom=Math.Max(bottom,y);break;} return new int[]{top,bottom}; } public static int[] ColorRows(Bitmap b,int color) {int top=b.Height,bottom=-1;for(int y=0;y<b.Height;y++) for(int x=0;x<b.Width;x++) if(b.GetPixel(x,y).ToArgb()==color){top=Math.Min(top,y);bottom=Math.Max(bottom,y);break;}return new int[]{top,bottom};} }'
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
    $widget.SetMetrics(@('running','waiting','failed','completed','stalled','approval'),'17.0 tok/s','5h 80% / week 40%','15 K/s','161 K/s',$null,$null,$null)
    Assert-Taskbar ($widget.PreferredWidth(96) -lt 300) 'Default metrics must size tightly to their content.'
    Assert-Taskbar (-not [TokcatTaskbarWidget]::Caption($widget.Handle).Contains('CPU')) 'CPU must be omitted when disabled.'
    $preview=$widget.RenderPreview(96)
    try {
        Assert-Taskbar ($preview.GetPixel(0,0).A -eq 0) 'The taskbar background must be transparent.'
        $textRows=[TokcatTaskbarTestPixels]::Ink($preview,31,$preview.Width)
        $dotRows=[TokcatTaskbarTestPixels]::Ink($preview,0,25)
        Assert-Taskbar ($dotRows[0] -eq $textRows[0] -and $dotRows[1] -eq $textRows[1]) ('Dot-group edges must align with text: dots ' + ($dotRows -join ',') + '; text ' + ($textRows -join ','))
        $firstRows=[TokcatTaskbarTestPixels]::ColorRows($preview,[Drawing.Color]::Goldenrod.ToArgb())
        $secondRows=[TokcatTaskbarTestPixels]::ColorRows($preview,[Drawing.Color]::OrangeRed.ToArgb())
        $fourthRows=[TokcatTaskbarTestPixels]::ColorRows($preview,[Drawing.Color]::ForestGreen.ToArgb())
        Assert-Taskbar ($secondRows[0] -gt $firstRows[1]) 'Second dot must be below the first dot.'
        Assert-Taskbar ($fourthRows[0] -eq $firstRows[0]) 'Fourth dot must start the second column.'
        Assert-Taskbar ([TokcatTaskbarWidget]::Caption($widget.Handle).Contains('15 K/s')) 'Network values and units must have a separating space.'
        $preview.Save((Join-Path $env:TEMP 'tokcat-taskbar-preview.png'),[Drawing.Imaging.ImageFormat]::Png)
    } finally { $preview.Dispose() }
    $widget.SetMetrics(@('running','completed'),'17.0 tok/s','5h 80%','15 K/s','161 K/s',$null,$null,$null)
    $preview=$widget.RenderPreview(96)
    try {
        $textRows=[TokcatTaskbarTestPixels]::Ink($preview,20,$preview.Width); $dotRows=[TokcatTaskbarTestPixels]::Ink($preview,0,14)
        Assert-Taskbar ($dotRows[0] -eq $textRows[0] -and $dotRows[1] -eq $textRows[1]) 'Two dots must align with the top and bottom text edges.'
    } finally { $preview.Dispose() }
    foreach ($dpi in @(144,192)) {
        $preview=$widget.RenderPreview($dpi); $scale=$dpi/96.0
        try {
            $textRows=[TokcatTaskbarTestPixels]::Ink($preview,[int](20*$scale),$preview.Width); $dotRows=[TokcatTaskbarTestPixels]::Ink($preview,0,[int](14*$scale))
            Assert-Taskbar ($dotRows[0] -eq $textRows[0] -and $dotRows[1] -eq $textRows[1]) 'Scaled dot edges must align with the text.'
        } finally { $preview.Dispose() }
    }
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
