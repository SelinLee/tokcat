param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\ui-preview'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'Load-TaskbarWidget.ps1')
Add-Type -Path (Join-Path $PSScriptRoot 'DesktopUi.cs') -ReferencedAssemblies @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location)
[Windows.Forms.Application]::EnableVisualStyles()
$window = New-Object TokcatMainWindow
try {
    $window.SetTotals(2,1,1,0)
    $fixtures = @(
        @('waiting','等待回答','Claude Code','确认界面优化方案','C:\Projects\tokcat','等待回答','claude-opus'),
        @('running','运行中','Codex','统一 Windows 功能图标','C:\Projects\tokcat','编辑文件','gpt-5.6-sol'),
        @('running','运行中','WorkBuddy','检查本地使用记录','C:\Projects\demo','读取记录','deepseek'),
        @('completed','本轮结束','Codex','更新用量统计布局','C:\Projects\tokcat','本轮完成','gpt-5.6-sol')
    )
    foreach ($fixture in $fixtures) {
        $item = New-Object Windows.Forms.ListViewItem($fixture[1]); $item.ImageKey = $fixture[0]
        foreach ($value in $fixture[2..6] + @('1,240','23.6','2026-10-31 12:00:00')) { [void]$item.SubItems.Add($value) }
        [void]$window.Sessions.Items.Add($item)
    }
    $window.SetResults(4,4)
    $window.SetSelection('统一 Windows 功能图标', "Codex · 运行中 · gpt-5.6-sol · 编辑文件`nC:\Projects\tokcat", 'running')
    $window.Quota.Text = 'Codex 本地额度：5h 82% · 周 65%'
    $window.Note.Text = "CPU 12% · GPU — · 内存 48% · 网络 ↓ 842 KiB/s ↑ 24 KiB/s`n预览使用示例任务，不读取任何本地 Agent 记录。"
    $window.Taskbar.Checked = $true
    [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    $window.Show(); [Windows.Forms.Application]::DoEvents()
    foreach ($page in @('tasks','settings')) {
        $window.ShowSettings($page -eq 'settings'); [Windows.Forms.Application]::DoEvents()
        $bitmap = New-Object Drawing.Bitmap($window.Width, $window.Height)
        try {
            $window.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0,0,$window.Width,$window.Height)))
            $path = Join-Path $OutputDirectory ($page + '.png')
            $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
            Write-Output $path
        } finally { $bitmap.Dispose() }
    }
} finally { $window.Close(); $window.Dispose() }
