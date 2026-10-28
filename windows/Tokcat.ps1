param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [switch]$SmokeTest
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'SystemMetrics.cs')
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace Tokcat { public static class Native { [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h); [DllImport("kernel32.dll")] public static extern bool FreeConsole(); [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appId); } }'
if (-not $SmokeTest) { [void][Tokcat.Native]::FreeConsole() }
[void][Tokcat.Native]::SetCurrentProcessExplicitAppUserModelID('tokcat.Windows.Monitor')
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'Monitor.ps1')
. (Join-Path $PSScriptRoot 'Conversation.ps1')

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
$note.Dock = 'Bottom'; $note.Height = 56; $note.Padding = New-Object Windows.Forms.Padding(8,5,0,0)
$note.Text = 'Codex 本地会话 · 双击任务打开日志 · 关闭窗口可保留托盘运行'
$quotaLabel = New-Object Windows.Forms.Label
$quotaLabel.Dock = 'Top'; $quotaLabel.Height = 27; $quotaLabel.Padding = New-Object Windows.Forms.Padding(8,4,0,0)
$quotaLabel.Text = 'Codex 本地额度：等待记录'
$form.Controls.Add($list); $form.Controls.Add($note); $form.Controls.Add($quotaLabel)
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
$script:launchedAt = [datetimeoffset]::UtcNow
$script:reminderPath = Join-Path $env:LOCALAPPDATA 'Tokcat\reminders.json'
$script:reminderError = $false
try { $script:savedReminders = Read-ReminderStore $script:reminderPath } catch { $script:savedReminders = @{}; $script:reminderError = $true }
$listMenu = New-Object Windows.Forms.ContextMenuStrip
$markRead = $listMenu.Items.Add('标记所选任务已读')
$openRaw = $listMenu.Items.Add('打开原始记录')
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
    [void][Tokcat.Native]::DestroyIcon($handle)
    $tray.Icon = $newIcon
    $form.Icon = $newIcon
    if ($script:icon) { $script:icon.Dispose() }; $script:icon = $newIcon
    $tray.Text = if ($Text.Length -gt 63) { $Text.Substring(0,63) } else { $Text }
    $graphics.Dispose(); $bitmap.Dispose()
}

function Format-NetworkRate($BytesPerSecond) {
    if ($null -eq $BytesPerSecond) { return '—' }
    if ($BytesPerSecond -ge 1048576) { return ('{0:N1} MiB/s' -f ($BytesPerSecond / 1048576)) }
    return ('{0:N1} KiB/s' -f ($BytesPerSecond / 1024))
}

function Format-NetworkRateShort($BytesPerSecond) {
    if ($null -eq $BytesPerSecond) { return '—' }
    if ($BytesPerSecond -ge 1048576) { return ('{0:N1}M' -f ($BytesPerSecond / 1048576)) }
    return ('{0:N1}K' -f ($BytesPerSecond / 1024))
}

function Show-AgentConversation($Session, [bool]$TestMode = $false) {
    $path = Resolve-ConversationPath $Session $env:USERPROFILE
    if (-not $path) { if ($TestMode) { $script:smokeError = 'Conversation path was not found.' } else { [void][Windows.Forms.MessageBox]::Show($form, '尚未找到此会话的本地对话记录。', 'tokcat') }; return }
    $viewer = New-Object Windows.Forms.Form
    $viewer.Text = 'tokcat · ' + [string]$Session.Title
    $viewer.StartPosition = 'CenterParent'; $viewer.Size = New-Object Drawing.Size(800,600); $viewer.MinimumSize = New-Object Drawing.Size(500,300); $viewer.Font = $form.Font
    $textBox = New-Object Windows.Forms.TextBox
    $textBox.Multiline = $true; $textBox.ReadOnly = $true; $textBox.ScrollBars = 'Vertical'; $textBox.WordWrap = $true; $textBox.Dock = 'Fill'
    $button = New-Object Windows.Forms.Button
    $button.Text = '刷新对话'; $button.Dock = 'Bottom'; $button.Height = 34
    $viewer.Controls.Add($textBox); $viewer.Controls.Add($button)
    $reader = ${function:Read-AgentConversation}
    $load = {
        try {
            $snapshot = & $reader $Session $path
            $builder = New-Object Text.StringBuilder
            if ($snapshot.Truncated) { [void]$builder.AppendLine('[仅显示最近的部分对话]'); [void]$builder.AppendLine() }
            foreach ($message in $snapshot.Messages) {
                $role = if ($message.Role -eq 'user') { '用户' } else { '助手' }
                [void]$builder.AppendLine('[' + $role + ']'); [void]$builder.AppendLine($message.Text); [void]$builder.AppendLine()
            }
            if ($builder.Length -eq 0) { [void]$builder.Append('尚无可显示的用户或助手文本。') }
            $textBox.Text = $builder.ToString()
        } catch { $textBox.Text = '无法读取对话：' + $_.Exception.Message }
    }.GetNewClosure()
    $button.Add_Click($load)
    $viewer.Add_Shown($load)
    if ($TestMode) {
        $viewerTimer = New-Object Windows.Forms.Timer
        $testOutcome = [pscustomobject]@{ Error=$null }
        $viewerTimer.Interval = 500
        $check = { $viewerTimer.Stop(); if (-not $textBox.Text.Contains('fixture conversation')) { $testOutcome.Error = 'Conversation viewer did not show fixture text.' }; $viewer.Close() }.GetNewClosure()
        $viewerTimer.Add_Tick($check); $viewer.Add_Shown({ $viewerTimer.Start() }.GetNewClosure())
    }
    try { [void]$viewer.ShowDialog($form); if ($TestMode -and $testOutcome.Error) { $script:smokeError = $testOutcome.Error } } finally { if ($TestMode) { $viewerTimer.Dispose() }; $viewer.Dispose() }
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
        $quota = Get-CodexQuota $CodexHome
        $quotaText = Format-CodexQuota $quota ([datetimeoffset]::UtcNow)
        $quotaLabel.Text = 'Codex 本地额度：' + $quotaText + $(if ($quota) { ' · 记录时间 ' + $quota.ObservedAt.ToLocalTime().ToString('yyyy-MM-dd HH:mm') } else { ' · 等待记录' })
        $rates = Get-OutputRates $sessions ([double][Diagnostics.Stopwatch]::GetTimestamp() / [Diagnostics.Stopwatch]::Frequency)
        $metrics = [TokcatSystemMetrics]::Sample()
        $cpu = if ($null -ne $metrics.CpuPercent) { '{0:N0}%' -f $metrics.CpuPercent } else { '—' }
        $memory = if ($null -ne $metrics.MemoryPercent) { '{0:N0}%' -f $metrics.MemoryPercent } else { '—' }
        $networkDown = Format-NetworkRate $metrics.NetworkDown; $networkUp = Format-NetworkRate $metrics.NetworkUp
        $counts = @{ running=0; waiting=0; approval=0; stalled=0; failed=0; completed=0; interrupted=0 }
        $dotStates = New-Object 'System.Collections.Generic.List[string]'
        Restore-Reminders $sessions $script:seenStates $script:unread $script:savedReminders
        Update-ReminderStates $sessions $script:seenStates $script:unread $script:bootstrapped $script:launchedAt
        if (-not $script:reminderError) {
            try { Sync-ReminderStore $sessions $script:unread $script:savedReminders ([datetimeoffset]::UtcNow); Write-ReminderStore $script:reminderPath $script:savedReminders } catch { $script:reminderError = $true }
        }
        $selectedKey = if ($list.SelectedItems.Count -gt 0) { $list.SelectedItems[0].Name } else { $null }
        $list.BeginUpdate(); $list.Items.Clear()
        foreach ($s in $sessions) {
            $state = $s.State
            if ($s.Source -ne 'Codex Work' -and $state -eq 'running' -and ([datetimeoffset]::UtcNow - $s.Updated).TotalSeconds -ge 120) { $state = 'stalled' }
            if ($counts.ContainsKey($state)) { $counts[$state]++ }
            $label = switch ($state) { 'running' {'运行中'} 'waiting' {'等待回答'} 'approval' {'等待授权'} 'stalled' {'长时间无活动'} 'completed' {'本轮结束'} 'failed' {'失败'} 'interrupted' {'中断'} default {'未知'} }
            $row = New-Object Windows.Forms.ListViewItem($label)
            $row.Name = $s.Source + ':' + $s.Id
            $key = $row.Name
            if ($state -in @('running','waiting','approval','stalled') -or ($state -in @('completed','failed') -and $script:unread.ContainsKey($key))) { $dotStates.Add($state) }
            $rate = if ($rates.ContainsKey($key)) { '{0:N1}' -f $rates[$key] } else { '—' }
            foreach ($value in @($s.Source, $s.Title, $s.Project, $s.Phase, $s.Model, $s.OutputTokens, $rate, $s.Updated.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss'))) { [void]$row.SubItems.Add([string]$value) }
            $row.Tag = $s
            $row.ForeColor = [Drawing.Color]::FromName($(switch ($state) { 'waiting' {'DarkOrange'} 'approval' {'DarkOrange'} 'failed' {'Red'} 'stalled' {'DarkOrange'} 'running' {'DarkGoldenrod'} 'completed' {'ForestGreen'} default {'Gray'} }))
            [void]$list.Items.Add($row)
            if ($row.Name -eq $selectedKey) { $row.Selected = $true }
        }
        $script:bootstrapped = $true
        $list.EndUpdate()
        $downShort = Format-NetworkRateShort $metrics.NetworkDown; $upShort = Format-NetworkRateShort $metrics.NetworkUp
        $summary = "运行$($counts.running) 等$($counts.waiting + $counts.approval) $quotaText CPU$cpu 内存$memory ↓$downShort ↑$upShort"
        if ($dotStates.Count -gt 6) { $summary = "状态$($dotStates.Count) 等$($counts.waiting + $counts.approval) $quotaText CPU$cpu 内存$memory ↓$downShort ↑$upShort" }
        $orderedDots = @($dotStates | Sort-Object { switch ($_) { 'waiting' { 0 } 'approval' { 0 } 'failed' { 1 } 'stalled' { 2 } 'running' { 3 } 'completed' { 4 } default { 5 } } })
        Set-TrayIcon $orderedDots $summary
        $form.Text = "tokcat · 运行 $($counts.running) · 等待 $($counts.waiting + $counts.approval) · 无活动 $($counts.stalled)"
        $note.Text = "CPU $cpu · 内存 $memory · 网络 ↓ $networkDown ↑ $networkUp`n最近 7 天共 $($sessions.Count) 项 · 双击查看对话" + $(if ($workError) { ' · Work 数据暂不可读' } else { '' }) + $(if ($buddyError) { ' · WorkBuddy 数据暂不可读' } else { '' }) + $(if ($script:reminderError) { ' · 提醒保存不可用' } else { '' })
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
$openRaw.Add_Click({ if ($list.SelectedItems.Count -gt 0) { $item = $list.SelectedItems[0].Tag; $path = Resolve-ConversationPath $item $env:USERPROFILE; if ($path) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $path + '"') } else { [void][Windows.Forms.MessageBox]::Show($form, '尚未找到此会话的本地记录。', 'tokcat') } } })
$exit.Add_Click({ $script:quitting = $true; $form.Close() })
$tray.Add_DoubleClick({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$list.Add_DoubleClick({ if ($list.SelectedItems.Count -gt 0) { $item = $list.SelectedItems[0].Tag; if ($item.Source -eq 'Codex Work') { Start-Process $item.Url } elseif ($item.Source -in @('Codex','Claude Code','WorkBuddy','WorkBuddy AI','DeepSeek Harness')) { Show-AgentConversation $item } elseif ($item.Path) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $item.Path + '"') } } })
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
        if (-not $form.Visible -or -not $form.IsHandleCreated -or -not $list.IsHandleCreated -or -not $form.ShowInTaskbar -or -not $tray.Visible -or $null -eq $tray.Icon -or $null -eq $form.Icon) { $script:smokeError = 'Window, taskbar, or tray was not initialized.' }
        if (@($list.Items | Where-Object { $_.SubItems.Count -gt 1 -and $_.SubItems[1].Text -eq 'Codex' }).Count -eq 0) { $script:smokeError = 'Fixture session was not shown in the window.' }
        $testRow = @($list.Items | Where-Object { $_.SubItems.Count -gt 1 -and $_.SubItems[1].Text -eq 'Codex' } | Select-Object -First 1)
        if ($testRow.Count -gt 0) { Show-AgentConversation $testRow[0].Tag $true }
        Set-TrayIcon @('running','waiting','failed','completed','stalled','approval') 'tokcat: smoke test'
        $iconBitmap = $tray.Icon.ToBitmap()
        $taskbarBitmap = $form.Icon.ToBitmap()
        try {
            if ($iconBitmap.GetPixel(5,9).ToArgb() -ne [Drawing.Color]::Goldenrod.ToArgb() -or $iconBitmap.GetPixel(15,9).ToArgb() -ne [Drawing.Color]::OrangeRed.ToArgb() -or $iconBitmap.GetPixel(25,9).ToArgb() -ne [Drawing.Color]::Red.ToArgb()) { $script:smokeError = 'Task state dots were not drawn in the tray icon.' }
            if ($taskbarBitmap.GetPixel(5,9).ToArgb() -ne $iconBitmap.GetPixel(5,9).ToArgb() -or $taskbarBitmap.GetPixel(15,9).ToArgb() -ne $iconBitmap.GetPixel(15,9).ToArgb()) { $script:smokeError = 'Taskbar and tray icons did not match.' }
        } finally { $iconBitmap.Dispose(); $taskbarBitmap.Dispose() }
        $script:quitting = $true
        $form.Close()
    })
    $form.Add_Shown({ $smokeTimer.Start() })
}
try { [Windows.Forms.Application]::Run($form) } finally { $timer.Stop(); $timer.Dispose(); if ($SmokeTest) { $smokeTimer.Dispose() }; $tray.Visible = $false; $tray.Dispose(); $form.Dispose(); if ($script:icon) { $script:icon.Dispose() } }
if ($SmokeTest -and $script:smokeError) { [Console]::Error.WriteLine($script:smokeError); exit 1 }
