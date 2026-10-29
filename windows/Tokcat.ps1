param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [switch]$SmokeTest
)

. (Join-Path $PSScriptRoot 'Instance.ps1')
$instance = Open-TokcatInstance ([Environment]::UserName + '|' + [string]$env:USERPROFILE)
if (-not $instance.IsFirst) {
    [void]$instance.Event.Set()
    Close-TokcatInstance $instance
    return
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'Load-TaskbarWidget.ps1')
Add-Type -Path (Join-Path $PSScriptRoot 'SystemMetrics.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'GpuMetrics.cs') -ReferencedAssemblies System.Management.dll
Add-Type -Path (Join-Path $PSScriptRoot 'CodexLogReader.cs')
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace Tokcat { public static class Native { [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h); [DllImport("kernel32.dll")] public static extern bool FreeConsole(); [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appId); } }'
if (-not $SmokeTest) { [void][Tokcat.Native]::FreeConsole() }
[void][Tokcat.Native]::SetCurrentProcessExplicitAppUserModelID('tokcat.Windows.Monitor')
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'Monitor.ps1')
. (Join-Path $PSScriptRoot 'Conversation.ps1')
. (Join-Path $PSScriptRoot 'Usage.ps1')
. (Join-Path $PSScriptRoot 'UsageWindow.ps1')

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
$topBar = New-Object Windows.Forms.Panel; $topBar.Dock = 'Top'; $topBar.Height = 35
$usageButton = New-Object Windows.Forms.Button; $usageButton.Text = '用量统计'; $usageButton.Width = 100; $usageButton.Dock = 'Left'
$stripButton = New-Object Windows.Forms.Button; $stripButton.Text = '任务栏'; $stripButton.Width = 100; $stripButton.Dock = 'Left'
$quitButton = New-Object Windows.Forms.Button; $quitButton.Text = '退出'; $quitButton.Width = 65; $quitButton.Dock = 'Right'
$quotaLabel.Dock = 'Fill'; $topBar.Controls.Add($quotaLabel); $topBar.Controls.Add($quitButton); $topBar.Controls.Add($stripButton); $topBar.Controls.Add($usageButton)
$form.Controls.Add($list); $form.Controls.Add($note); $form.Controls.Add($topBar)
$menu = New-Object Windows.Forms.ContextMenuStrip
$open = $menu.Items.Add('打开监控窗口')
$refresh = $menu.Items.Add('立即刷新')
$usageMenu = $menu.Items.Add('用量统计')
$notificationMenu = $menu.Items.Add('启用状态通知')
$stripMenu = $menu.Items.Add('显示任务栏监控')
$metricsMenu = $menu.Items.Add('任务栏指标')
$cpuMenu = $metricsMenu.DropDownItems.Add('CPU'); $cpuMenu.Tag = 'Cpu'
$gpuMenu = $metricsMenu.DropDownItems.Add('GPU'); $gpuMenu.Tag = 'Gpu'
$memoryMenu = $metricsMenu.DropDownItems.Add('内存'); $memoryMenu.Tag = 'Memory'
[void]$menu.Items.Add('-')
$exit = $menu.Items.Add('退出 tokcat')
$tray = New-Object Windows.Forms.NotifyIcon
$tray.ContextMenuStrip = $menu; $tray.Visible = $true
$script:icon = $null; $script:quitting = $false; $script:scanning = $false
$script:smokeError = $null
$script:dshBaseline = @{}; $script:dshUsagePath = Join-Path $env:LOCALAPPDATA 'Tokcat\dsh-usage.jsonl'; $script:dshUsageError = $false
$script:metricsPreferencePath = Join-Path $env:LOCALAPPDATA 'Tokcat\taskbar-metrics.json'; $script:metricsPreferenceError = $false
try { $script:taskbarMetrics = Read-TaskbarMetricsPreference $script:metricsPreferencePath } catch { $script:taskbarMetrics = [pscustomobject]@{ Cpu=$false; Gpu=$false; Memory=$false }; $script:metricsPreferenceError = $true }
$cpuMenu.Checked = $script:taskbarMetrics.Cpu; $gpuMenu.Checked = $script:taskbarMetrics.Gpu; $memoryMenu.Checked = $script:taskbarMetrics.Memory
$script:gpuSampler = $null
if ($script:taskbarMetrics.Gpu -and -not $SmokeTest) { $script:gpuSampler = New-Object TokcatGpuMetrics; $script:gpuSampler.Start() }
$script:seenStates = @{}; $script:unread = @{}; $script:bootstrapped = $false
$script:launchedAt = [datetimeoffset]::UtcNow
$script:reminderPath = Join-Path $env:LOCALAPPDATA 'Tokcat\reminders.json'
$script:reminderError = $false
try { $script:savedReminders = Read-ReminderStore $script:reminderPath } catch { $script:savedReminders = @{}; $script:reminderError = $true }
$script:preferencePath = Join-Path $env:LOCALAPPDATA 'Tokcat\preferences.json'
$script:preferenceError = $false
try { $notificationMenu.Checked = Read-NotificationPreference $script:preferencePath } catch { $notificationMenu.Checked = $false; $script:preferenceError = $true }
$script:stripPreferencePath = Join-Path $env:LOCALAPPDATA 'Tokcat\taskbar.json'
$script:stripPreferenceError = $false
try { $script:stripEnabled = Read-StatusStripPreference $script:stripPreferencePath } catch { $script:stripEnabled = $true; $script:stripPreferenceError = $true }
$stripMenu.Checked = $script:stripEnabled
$taskbarWidget = New-Object TokcatTaskbarWidget
$taskbarWidget.Menu = $menu
$script:snapshotReader = New-AgentSnapshotReader $PSScriptRoot
$script:latestMetrics = [TokcatSystemMetrics]::Sample()
$script:taskbarDots = @('unknown'); $script:taskbarTokenSpeed = '—'; $script:taskbarQuota = '—'; $script:agentReadError = $false
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

function Set-StatusStrip([bool]$Enabled, [bool]$Persist = $true) {
    if ($Persist) {
        try { Write-StatusStripPreference $script:stripPreferencePath $Enabled; $script:stripPreferenceError = $false }
        catch { $script:stripPreferenceError = $true; [void][Windows.Forms.MessageBox]::Show($form, '无法保存任务栏显示设置。', 'tokcat'); return }
    }
    $script:stripEnabled = $Enabled; $stripMenu.Checked = $Enabled
    $stripButton.Text = if ($Enabled) { '隐藏任务栏' } else { '显示任务栏' }
    $taskbarWidget.SetEnabled($Enabled -and -not $SmokeTest)
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

function Update-SystemDisplay([bool]$Sample = $true) {
    if ($Sample) { $script:latestMetrics = [TokcatSystemMetrics]::Sample() }
    $metrics = $script:latestMetrics
    $cpu = if ($script:taskbarMetrics.Cpu -and $null -ne $metrics.CpuPercent) { '{0:N0}%' -f $metrics.CpuPercent } elseif ($script:taskbarMetrics.Cpu) { '—' } else { $null }
    $gpuValue = if ($script:gpuSampler) { $script:gpuSampler.Read() } else { $null }
    $gpu = if ($script:taskbarMetrics.Gpu -and $null -ne $gpuValue) { '{0:N0}%' -f $gpuValue } elseif ($script:taskbarMetrics.Gpu) { '—' } else { $null }
    $memory = if ($script:taskbarMetrics.Memory -and $null -ne $metrics.MemoryPercent) { '{0:N0}%' -f $metrics.MemoryPercent } elseif ($script:taskbarMetrics.Memory) { '—' } else { $null }
    $speed = if ($script:agentReadError) { '读取失败' } else { "$($script:taskbarTokenSpeed) tok/s" }
    $taskbarWidget.SetMetrics($script:taskbarDots, $speed, $script:taskbarQuota, (Format-TaskbarNetworkRate $metrics.NetworkUp), (Format-TaskbarNetworkRate $metrics.NetworkDown), $cpu, $gpu, $memory)
}

function Update-Sessions($Snapshot = $null) {
    if ($null -eq $Snapshot) {
        try { [void](Request-AgentSnapshot $script:snapshotReader $CodexHome $env:USERPROFILE $env:APPDATA $env:LOCALAPPDATA) }
        catch { $script:agentReadError = $true; $note.Text = '无法开始读取任务：' + $_.Exception.Message; if ($SmokeTest) { $script:smokeError = $_.Exception.Message } }
        return
    }
    if ($script:scanning) { return }
    $script:scanning = $true
    try {
        $workError = $Snapshot.WorkError; $buddyError = $Snapshot.BuddyError
        $dshSessions = @($Snapshot.DshSessions)
        try { Save-DshUsage $dshSessions $script:dshBaseline $script:dshUsagePath ([datetimeoffset]::Now); $script:dshUsageError = $false } catch { $script:dshUsageError = $true }
        $sessions = @($Snapshot.Sessions); $quota = $Snapshot.Quota; $script:agentReadError = $false
        $quotaText = Format-CodexQuota $quota ([datetimeoffset]::UtcNow)
        $quotaLabel.Text = 'Codex 本地额度：' + $quotaText + $(if ($quota) { ' · 记录时间 ' + $quota.ObservedAt.ToLocalTime().ToString('yyyy-MM-dd HH:mm') } else { ' · 等待记录' })
        $rates = Get-OutputRates $sessions ([double][Diagnostics.Stopwatch]::GetTimestamp() / [Diagnostics.Stopwatch]::Frequency)
        $metrics = $script:latestMetrics
        $cpu = if ($null -ne $metrics.CpuPercent) { '{0:N0}%' -f $metrics.CpuPercent } else { '—' }
        $gpuValue = if ($script:gpuSampler) { $script:gpuSampler.Read() } else { $null }
        $gpu = if ($null -ne $gpuValue) { '{0:N0}%' -f $gpuValue } else { '—' }
        $memory = if ($null -ne $metrics.MemoryPercent) { '{0:N0}%' -f $metrics.MemoryPercent } else { '—' }
        $networkDown = Format-NetworkRate $metrics.NetworkDown; $networkUp = Format-NetworkRate $metrics.NetworkUp
        $counts = @{ running=0; waiting=0; approval=0; stalled=0; failed=0; completed=0; interrupted=0 }
        $dotStates = New-Object 'System.Collections.Generic.List[string]'
        $alerts = @(Get-NewSessionAlerts $sessions $script:seenStates $script:bootstrapped $script:launchedAt)
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
        $summary = "运行$($counts.running) 等$($counts.waiting + $counts.approval) $quotaText CPU$cpu GPU$gpu 内存$memory ↓$downShort ↑$upShort"
        if ($dotStates.Count -gt 6) { $summary = "状态$($dotStates.Count) 等$($counts.waiting + $counts.approval) $quotaText CPU$cpu GPU$gpu 内存$memory ↓$downShort ↑$upShort" }
        $orderedDots = @($dotStates | Sort-Object { switch ($_) { 'waiting' { 0 } 'approval' { 0 } 'failed' { 1 } 'stalled' { 2 } 'running' { 3 } 'completed' { 4 } default { 5 } } })
        Set-TrayIcon $orderedDots $summary
        $tokenSpeed = if ($rates.Count -gt 0) { '{0:N1}' -f (($rates.Values | Measure-Object -Sum).Sum) } else { '—' }
        $script:taskbarDots = $orderedDots; $script:taskbarTokenSpeed = $tokenSpeed; $script:taskbarQuota = $quotaText
        Update-SystemDisplay $false
        if ($notificationMenu.Checked -and $alerts.Count -gt 0 -and -not $SmokeTest) {
            $detail = if ($alerts.Count -eq 1) {
                $alert = $alerts[0]; $label = switch ($alert.State) { 'waiting' {'等待回答'} 'approval' {'等待授权'} 'failed' {'本轮失败'} default {'本轮结束'} }
                $title = [string]$alert.Title; if ($title.Length -gt 80) { $title = $title.Substring(0,80) + '…' }; "$label · $title"
            } else { "$($alerts.Count) 个任务状态发生变化，打开 tokcat 查看。" }
            $tray.ShowBalloonTip(5000, 'tokcat', $detail, [Windows.Forms.ToolTipIcon]::Info)
        }
        $form.Text = "tokcat · 运行 $($counts.running) · 等待 $($counts.waiting + $counts.approval) · 无活动 $($counts.stalled)"
        $note.Text = "CPU $cpu · GPU $gpu · 内存 $memory · 网络 ↓ $networkDown ↑ $networkUp`n最近 7 天共 $($sessions.Count) 项 · 双击查看对话" + $(if ($workError) { ' · Work 数据暂不可读' } else { '' }) + $(if ($buddyError) { ' · WorkBuddy 数据暂不可读' } else { '' }) + $(if ($script:dshUsageError) { ' · DeepSeek 用量保存不可用' } else { '' }) + $(if ($script:reminderError) { ' · 提醒保存不可用' } else { '' }) + $(if ($script:preferenceError -or $script:stripPreferenceError) { ' · 设置保存不可用' } else { '' })
    } catch {
        $list.EndUpdate()
        $note.Text = '刷新失败：' + $_.Exception.Message
        if ($SmokeTest) { $script:smokeError = $_.Exception.Message }
        $script:agentReadError = $true; $script:taskbarDots = @('unknown')
        Set-TrayIcon @('unknown') 'tokcat: 读取失败，请打开窗口查看'
        $taskbarWidget.SetContent(@('unknown'), 'tokcat 读取失败', '单击查看详情')
    } finally { $script:scanning = $false }
}

$open.Add_Click({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$refresh.Add_Click({ Update-Sessions })
$usageMenu.Add_Click({ Show-UsageWindow $form $CodexHome })
$usageButton.Add_Click({ Show-UsageWindow $form $CodexHome })
$toggleStrip = { Set-StatusStrip (-not $script:stripEnabled) }
$stripMenu.Add_Click($toggleStrip); $stripButton.Add_Click($toggleStrip)
$showMain = { $form.Show(); $form.WindowState = 'Normal'; $form.Activate() }
$taskbarWidget.Add_Clicked($showMain)
$toggleMetric = {
    param($sender,$event)
    $value = [pscustomobject]@{ Cpu=$script:taskbarMetrics.Cpu; Gpu=$script:taskbarMetrics.Gpu; Memory=$script:taskbarMetrics.Memory }
    $key = [string]$sender.Tag; $value.$key = -not $value.$key
    try { Write-TaskbarMetricsPreference $script:metricsPreferencePath $value.Cpu $value.Gpu $value.Memory; $script:metricsPreferenceError = $false } catch { $script:metricsPreferenceError = $true; [void][Windows.Forms.MessageBox]::Show($form,'无法保存任务栏指标设置。','tokcat'); return }
    $script:taskbarMetrics = $value; $cpuMenu.Checked = $value.Cpu; $gpuMenu.Checked = $value.Gpu; $memoryMenu.Checked = $value.Memory
    if ($value.Gpu -and -not $script:gpuSampler -and -not $SmokeTest) { $script:gpuSampler = New-Object TokcatGpuMetrics; $script:gpuSampler.Start() }
    elseif (-not $value.Gpu -and $script:gpuSampler) { $script:gpuSampler.Stop(); $script:gpuSampler = $null }
    Update-Sessions
}
$cpuMenu.Add_Click($toggleMetric); $gpuMenu.Add_Click($toggleMetric); $memoryMenu.Add_Click($toggleMetric)
$quitButton.Add_Click({ $script:quitting = $true; $form.Close() })
$notificationMenu.Add_Click({ try { $enabled = -not $notificationMenu.Checked; Write-NotificationPreference $script:preferencePath $enabled; $notificationMenu.Checked = $enabled; $script:preferenceError = $false } catch { $script:preferenceError = $true; [void][Windows.Forms.MessageBox]::Show($form, '无法保存通知设置。', 'tokcat') } })
$markRead.Add_Click({ if ($list.SelectedItems.Count -gt 0) { $script:unread.Remove($list.SelectedItems[0].Name); Update-Sessions } })
$openRaw.Add_Click({ if ($list.SelectedItems.Count -gt 0) { $item = $list.SelectedItems[0].Tag; $path = Resolve-ConversationPath $item $env:USERPROFILE; if ($path) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $path + '"') } else { [void][Windows.Forms.MessageBox]::Show($form, '尚未找到此会话的本地记录。', 'tokcat') } } })
$exit.Add_Click({ $script:quitting = $true; $form.Close() })
$tray.Add_DoubleClick({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$list.Add_DoubleClick({ if ($list.SelectedItems.Count -gt 0) { $item = $list.SelectedItems[0].Tag; if ($item.Source -eq 'Codex Work') { Start-Process $item.Url } elseif ($item.Source -in @('Codex','Claude Code','WorkBuddy','WorkBuddy AI','DeepSeek Harness')) { Show-AgentConversation $item } elseif ($item.Path) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $item.Path + '"') } } })
$form.Add_FormClosing({ param($sender,$e) if (-not $script:quitting -and $e.CloseReason -eq 'UserClosing') { $e.Cancel = $true; $form.Hide() } })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-Sessions })
$metricsTimer = New-Object Windows.Forms.Timer; $metricsTimer.Interval = 1000
$metricsTimer.Add_Tick({ try { Update-SystemDisplay } catch { $note.Text = '指标刷新失败：' + $_.Exception.Message } })
$snapshotPoll = New-Object Windows.Forms.Timer; $snapshotPoll.Interval = 200
$snapshotPoll.Add_Tick({
    try { $snapshot = Receive-AgentSnapshot $script:snapshotReader; if ($null -ne $snapshot) { Update-Sessions $snapshot } }
    catch { $script:agentReadError = $true; $script:taskbarDots = @('unknown'); $note.Text = '任务读取失败：' + $_.Exception.Message; if ($SmokeTest) { $script:smokeError = $_.Exception.Message } }
})
$instanceTimer = New-Object Windows.Forms.Timer
$instanceTimer.Interval = 500
$instanceTimer.Add_Tick({ if ($instance.Event.WaitOne(0)) { $form.Show(); $form.WindowState = 'Normal'; $form.Activate() }; if ($script:stripEnabled -and $taskbarWidget.Status -ne 'Embedded') { $quotaLabel.Text = '任务栏监控暂不可用：' + $(switch ($taskbarWidget.Status) { 'No free taskbar space' { '任务栏空间不足' } 'Waiting for taskbar layout' { '正在读取布局' } default { '等待任务栏恢复' } }) } })
Set-TrayIcon @('unknown') 'tokcat: 正在读取 Codex 会话'
$form.Add_Shown({ Update-SystemDisplay; Update-Sessions; if ($script:stripEnabled) { Set-StatusStrip $true $false } else { $stripButton.Text = '显示任务栏' }; $timer.Start(); $metricsTimer.Start(); $snapshotPoll.Start(); $instanceTimer.Start(); if (-not $SmokeTest) { $form.Hide() } })
if ($SmokeTest) {
    $smokeTimer = New-Object Windows.Forms.Timer
    $smokeTimer.Interval = 1000
    $script:smokeDeadline = [datetimeoffset]::UtcNow.AddSeconds(30)
    $smokeTimer.Add_Tick({
        if (-not $script:bootstrapped -and [datetimeoffset]::UtcNow -lt $script:smokeDeadline) { return }
        $smokeTimer.Stop()
        if ($metricsTimer.Interval -ne 1000 -or -not $metricsTimer.Enabled) { $script:smokeError = 'Lightweight metrics must refresh independently every second.' }
        if (-not $form.Visible -or -not $form.IsHandleCreated -or -not $list.IsHandleCreated -or -not $form.ShowInTaskbar -or -not $tray.Visible -or $null -eq $tray.Icon -or $null -eq $form.Icon) { $script:smokeError = 'Window, taskbar, or tray was not initialized.' }
        $stripButton.PerformClick()
        if ($taskbarWidget.Visible -or $stripMenu.Checked) { $script:smokeError = 'Taskbar widget did not hide.' }
        $stripButton.PerformClick()
        if (-not $stripMenu.Checked) { $script:smokeError = 'Taskbar widget was not enabled.' }
        if ($cpuMenu.Checked -or $gpuMenu.Checked -or $memoryMenu.Checked) { $script:smokeError = 'Taskbar hardware metrics must be off by default.' }
        $cpuMenu.PerformClick()
        if (-not $cpuMenu.Checked -or -not (Read-TaskbarMetricsPreference $script:metricsPreferencePath).Cpu) { $script:smokeError = 'Taskbar metric toggle did not persist.' }
        $cpuMenu.PerformClick()
        if (@($list.Items | Where-Object { $_.SubItems.Count -gt 1 -and $_.SubItems[1].Text -eq 'Codex' }).Count -eq 0) { $script:smokeError = 'Fixture session was not shown in the window.' }
        $testRow = @($list.Items | Where-Object { $_.SubItems.Count -gt 1 -and $_.SubItems[1].Text -eq 'Codex' } | Select-Object -First 1)
        if ($testRow.Count -gt 0) { Show-AgentConversation $testRow[0].Tag $true }
        $usageError = Show-UsageWindow $form $CodexHome $true
        if ($usageError) { $script:smokeError = 'Usage window: ' + $usageError }
        $proxyUsageError = Show-UsageWindow $form $CodexHome $true $true
        if ($proxyUsageError) { $script:smokeError = 'Proxy usage window: ' + $proxyUsageError }
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
try { [Windows.Forms.Application]::Run($form) } finally { $timer.Stop(); $timer.Dispose(); $metricsTimer.Stop(); $metricsTimer.Dispose(); $snapshotPoll.Stop(); $snapshotPoll.Dispose(); Close-AgentSnapshotReader $script:snapshotReader; $instanceTimer.Stop(); $instanceTimer.Dispose(); if ($SmokeTest) { $smokeTimer.Dispose() }; if ($script:gpuSampler) { $script:gpuSampler.Stop() }; $taskbarWidget.Dispose(); $tray.Visible = $false; $tray.Dispose(); $form.Dispose(); if ($script:icon) { $script:icon.Dispose() }; Close-TokcatInstance $instance }
if ($SmokeTest -and $script:smokeError) { [Console]::Error.WriteLine($script:smokeError); exit 1 }
