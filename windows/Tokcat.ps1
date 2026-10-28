param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [switch]$SmokeTest
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'SystemMetrics.cs')
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
foreach ($column in @(@('状态',110),@('来源',130),@('任务',240),@('项目',210),@('阶段',170),@('模型',125),@('输出 tokens',90),@('输出 tok/s',90),@('最后活动',145))) { [void]$list.Columns.Add($column[0], $column[1]) }
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
$script:smokeError = $null
$script:seenStates = @{}; $script:unread = @{}; $script:bootstrapped = $false
$listMenu = New-Object Windows.Forms.ContextMenuStrip
$markRead = $listMenu.Items.Add('标记所选任务已读')
$list.ContextMenuStrip = $listMenu

function Set-TrayIcon([string[]]$States, [string]$Text) {
    $bitmap = New-Object Drawing.Bitmap(32,32)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = 'AntiAlias'
    if (-not $States -or $States.Count -eq 0) { $States = @('unknown') }
    $shown = @($States | Select-Object -First 6)
    for ($i = 0; $i -lt $shown.Count; $i++) {
        $color = switch ($shown[$i]) { 'waiting' { 'OrangeRed' } 'approval' { 'OrangeRed' } 'failed' { 'Red' } 'running' { 'Goldenrod' } 'stalled' { 'DarkOrange' } 'completed' { 'ForestGreen' } default { 'Gray' } }
        $brush = New-Object Drawing.SolidBrush([Drawing.Color]::FromName($color))
        if ($shown.Count -eq 1) { $x = 2; $y = 2; $diameter = 28 }
        else { $x = 1 + ($i % 3) * 10; $y = 5 + [Math]::Floor($i / 3) * 12; $diameter = 9 }
        $graphics.FillEllipse($brush, [int]$x, [int]$y, [int]$diameter, [int]$diameter)
        $graphics.DrawEllipse([Drawing.Pens]::White, [int]$x, [int]$y, [int]$diameter, [int]$diameter)
        $brush.Dispose()
    }
    $handle = $bitmap.GetHicon()
    $newIcon = [Drawing.Icon]::FromHandle($handle).Clone()
    if (-not ('Tokcat.Native' -as [type])) { Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace Tokcat { public static class Native { [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h); } }' }
    [void][Tokcat.Native]::DestroyIcon($handle)
    $tray.Icon = $newIcon
    if ($script:icon) { $script:icon.Dispose() }; $script:icon = $newIcon
    $tray.Text = if ($Text.Length -gt 63) { $Text.Substring(0,63) } else { $Text }
    $graphics.Dispose(); $bitmap.Dispose()
}

function Update-Sessions {
    if ($script:scanning) { return }
    $script:scanning = $true
    try {
        $dshHomes = @((Join-Path $env:USERPROFILE '.dsh'), $env:DSH_HOME)
        if ($env:APPDATA) { $dshHomes += @((Join-Path $env:APPDATA 'DSH Desktop\.dsh'), (Join-Path $env:APPDATA 'dsh-desktop\.dsh'), (Join-Path $env:APPDATA '@deepseek-ai\dsh-desktop\.dsh')) }
        $workError = $false
        try { $workSessions = @(Get-WorkSessions $CodexHome) } catch { $workSessions = @(); $workError = $true }
        $buddyError = $false
        try { $buddySessions = @(Get-WorkBuddySessions (Join-Path $env:USERPROFILE '.workbuddy') 'WorkBuddy') } catch { $buddySessions = @(); $buddyError = $true }
        try { $buddySessions += @(Get-WorkBuddySessions (Join-Path $env:USERPROFILE '.workbuddy-ai') 'WorkBuddy AI') } catch { $buddyError = $true }
        $claudeSessions = @(Get-ClaudeSessions (Join-Path $env:LOCALAPPDATA 'Tokcat\claude'))
        $kimiRoots = @((Join-Path $env:USERPROFILE '.kimi-work'), (Join-Path $env:USERPROFILE '.kimi-webbridge'))
        if ($env:APPDATA) { $kimiRoots += @((Join-Path $env:APPDATA 'kimi-desktop'), (Join-Path $env:APPDATA 'kimi')) }
        $activity = @(Get-ActivitySessions @((Join-Path $env:USERPROFILE '.openclaw\agents')) 'OpenClaw') + @(Get-ActivitySessions $kimiRoots 'Kimi')
        $sessions = @(@(Get-CodexSessions $CodexHome) + @(Get-DshSessions $dshHomes) + $workSessions + $buddySessions + $claudeSessions + $activity | Sort-Object Updated -Descending)
        $rates = Get-OutputRates $sessions ([double][Diagnostics.Stopwatch]::GetTimestamp() / [Diagnostics.Stopwatch]::Frequency)
        $metrics = [TokcatSystemMetrics]::Sample()
        $cpu = if ($null -ne $metrics.CpuPercent) { '{0:N0}%' -f $metrics.CpuPercent } else { '—' }
        $memory = if ($null -ne $metrics.MemoryPercent) { '{0:N0}%' -f $metrics.MemoryPercent } else { '—' }
        $counts = @{ running=0; waiting=0; approval=0; stalled=0; failed=0; completed=0; interrupted=0 }
        $dotStates = New-Object 'System.Collections.Generic.List[string]'
        $seenKeys = @{}
        $selectedKey = if ($list.SelectedItems.Count -gt 0) { $list.SelectedItems[0].Name } else { $null }
        $list.BeginUpdate(); $list.Items.Clear()
        foreach ($s in $sessions) {
            $state = $s.State
            if ($s.Source -ne 'Codex Work' -and $state -eq 'running' -and ([datetimeoffset]::UtcNow - $s.Updated).TotalSeconds -ge 120) { $state = 'stalled' }
            if ($counts.ContainsKey($state)) { $counts[$state]++ }
            $label = switch ($state) { 'running' {'运行中'} 'waiting' {'等待回答'} 'approval' {'等待授权'} 'stalled' {'长时间无活动'} 'completed' {'本轮结束'} 'failed' {'失败'} 'interrupted' {'中断'} default {'未知'} }
            $row = New-Object Windows.Forms.ListViewItem($label)
            $row.Name = $s.Source + ':' + $s.Id
            $key = $row.Name; $seenKeys[$key] = $true
            $old = $script:seenStates[$key]
            if ($s.State -in @('running','waiting','approval')) { $script:unread.Remove($key) }
            elseif ($script:bootstrapped -and $s.State -in @('completed','failed') -and $old -and ($old.State -ne $s.State -or $s.Updated -gt $old.Updated)) { $script:unread[$key] = $true }
            $script:seenStates[$key] = @{ State=$s.State; Updated=$s.Updated }
            if ($state -in @('running','waiting','approval','stalled') -or ($state -in @('completed','failed') -and $script:unread.ContainsKey($key))) { $dotStates.Add($state) }
            $rate = if ($rates.ContainsKey($key)) { '{0:N1}' -f $rates[$key] } else { '—' }
            foreach ($value in @($s.Source, $s.Title, $s.Project, $s.Phase, $s.Model, $s.OutputTokens, $rate, $s.Updated.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss'))) { [void]$row.SubItems.Add([string]$value) }
            $row.Tag = if ($s.Source -eq 'Codex Work') { $s.Url } else { $s.Path }
            $row.ForeColor = [Drawing.Color]::FromName($(switch ($state) { 'waiting' {'DarkOrange'} 'approval' {'DarkOrange'} 'failed' {'Red'} 'stalled' {'DarkOrange'} 'running' {'DarkGoldenrod'} 'completed' {'ForestGreen'} default {'Gray'} }))
            [void]$list.Items.Add($row)
            if ($row.Name -eq $selectedKey) { $row.Selected = $true }
        }
        foreach ($key in @($script:seenStates.Keys)) { if (-not $seenKeys.ContainsKey($key)) { $script:seenStates.Remove($key); $script:unread.Remove($key) } }
        $script:bootstrapped = $true
        $list.EndUpdate()
        $summary = "tokcat: 运行 $($counts.running) · 等待 $($counts.waiting + $counts.approval) · 无活动 $($counts.stalled) · CPU $cpu · 内存 $memory"
        if ($dotStates.Count -gt 6) { $summary = "tokcat: $($dotStates.Count) 个状态 · 运行 $($counts.running) · 等待 $($counts.waiting + $counts.approval) · CPU $cpu · 内存 $memory" }
        $orderedDots = @($dotStates | Sort-Object { switch ($_) { 'waiting' { 0 } 'approval' { 0 } 'failed' { 1 } 'stalled' { 2 } 'running' { 3 } 'completed' { 4 } default { 5 } } })
        Set-TrayIcon $orderedDots $summary
        $form.Text = "tokcat · 运行 $($counts.running) · 等待 $($counts.waiting + $counts.approval) · 无活动 $($counts.stalled)"
        $note.Text = "CPU $cpu · 内存 $memory · 最近 7 天共 $($sessions.Count) 项 · 双击打开记录" + $(if ($workError) { ' · Work 数据暂不可读' } else { '' }) + $(if ($buddyError) { ' · WorkBuddy 数据暂不可读' } else { '' })
    } catch {
        $list.EndUpdate()
        $note.Text = '刷新失败：' + $_.Exception.Message
        if ($SmokeTest) { $script:smokeError = $_.Exception.Message }
        Set-TrayIcon @('unknown') 'tokcat: 读取失败，请打开窗口查看'
    } finally { $script:scanning = $false }
}

$open.Add_Click({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$refresh.Add_Click({ Update-Sessions })
$markRead.Add_Click({ if ($list.SelectedItems.Count -gt 0) { $script:unread.Remove($list.SelectedItems[0].Name); Update-Sessions } })
$exit.Add_Click({ $script:quitting = $true; $form.Close() })
$tray.Add_DoubleClick({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$list.Add_DoubleClick({ if ($list.SelectedItems.Count -gt 0) { $target = [string]$list.SelectedItems[0].Tag; if ($target.StartsWith('https://chatgpt.com/c/')) { Start-Process $target } elseif ($target) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $target + '"') } } })
$form.Add_FormClosing({ param($sender,$e) if (-not $script:quitting -and $e.CloseReason -eq 'UserClosing') { $e.Cancel = $true; $form.Hide() } })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-Sessions })
Set-TrayIcon @('unknown') 'tokcat: 正在读取 Codex 会话'
$form.Add_Shown({ Update-Sessions; $timer.Start() })
if ($SmokeTest) {
    $smokeTimer = New-Object Windows.Forms.Timer
    $smokeTimer.Interval = 1000
    $smokeTimer.Add_Tick({
        $smokeTimer.Stop()
        if (-not $form.Visible -or -not $form.IsHandleCreated -or -not $list.IsHandleCreated -or -not $form.ShowInTaskbar -or -not $tray.Visible -or $null -eq $tray.Icon) { $script:smokeError = 'Window, taskbar, or tray was not initialized.' }
        if (@($list.Items | Where-Object { $_.SubItems.Count -gt 1 -and $_.SubItems[1].Text -eq 'Codex' }).Count -eq 0) { $script:smokeError = 'Fixture session was not shown in the window.' }
        $script:quitting = $true
        $form.Close()
    })
    $form.Add_Shown({ $smokeTimer.Start() })
}
try { [Windows.Forms.Application]::Run($form) } finally { $timer.Stop(); $timer.Dispose(); if ($SmokeTest) { $smokeTimer.Dispose() }; $tray.Visible = $false; $tray.Dispose(); if ($script:icon) { $script:icon.Dispose() }; $form.Dispose() }
if ($SmokeTest -and $script:smokeError) { [Console]::Error.WriteLine($script:smokeError); exit 1 }
