param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $root 'windows\Load-TaskbarWidget.ps1')
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$widget = [TokcatTaskbarWidget]::new()
try {
    $widget.SetMetricColumns(
        [string[]]@('running', 'waiting', 'completed', 'running', 'running'),
        [string[]]@('Output', 'Weekly', 'Upload', 'Download'),
        @{ Output='209 tok/s'; Weekly='38%'; Upload='32 K/s'; Download='1.2 M/s' }
    )
    foreach ($theme in @('light', 'dark')) {
        $light = $theme -eq 'light'
        $background = if ($light) { '#EEF4F8' } else { '#141B24' }
        $panel = if ($light) { '#FFFFFF' } else { '#222D3A' }
        $foreground = if ($light) { '#172C40' } else { '#F0F5FA' }
        $secondary = if ($light) { '#3C5A70' } else { '#B0C7D9' }
        $accent = if ($light) { '#16665C' } else { '#8BDCC3' }
        $image = [Drawing.Bitmap]::new(1320, 400)
        $graphics = [Drawing.Graphics]::FromImage($image)
        $strip = $widget.RenderPreview(288, $light)
        try {
            $graphics.SmoothingMode = 'AntiAlias'
            $graphics.TextRenderingHint = 'AntiAliasGridFit'
            $graphics.Clear([Drawing.ColorTranslator]::FromHtml($background))
            function Draw-Text([string]$Text, [int]$X, [int]$Y, [int]$Size, [string]$Color, [bool]$Bold = $false) {
                $weight = if ($Bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
                $font = [Drawing.Font]::new('Segoe UI', [single]$Size, $weight, [Drawing.GraphicsUnit]::Pixel)
                $brush = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($Color))
                try { $graphics.DrawString($Text, $font, $brush, [single]$X, [single]$Y) }
                finally { $font.Dispose(); $brush.Dispose() }
            }
            Draw-Text 'tokcat  /  WINDOWS TASKBAR' 60 42 24 $accent $true
            $card = [Drawing.Drawing2D.GraphicsPath]::new()
            $fill = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($panel))
            try {
                $card.AddArc(64, 102, 48, 48, 180, 90)
                $card.AddArc(1208, 102, 48, 48, 270, 90)
                $card.AddArc(1208, 242, 48, 48, 0, 90)
                $card.AddArc(64, 242, 48, 48, 90, 90)
                $card.CloseFigure()
                $graphics.FillPath($fill, $card)
                $graphics.DrawImageUnscaled($strip, [int](660 - $strip.Width / 2), [int](196 - $strip.Height / 2))
            } finally { $fill.Dispose(); $card.Dispose() }
            Draw-Text 'Task status' 64 319 24 $foreground $true
            Draw-Text 'One dot per task' 64 353 19 $secondary
            Draw-Text 'Output and quota' 448 319 24 $foreground $true
            Draw-Text 'Total tok/s above weekly quota' 448 353 19 $secondary
            Draw-Text 'Network' 890 319 24 $foreground $true
            Draw-Text 'Upload above download' 890 353 19 $secondary
            $image.Save((Join-Path $OutputDirectory ('taskbar-' + $theme + '.png')), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $strip.Dispose(); $graphics.Dispose(); $image.Dispose() }
    }
} finally { $widget.Dispose() }
