function Show-UsageWindow($Owner, [string]$CodexHome, [bool]$TestMode = $false, [bool]$TestProxy = $false) {
    $baseDirectory = $PSScriptRoot
    $window = New-Object Windows.Forms.Form
    $window.Text = 'tokcat · Agent 用量统计'; $window.Size = New-Object Drawing.Size(1180,600)
    $window.MinimumSize = New-Object Drawing.Size(650,350); $window.StartPosition = 'CenterParent'; $window.Font = $Owner.Font
    [TokcatUi]::StyleWindow($window)
    $window.MinimumSize = New-Object Drawing.Size(1040,560)
    $controls = New-Object Windows.Forms.FlowLayoutPanel
    $controls.Dock = 'Top'; $controls.Height = 54; $controls.WrapContents = $false
    $caption = New-Object Windows.Forms.Label; $caption.Text = '统计周期：'; $caption.AutoSize = $true; $caption.Padding = New-Object Windows.Forms.Padding(4,8,0,0)
    $period = New-Object Windows.Forms.ComboBox; $period.DropDownStyle = 'DropDownList'; $period.Width = 105
    [void]$period.Items.AddRange(@('今天','近 7 天','近 30 天')); $period.SelectedIndex = 1
    $sourceLabel = New-Object Windows.Forms.Label; $sourceLabel.Text = '数据来源：'; $sourceLabel.AutoSize = $true; $sourceLabel.Padding = New-Object Windows.Forms.Padding(4,8,0,0)
    $source = New-Object Windows.Forms.ComboBox; $source.DropDownStyle = 'DropDownList'; $source.Width = 160
    [void]$source.Items.AddRange(@('Agent 本地日志','CC Switch 代理')); $source.SelectedIndex = if ($TestProxy) { 1 } else { 0 }
    $refresh = [TokcatUi]::Button('重新读取', 'refresh', $false); $refresh.Width = 120
    $editPrices = [TokcatUi]::Button('编辑参考单价', 'record', $false); $editPrices.Width = 150
    $controls.Controls.Add($caption); $controls.Controls.Add($period); $controls.Controls.Add($sourceLabel); $controls.Controls.Add($source); $controls.Controls.Add($refresh); $controls.Controls.Add($editPrices)
    [TokcatUi]::StyleToolbar($controls)
    $list = New-Object Windows.Forms.ListView
    $list.Dock = 'Fill'; [TokcatUi]::StyleList($list)
    foreach ($column in @(@('日期',110),@('来源',105),@('模型',180),@('提供方',120),@('输入',105),@('缓存读取',105),@('缓存写入',105),@('输出',105),@('参考估价 USD',130),@('未计价 tokens',130))) { [void]$list.Columns.Add($column[0], $column[1]) }
    foreach ($index in 4..9) { $list.Columns[$index].TextAlign = 'Right' }
    $summary = New-Object Windows.Forms.Label
    $summary.Dock = 'Bottom'; $summary.Height = 90; $summary.Padding = New-Object Windows.Forms.Padding(14,12,14,6); $summary.ForeColor = [TokcatUi]::Secondary
    $summary.Text = '正在读取本地 Agent 日志…'
    $window.Controls.Add($list); $window.Controls.Add($summary); $window.Controls.Add($controls)
    $heading = [TokcatUi]::Label('用量统计  /  USAGE', 18, [TokcatUi]::Text)
    $heading.Dock = 'Top'; $heading.Height = 66; $heading.Padding = New-Object Windows.Forms.Padding(14,16,0,0)
    $window.Controls.Add($heading)
    $context = [pscustomobject]@{ Worker=$null; Handle=$null; Done=$false; Error=$null; Deadline=[datetimeoffset]::UtcNow.AddSeconds(45) }
    $poll = New-Object Windows.Forms.Timer; $poll.Interval = 300
    $resolvePrice = ${function:Get-UsagePricePath}
    $start = {
        if ($context.Worker) { $context.Worker.Dispose(); $context.Worker = $null; $context.Handle = $null }
        $context.Done = $false; $context.Error = $null; $summary.Text = '正在后台读取本地 Agent 日志…'; $list.Items.Clear()
        $period.Enabled = $false; $source.Enabled = $false; $refresh.Enabled = $false
        $days = @(1,7,30)[$period.SelectedIndex]
        $proxyView = $source.SelectedIndex -eq 1
        $list.Columns[8].Text = if ($proxyView) { '上报费用 USD' } else { '参考估价 USD' }
        try {
            $pricePath = & $resolvePrice $baseDirectory $env:LOCALAPPDATA $false
            $workerScript = {
                param($directory,$homePath,$userDirectory,$days,$pricePath,$proxyView)
                $ErrorActionPreference = 'Stop'
                . (Join-Path $directory 'Monitor.ps1'); . (Join-Path $directory 'Usage.ps1')
                if ($proxyView) { Get-CCSwitchUsage $userDirectory $days } else { Get-CombinedUsage $homePath $userDirectory $days $pricePath }
            }.ToString()
            $context.Worker = [PowerShell]::Create()
            [void]$context.Worker.AddScript($workerScript).AddArgument($baseDirectory).AddArgument($CodexHome).AddArgument($env:USERPROFILE).AddArgument($days).AddArgument($pricePath).AddArgument($proxyView)
            $context.Handle = $context.Worker.BeginInvoke()
            $poll.Start()
        } catch { $context.Error = $_.Exception.Message; $context.Done = $true; $summary.Text = '无法开始读取：' + $context.Error; $period.Enabled = $true; $source.Enabled = $true; $refresh.Enabled = $true; if ($TestMode) { $window.Close() } }
    }.GetNewClosure()
    $tick = {
        if ($TestMode -and [datetimeoffset]::UtcNow -gt $context.Deadline -and -not $context.Done) { $context.Error = 'Usage worker timed out.'; $context.Done = $true }
        if (-not $context.Done -and $context.Handle -and $context.Handle.IsCompleted) {
            try {
                $result = @($context.Worker.EndInvoke($context.Handle))
                if ($context.Worker.HadErrors) { throw '后台读取未能完成。' }
                if ($result.Count -ne 1) { throw '后台读取未返回有效统计。' }
                $result = $result[0]
                if ($null -eq $result -or $null -eq $result.PSObject.Properties['Rows']) { throw '后台读取未返回有效统计。' }
                if ($TestMode -and -not $TestProxy -and @($result.Rows | Where-Object { $_.Model -eq 'gpt-5.6-sol' -and $_.Output -eq 3 }).Count -eq 0) { throw '用量窗口没有显示测试数据。' }
                if ($TestMode -and $TestProxy -and $result.Present -and @($result.Rows | Where-Object { $_.Model -eq 'gpt-x' -and $_.Input -eq 103 }).Count -eq 0) { throw '代理用量窗口没有显示测试数据。' }
                if ($TestMode -and $TestProxy -and -not $result.Present -and @($result.Rows).Count -ne 0) { throw '缺少代理数据库时不应显示数据。' }
                $inputTotal = [long]0; $cacheTotal = [long]0; $cacheWriteTotal = [long]0; $outputTotal = [long]0; $cost = [double]0; $unpriced = [long]0
                $list.BeginUpdate(); $list.Items.Clear()
                foreach ($row in $result.Rows) {
                    $inputTotal += $row.Input; $cacheTotal += $row.Cache; $cacheWriteTotal += $row.CacheWrite; $outputTotal += $row.Output; $cost += $row.EstimatedUSD; $unpriced += $row.UnpricedTokens
                    $item = New-Object Windows.Forms.ListViewItem([string]$row.Date)
                    $estimated = if ($row.UnpricedTokens -gt 0 -and $row.EstimatedUSD -gt 0) { ('${0:N4} + 未计价' -f $row.EstimatedUSD) } elseif ($row.UnpricedTokens -gt 0) { '未计价' } else { ('${0:N4}' -f $row.EstimatedUSD) }
                    foreach ($value in @($row.Source, $row.Model, $row.Provider, ('{0:N0}' -f $row.Input), ('{0:N0}' -f $row.Cache), ('{0:N0}' -f $row.CacheWrite), ('{0:N0}' -f $row.Output), $estimated, ('{0:N0}' -f $row.UnpricedTokens))) { [void]$item.SubItems.Add([string]$value) }
                    [void]$list.Items.Add($item)
                }
                $list.EndUpdate()
                if ($source.SelectedIndex -eq 1) {
                    $summary.Text = "输入 $inputTotal · 缓存读取 $cacheTotal · 缓存写入 $cacheWriteTotal · 输出 $outputTotal · 代理记录费用 $('${0:N4}' -f $cost) · 无有效费用 $unpriced`nCC Switch 代理记录单独统计，可能与 Agent 日志重复；上报费用不代表实际账单。" + $(if (-not $result.Present) { ' 未找到数据库。' } else { '' }) + $(if ($result.Truncated) { ' 仅显示最近 100000 条。' } else { '' }) + $(if ($result.Invalid) { " 跳过无效记录 $($result.Invalid) 条。" } else { '' })
                } else {
                    $summary.Text = "输入 $inputTotal · 缓存读取 $cacheTotal · 缓存写入 $cacheWriteTotal · 输出 $outputTotal · 参考估价 $('${0:N4}' -f $cost) · 未计价 $unpriced`nAgent 本地观测（DeepSeek 仅记录运行期间增量）；参考估价并非实际账单。文件 $($result.FilesScanned)，读取失败 $($result.ReadErrors)，超大文件 $($result.Skipped)。"
                }
                $context.Done = $true
            } catch { $context.Error = $_.Exception.Message; $context.Done = $true; $summary.Text = '读取失败：' + $context.Error }
        }
        if ($context.Done) { $poll.Stop(); $period.Enabled = $true; $source.Enabled = $true; $refresh.Enabled = $true; if ($TestMode) { $window.Close() } }
    }.GetNewClosure()
    $editPrices.Add_Click({ try { $path = & $resolvePrice $baseDirectory $env:LOCALAPPDATA $true; Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $path + '"') } catch { [void][Windows.Forms.MessageBox]::Show($window, '无法打开参考单价文件。', 'tokcat') } }.GetNewClosure())
    $poll.Add_Tick($tick); $refresh.Add_Click($start); $period.Add_SelectedIndexChanged($start); $source.Add_SelectedIndexChanged($start)
    $window.Add_Shown($start)
    try { [void]$window.ShowDialog($Owner) } finally {
        $poll.Stop(); $poll.Dispose()
        if ($context.Worker) { if ($context.Handle -and -not $context.Handle.IsCompleted) { $context.Worker.Stop() }; $context.Worker.Dispose() }
        $window.Dispose()
    }
    if ($TestMode) { return $context.Error }
}
