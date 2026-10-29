param([switch]$RealTaskbar)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Load-TaskbarWidget.ps1')
function Assert-Taskbar($Value, [string]$Message) { if (-not $Value) { throw $Message } }
$font = [TokcatTaskbarWidget]::CreateTextFont(96)
try { Assert-Taskbar ($font.Bold -and [math]::Abs($font.SizeInPoints - 9) -lt 0.1) 'Taskbar typography must use the larger bold 9-point font.' } finally { $font.Dispose() }
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
Add-Type -ReferencedAssemblies System.Drawing.dll -TypeDefinition 'using System; using System.Drawing; public static class TokcatTaskbarTestPixels { public static int[] Ink(Bitmap b,int left,int right) { int top=b.Height,bottom=-1; for(int y=0;y<b.Height;y++) for(int x=left;x<right;x++) if(b.GetPixel(x,y).A>0) {top=Math.Min(top,y);bottom=Math.Max(bottom,y);break;} return new int[]{top,bottom}; } public static int[] ColorRows(Bitmap b,int color) {int top=b.Height,bottom=-1;for(int y=0;y<b.Height;y++) for(int x=0;x<b.Width;x++) if(b.GetPixel(x,y).ToArgb()==color){top=Math.Min(top,y);bottom=Math.Max(bottom,y);break;}return new int[]{top,bottom};} public static bool SameRight(Bitmap a,Bitmap b,int width) {if(a.Size!=b.Size) return false;for(int y=0;y<a.Height;y++)for(int x=a.Width-width;x<a.Width;x++)if(a.GetPixel(x,y)!=b.GetPixel(x,y))return false;return true;} }'
$hostForm = New-Object Windows.Forms.Form
$hostForm.FormBorderStyle='None'; $hostForm.Size=New-Object Drawing.Size(1000,48); $hostForm.ShowInTaskbar=$false
$widget = New-Object TokcatTaskbarWidget
$quotaSample = '5h ' + [char]0x2014 + ' / ' + [char]0x5468 + ' 39%'
try {
    $hostForm.Show(); $widget.AttachForTest($hostForm.Handle,(New-Object Drawing.Rectangle(500,0,300,48)))
    $widget.SetContent(@('running','waiting'), 'tokcat test', 'CPU 10%  MEM 20%')
    $script:taskbarClicked=$false; $widget.Add_Clicked({ $script:taskbarClicked=$true })
    [Windows.Forms.Application]::DoEvents()
    Assert-Taskbar ($widget.ParentHandle -eq $hostForm.Handle -and $widget.Visible) 'Widget must be a visible child of its host.'
    Assert-Taskbar ([TokcatTaskbarWidget]::Caption($widget.Handle).Contains('CPU 10%')) 'Taskbar metrics must be exposed as accessible window text.'
    [void][TokcatTaskbarTestInput]::SendMessage($widget.Handle,0x0202,[IntPtr]::Zero,[IntPtr]::Zero)
    Assert-Taskbar $script:taskbarClicked 'Clicking the taskbar widget must raise the details action.'
    $widget.SetMetrics(@('running','waiting','failed','completed','stalled','approval'),'17.0 tok/s',$quotaSample,'15 K/s','161 K/s',$null,$null,$null)
    Assert-Taskbar ($widget.PreferredWidth(96) -lt 220) 'Default metrics must keep the compact reference layout.'
    Assert-Taskbar (-not [TokcatTaskbarWidget]::Caption($widget.Handle).Contains('CPU')) 'CPU must be omitted when disabled.'
    $stableWidth=$widget.PreferredWidth(96)
    $widget.SetMetrics(@('running','waiting','failed','completed','stalled','approval'),'17.0 tok/s',$quotaSample,'999 M/s','0 K/s',$null,$null,$null)
    Assert-Taskbar ($widget.PreferredWidth(96) -eq $stableWidth) 'Network digit changes must not move other columns.'
    $widget.SetMetrics(@('running','waiting','failed','completed','stalled','approval'),'17.0 tok/s',$quotaSample,'10.5 G/s','1 M/s',$null,$null,$null)
    Assert-Taskbar ($widget.PreferredWidth(96) -eq $stableWidth) 'Network unit changes must not resize the widget.'
    $widget.SetMetrics(@('running','waiting','failed','completed','stalled','approval'),'17.0 tok/s',$quotaSample,'15 K/s','161 K/s',$null,$null,$null)
    $preview=$widget.RenderPreview(96)
    try {
        Assert-Taskbar ($preview.GetPixel(0,0).A -eq 0) 'The taskbar background must be transparent.'
        $textRows=[TokcatTaskbarTestPixels]::Ink($preview,29,$preview.Width)
        $dotRows=[TokcatTaskbarTestPixels]::Ink($preview,0,25)
        Assert-Taskbar ($dotRows[0] -eq $textRows[0] -and $dotRows[1] -eq $textRows[1]) ('Dot-group edges must align with text: dots ' + ($dotRows -join ',') + '; text ' + ($textRows -join ','))
        $firstRows=[TokcatTaskbarTestPixels]::ColorRows($preview,[Drawing.Color]::Goldenrod.ToArgb())
        $secondRows=[TokcatTaskbarTestPixels]::ColorRows($preview,[Drawing.Color]::OrangeRed.ToArgb())
        $fourthRows=[TokcatTaskbarTestPixels]::ColorRows($preview,[Drawing.Color]::ForestGreen.ToArgb())
        Assert-Taskbar (($firstRows[1]-$firstRows[0]+1) -ge 7) 'Status dots must use the larger diameter.'
        Assert-Taskbar ($secondRows[0] -gt $firstRows[1]) 'Second dot must be below the first dot.'
        Assert-Taskbar ($fourthRows[0] -eq $firstRows[0]) 'Fourth dot must start the second column.'
        Assert-Taskbar ([TokcatTaskbarWidget]::Caption($widget.Handle).Contains('15 K/s')) 'Network values and units must have a separating space.'
        $preview.Save((Join-Path $env:TEMP 'tokcat-taskbar-preview.png'),[Drawing.Imaging.ImageFormat]::Png)
    } finally { $preview.Dispose() }
    $before=$widget.RenderPreview(96)
    $widget.SetDotDimming(@($true,$true,$true,$true,$true,$true)); $dimmedPreview=$widget.RenderPreview(96)
    try {
        Assert-Taskbar (-not [TokcatTaskbarTestPixels]::SameRight($before,$dimmedPreview,$before.Width)) 'Reminder flashing must visibly dim the dots.'
        Assert-Taskbar ([TokcatTaskbarTestPixels]::SameRight($before,$dimmedPreview,$before.Width-29)) 'Dot flashing must leave metric positions and glyphs unchanged.'
    } finally { $dimmedPreview.Dispose(); $widget.SetDotDimming(@()) }
    $widget.SetMetrics(@('running','waiting','failed','completed','stalled','approval'),'17.0 tok/s',$quotaSample,'0.3 K/s','999 K/s',$null,$null,$null)
    $after=$widget.RenderPreview(96); $font=[TokcatTaskbarWidget]::CreateTextFont(96); $surface=New-Object Drawing.Bitmap(1,1); $graphics=[Drawing.Graphics]::FromImage($surface)
    try {
        $flags=[Windows.Forms.TextFormatFlags]::NoPadding -bor [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::NoPrefix
        $unitWidth=0; foreach($unit in @('K/s','M/s','G/s')) { $unitWidth=[math]::Max($unitWidth,[Windows.Forms.TextRenderer]::MeasureText($graphics,$unit,$font,[Drawing.Size]::Empty,$flags).Width) }
        Assert-Taskbar ([TokcatTaskbarTestPixels]::SameRight($before,$after,$unitWidth+2)) 'Rendered unit positions must stay fixed as numeric widths change.'
        $unitRows=[TokcatTaskbarTestPixels]::Ink($after,$after.Width-$unitWidth-2,$after.Width-2)
        Assert-Taskbar ($unitRows[1] -gt $unitRows[0]) 'The fixed unit region must contain visible glyphs.'
    } finally { $before.Dispose(); $after.Dispose(); $font.Dispose(); $graphics.Dispose(); $surface.Dispose() }
    $widget.SetMetrics(@('running','completed'),'17.0 tok/s','5h 80%','15 K/s','161 K/s',$null,$null,$null)
    $preview=$widget.RenderPreview(96)
    try {
        $textRows=[TokcatTaskbarTestPixels]::Ink($preview,18,$preview.Width); $dotRows=[TokcatTaskbarTestPixels]::Ink($preview,0,14)
        Assert-Taskbar ($dotRows[0] -eq $textRows[0] -and $dotRows[1] -eq $textRows[1]) 'Two dots must align with the top and bottom text edges.'
    } finally { $preview.Dispose() }
    foreach ($dpi in @(144,192)) {
        $preview=$widget.RenderPreview($dpi); $scale=$dpi/96.0
        try {
            $textRows=[TokcatTaskbarTestPixels]::Ink($preview,[int](18*$scale),$preview.Width); $dotRows=[TokcatTaskbarTestPixels]::Ink($preview,0,[int](14*$scale))
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
