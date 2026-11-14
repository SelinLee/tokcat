param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\launcher-preview'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Load-Launcher.ps1')
[Windows.Forms.Application]::EnableVisualStyles()
[void][IO.Directory]::CreateDirectory($OutputDirectory)
foreach ($theme in @('light','dark')) {
    $isLight=$theme -eq 'light'
    $palette=if($isLight) { [Drawing.Color[]]@([Drawing.Color]::WhiteSmoke,[Drawing.Color]::White,[Drawing.Color]::Black,[Drawing.Color]::Gray,[Drawing.Color]::AliceBlue) } else { [Drawing.Color[]]@([Drawing.Color]::FromArgb(24,26,30),[Drawing.Color]::FromArgb(32,35,40),[Drawing.Color]::WhiteSmoke,[Drawing.Color]::Silver,[Drawing.Color]::FromArgb(48,64,67)) }
    $background=[Windows.Forms.Form]::new()
    $background.FormBorderStyle='None'; $background.ShowInTaskbar=$false; $background.TopMost=$true
    $background.StartPosition='CenterScreen'; $background.ClientSize=[Drawing.Size]::new(760,620)
    $background.BackColor=$palette[1]
    $background.add_Paint({ param($sender,$e)
        $brush=[Drawing.Drawing2D.LinearGradientBrush]::new($sender.ClientRectangle,$sender.BackColor,[Drawing.Color]::FromArgb(95,150,155),35.0)
        try { $e.Graphics.FillRectangle($brush,$sender.ClientRectangle) } finally { $brush.Dispose() }
    })
    $window=[TokcatLauncherWindow]::new($palette)
    try {
        $background.Show(); [Windows.Forms.Application]::DoEvents()
        foreach ($skin in @('classic','cyber','radial')) {
            foreach ($mode in @('empty','applications','translation','definition','calculation')) {
                $window.Hide(); $window.IsPreview=$false; $window.Appearance.Configure($skin,$true)
                $window.Location=[Drawing.Point]::new($background.Left+80,$background.Top+90)
                switch($mode) {
                    empty { $window.Query.Text=''; $window.SetResults([TokcatLauncherResult[]]@(),'') }
                    applications {
                        $window.Query.Text='应用'
                        $window.SetResults([TokcatLauncherResult[]]@(
                            [TokcatLauncherResult]@{Title='记事本';Detail='应用';Kind='application';Key='preview:notepad';RadialWeight=2;App=[TokcatLauncherApp]@{Name='记事本';Target=(Join-Path $env:WINDIR 'System32/notepad.exe')}},
                            [TokcatLauncherResult]@{Title='计算器';Detail='应用';Kind='application';Key='preview:calculator';RadialWeight=1.6;App=[TokcatLauncherApp]@{Name='计算器';Target=(Join-Path $env:WINDIR 'System32/calc.exe')}},
                            [TokcatLauncherResult]@{Title='翻译';Detail='查看释义';Kind='translate';Key='translate';RadialWeight=1.8},
                            [TokcatLauncherResult]@{Title='网页搜索';Detail='百度搜索';Kind='website';Key='web-search';RadialWeight=0.25}
                        ),'↑ ↓ ← → 按方位选择 · Enter 执行')
                    }
                    translation {
                        $window.Query.Text='tran+hello world'
                        $settings=[TokcatLauncherSettings]::new()
                        $window.SetResults([TokcatLauncherRanking]::Build($window.Query.Text,$settings,[TokcatLauncherMatch[]]@(),[TokcatEverythingFile[]]@(),$true,$null),'翻译 · ↑↓ 选择 · Enter 打开网页 · 默认方式置顶')
                    }
                    definition { $window.Query.Text='tran+hello'; $window.SetDefinition("hello /həˈləʊ/`r`n你好；喂。用于问候或引起注意。`r`n示例：Hello, world!") }
                    calculation { $window.Query.Text='sqrt(9)+2^3'; $window.SetResults([TokcatLauncherResult[]]@([TokcatLauncherResult]@{Title='11';Detail='计算 · 回车复制结果';Kind='calculation';Value='11';Key='calculator:fixture'}),'Enter 复制结果 · Esc 关闭') }
                }
                if($skin -eq 'radial') { $window.Radial.Navigate([Windows.Forms.Keys]::Up); $window.Location=[Drawing.Point]::new($(if($mode -eq 'definition'){$background.Left+35}else{$background.Left+($background.Width-$window.Width)/2}),$background.Top+($background.Height-$window.Height)/2) }
                $window.Appearance.Prepare(); $window.Show(); $window.Activate(); [void]$window.Query.Focus(); $window.Appearance.Presented()
                [Windows.Forms.Application]::DoEvents()
                if($skin -eq 'radial') {
                    $deadline=[datetimeoffset]::UtcNow.AddMilliseconds(200)
                    while([datetimeoffset]::UtcNow -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
                    # Freeze the displayed frame while any in-flight color
                    # sample restores capture visibility, before taking a PNG.
                    $window.IsPreview=$true
                    $deadline=[datetimeoffset]::UtcNow.AddMilliseconds(75)
                    while([datetimeoffset]::UtcNow -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
                }
                $marginX=if($skin -eq 'cyber'){$window.Appearance.MarginX}else{0}
                $marginY=if($skin -eq 'cyber'){$window.Appearance.MarginY}else{0}
                $captureBounds=[Drawing.Rectangle]::new($window.Left-$marginX,$window.Top-$marginY,$window.Width+2*$marginX,$window.Height+2*$marginY)
                if($skin -eq 'radial' -and -not $window.Radial.DefinitionBounds.IsEmpty) { $captureBounds=[Drawing.Rectangle]::Union($captureBounds,$window.Radial.DefinitionBounds) }
                $image=[Drawing.Bitmap]::new($captureBounds.Width,$captureBounds.Height)
                $graphics=[Drawing.Graphics]::FromImage($image)
                try {
                    $graphics.CopyFromScreen($captureBounds.Location,[Drawing.Point]::Empty,$image.Size)
                    $path=Join-Path $OutputDirectory ($skin+'-'+$theme+'-'+$mode+'.png')
                    $image.Save($path,[Drawing.Imaging.ImageFormat]::Png); Write-Output $path
                } finally { $graphics.Dispose(); $image.Dispose() }
            }
        }
        $window.Hide()
        $settingsWindow=[TokcatLauncherSettingsWindow]::new([TokcatLauncherSettings]::new(),$palette)
        try {
            $settingsWindow.Show(); [Windows.Forms.Application]::DoEvents()
            $tabs=@($settingsWindow.Controls | Where-Object {$_ -is [Windows.Forms.TabControl]})[0]
            foreach($tab in @('通用','网站','翻译')) {
                $tabs.SelectedTab=@($tabs.TabPages | Where-Object Text -eq $tab)[0]
                [Windows.Forms.Application]::DoEvents()
                $image=[Drawing.Bitmap]::new($settingsWindow.Width,$settingsWindow.Height)
                try {
                    $settingsWindow.DrawToBitmap($image,[Drawing.Rectangle]::new([Drawing.Point]::Empty,$image.Size))
                    $path=Join-Path $OutputDirectory ('settings-'+$theme+'-'+$tabs.SelectedIndex+'.png')
                    $image.Save($path,[Drawing.Imaging.ImageFormat]::Png); Write-Output $path
                } finally { $image.Dispose() }
            }
        } finally { $settingsWindow.Dispose() }
    } finally { $window.Dispose(); $background.Dispose() }
}
