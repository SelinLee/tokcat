param([string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }))

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'Monitor.ps1')

$form = New-Object Windows.Forms.Form
$form.Text = 'tokcat · Agent 监控'
$form.Size = New-Object Drawing.Size(980, 500)
$form.MinimumSize = New-Object Drawing.Size(650, 300)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
$form.ShowInTaskbar = $true
$list = New-Object Windows.Forms.ListView
$list.Dock = 'Fill'; $list.View = 'Details'; $list.FullRowSelect = $true; $list.GridLines = $true
foreach ($column in @(@('状态',110),@('来源',130),@('任务',240),@('项目',210),@('阶段',170),@('模型',125),@('输出 tokens',90),@('最后活动',145))) { [void]$list.Columns.Add($column[0], $column[1]) }
$note = New-Object Windows.Forms.Label
$note.Dock = 'Bottom'; $note.Height = 38; $note.Padding = New-Object Windows.Forms.Padding(8,5,0,0)
$note.Text = 'Codex 本地会话 · 双击任务打开日志 · 关闭窗口可保留托盘运行'
$form.Controls.Add($list); $form.Controls.Add($note)
$menu = New-Object Windows.Forms.ContextMenuStrip
$open = $menu.Items.Add('打开监控窗口')
$refresh = $menu.Items.Add('立即刷新')
[void]$menu.Items.Add('-')
$exit = $menu.Items.Add('退出 tokcat')
$tray = New-Object Windows.Forms.NotifyIcon
$tray.ContextMenuStrip = $menu; $tray.Visible = $true
$script:icon = $null; $script:quitting = $false; $script:scanning = $false

function Set-TrayIcon([string]$State, [string]$Text) {
    $color = switch ($State) { 'waiting' { 'OrangeRed' } 'failed' { 'Red' } 'running' { 'Goldenrod' } 'stalled' { 'DarkOrange' } 'completed' { 'ForestGreen' } default { 'Gray' } }
    $bitmap = New-Object Drawing.Bitmap(32,32)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = 'AntiAlias'
    $brush = New-Object Drawing.SolidBrush([Drawing.Color]::FromName($color))
    $graphics.FillEllipse($brush, 2, 2, 28, 28)
    $graphics.DrawEllipse([Drawing.Pens]::White, 2, 2, 28, 28)
    $handle = $bitmap.GetHicon()
    $newIcon = [Drawing.Icon]::FromHandle($handle).Clone()
    if (-not ('Tokcat.Native' -as [type])) { Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace Tokcat { public static class Native { [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h); } }' }
    [void][Tokcat.Native]::DestroyIcon($handle)
    $tray.Icon = $newIcon
    if ($script:icon) { $script:icon.Dispose() }; $script:icon = $newIcon
    $tray.Text = if ($Text.Length -gt 63) { $Text.Substring(0,63) } else { $Text }
    $brush.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}

function Update-Sessions {
    if ($script:scanning) { return }
    $script:scanning = $true
    try {
        $dshHomes = @((Join-Path $env:USERPROFILE '.dsh'), $env:DSH_HOME)
        if ($env:APPDATA) { $dshHomes += @((Join-Path $env:APPDATA 'DSH Desktop\.dsh'), (Join-Path $env:APPDATA 'dsh-desktop\.dsh'), (Join-Path $env:APPDATA '@deepseek-ai\dsh-desktop\.dsh')) }
        $workError = $false
        try { $workSessions = @(Get-WorkSessions $CodexHome) } catch { $workSessions = @(); $workError = $true }
        $sessions = @(@(Get-CodexSessions $CodexHome) + @(Get-DshSessions $dshHomes) + $workSessions | Sort-Object Updated -Descending)
        $counts = @{ running=0; waiting=0; stalled=0; failed=0; completed=0; interrupted=0 }
        $list.BeginUpdate(); $list.Items.Clear()
        foreach ($s in $sessions) {
            $state = $s.State
            if ($s.Source -ne 'Codex Work' -and $state -eq 'running' -and ([datetimeoffset]::UtcNow - $s.Updated).TotalSeconds -ge 120) { $state = 'stalled' }
            if ($counts.ContainsKey($state)) { $counts[$state]++ }
            $label = switch ($state) { 'running' {'运行中'} 'waiting' {'等待回答'} 'stalled' {'长时间无活动'} 'completed' {'本轮结束'} 'failed' {'失败'} 'interrupted' {'中断'} default {'未知'} }
            $row = New-Object Windows.Forms.ListViewItem($label)
            foreach ($value in @($s.Source, $s.Title, $s.Project, $s.Phase, $s.Model, $s.OutputTokens, $s.Updated.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss'))) { [void]$row.SubItems.Add([string]$value) }
            $row.Tag = if ($s.Source -eq 'Codex Work') { $s.Url } else { $s.Path }
            $row.ForeColor = [Drawing.Color]::FromName($(switch ($state) { 'waiting' {'DarkOrange'} 'failed' {'Red'} 'stalled' {'DarkOrange'} 'running' {'DarkGoldenrod'} 'completed' {'ForestGreen'} default {'Gray'} }))
            [void]$list.Items.Add($row)
        }
        $list.EndUpdate()
        $priority = @('waiting','failed','stalled','running','completed') | Where-Object { $counts[$_] -gt 0 } | Select-Object -First 1
        $summary = "tokcat: 运行 $($counts.running) · 等待 $($counts.waiting) · 无活动 $($counts.stalled)"
        Set-TrayIcon $priority $summary
        $form.Text = "tokcat · 运行 $($counts.running) · 等待 $($counts.waiting) · 无活动 $($counts.stalled)"
        $note.Text = "Codex / Work / DeepSeek Harness（最近 7 天）· 共 $($sessions.Count) 项 · 双击打开记录 · 关闭窗口保留托盘" + $(if ($workError) { ' · Work 数据暂不可读' } else { '' })
    } catch {
        $list.EndUpdate()
        $note.Text = '刷新失败：' + $_.Exception.Message
        Set-TrayIcon 'unknown' 'tokcat: 读取失败，请打开窗口查看'
    } finally { $script:scanning = $false }
}

$open.Add_Click({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$refresh.Add_Click({ Update-Sessions })
$exit.Add_Click({ $script:quitting = $true; $form.Close() })
$tray.Add_DoubleClick({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$list.Add_DoubleClick({ if ($list.SelectedItems.Count -gt 0) { $target = [string]$list.SelectedItems[0].Tag; if ($target.StartsWith('https://chatgpt.com/c/')) { Start-Process $target } elseif ($target) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $target + '"') } } })
$form.Add_FormClosing({ param($sender,$e) if (-not $script:quitting -and $e.CloseReason -eq 'UserClosing') { $e.Cancel = $true; $form.Hide() } })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-Sessions })
Set-TrayIcon 'unknown' 'tokcat: 正在读取 Codex 会话'
$form.Add_Shown({ Update-Sessions; $timer.Start() })
try { [Windows.Forms.Application]::Run($form) } finally { $timer.Stop(); $timer.Dispose(); $tray.Visible = $false; $tray.Dispose(); if ($script:icon) { $script:icon.Dispose() }; $form.Dispose() }
