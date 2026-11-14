$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Launcher.ps1')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TokcatImeInputTest {
    [StructLayout(LayoutKind.Sequential)] struct Msg { public IntPtr window; public uint id; public UIntPtr w; public IntPtr l; public uint time; public int x,y; public uint extra; }
    [DllImport("user32.dll")] static extern bool PeekMessage(out Msg msg,IntPtr hwnd,uint first,uint last,uint remove);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref Msg msg);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref Msg msg);
    public static void PumpOne() {
        Msg msg;
        if(PeekMessage(out msg, IntPtr.Zero, 0, 0, 1)) { TranslateMessage(ref msg); DispatchMessage(ref msg); }
    }
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr handle,int message,IntPtr first,IntPtr second);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr handle,int message,IntPtr first,IntPtr second);
}
'@
function Assert-Input($condition,[string]$message) { if(-not $condition) { throw $message } }
function Pump-Input([int]$milliseconds) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do { [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 5 } while($clock.ElapsedMilliseconds -lt $milliseconds)
}
foreach($count in @(0,1,4,9,10,50,200)) {
    $layout=[TokcatRadialLayout]::new([double[]]@(1..$count | Select-Object -First $count | ForEach-Object {1}))
    Assert-Input ($layout.RingCount -le 3 -and $layout.Slots.Count -le 9 -and $layout.Diameter -le 450) 'All result counts must remain within three radii.'
}
$weighted=[TokcatRadialLayout]::new([double[]]@(1..50 | ForEach-Object {$_/10.0}))
Assert-Input ($weighted.Slots.Count -eq 9 -and $weighted.Slots[0].Index -eq 49 -and $weighted.Slots[-1].Index -eq 41) 'Capping must retain the highest-weight choices.'
$tempParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
$testRoot=Join-Path $tempParent ('tokcat-input-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$palette=[Drawing.Color[]]@([Drawing.Color]::Black,[Drawing.Color]::FromArgb(32,35,40),[Drawing.Color]::White,[Drawing.Color]::Silver,[Drawing.Color]::DarkCyan)
$controller=$null
try {
    $settings=[TokcatLauncherSettings]::new();$settings.Skin='radial'
    $settingsPath=Join-Path $testRoot 'launcher.json';$settings.Save($settingsPath)
    $controller=[TokcatLauncherController]::new($settingsPath,$palette,$false)
    $deadline=[Diagnostics.Stopwatch]::StartNew()
    while($controller.IsIndexing -and $deadline.ElapsedMilliseconds -lt 30000) { Pump-Input 10 }
    Assert-Input (-not $controller.IsIndexing) 'The initial index must finish before installing fixtures.'
    $apps=[TokcatLauncherApp[]]@(
        [TokcatLauncherApp]@{Name='微信';Alias='weixin';Target=(Join-Path $testRoot 'wechat.exe')},
        [TokcatLauncherApp]@{Name='微信开发者工具';Alias='weixin kaifazhe gongju';Target=(Join-Path $testRoot 'wechat-tools.exe')},
        [TokcatLauncherApp]@{Name='网易云音乐';Alias='wangyi yunyinyue';Target=(Join-Path $testRoot 'cloudmusic.exe')},
        [TokcatLauncherApp]@{Name='Visual Studio';Alias='visual studio';Target=(Join-Path $testRoot 'studio.exe')}
    )
    $indexField=$controller.GetType().GetField('index',[Reflection.BindingFlags]'Instance,NonPublic')
    $indexField.SetValue($controller,[TokcatLauncherIndex]::new($apps))
    $controller.Show();$window=$controller.Window;$editor=$window.Query
    $previewMethod=$editor.GetType().GetMethod('SetCompositionPreview',[Reflection.BindingFlags]'Instance,NonPublic')
    # Sogou's floating reading window can send only candidate notifications and
    # processed keys. Exercise that path without injecting a composition string.
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0282,[IntPtr]5,[IntPtr]1)
    foreach($key in @(87,69,73)) {
        [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0282,[IntPtr]3,[IntPtr]1)
        [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0101,[IntPtr]$key,[IntPtr]::Zero)
    }
    Assert-Input ($editor.Composing -and $editor.Text -eq '' -and $editor.DisplayText -eq 'wei') 'Candidate-only IMEs must expose their uncommitted spelling to matching.'
    Assert-Input (@($window.Results.Items | Where-Object Title -eq '微信').Count -eq 1) 'The candidate notification path must match applications before Chinese is committed.'
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0101,[IntPtr]8,[IntPtr]::Zero)
    Assert-Input ($editor.DisplayText -eq 'we') 'Backspacing while candidates are open must update the pending spelling.'
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0100,[IntPtr]229,[IntPtr](0x17 -shl 16))
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0101,[IntPtr]73,[IntPtr]::Zero)
    Assert-Input ($editor.DisplayText -eq 'wei') 'A physical processed key and its key-up must add the reading character once.'
    $editor.Text='微信'
    Assert-Input (-not $editor.Composing -and $editor.DisplayText -eq '微信') 'Committing candidate-only input must discard its provisional spelling.'
    $editor.Text='网';$editor.Select(1,0)
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0282,[IntPtr]5,[IntPtr]1)
    foreach($key in @(89,73)) { [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0101,[IntPtr]$key,[IntPtr]::Zero) }
    Assert-Input ($editor.DisplayText -eq '网yi' -and @($window.Results.Items | Where-Object Title -eq '网易云音乐').Count -eq 1) 'Candidate-only spelling must retain the committed Chinese prefix.'
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0282,[IntPtr]4,[IntPtr]1)
    Assert-Input (-not $editor.Composing -and $editor.DisplayText -eq '网') 'Closing the candidate window must discard pending input.'
    $editor.Text=''
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0101,[IntPtr]87,[IntPtr]::Zero)
    Assert-Input ($editor.DisplayText -eq '' -and -not $editor.Composing) 'Key-up outside a candidate session must not manufacture input.'
    # Measure a newly matched application's first clickable native frame while
    # IME preedit changes. Reading Results.Items only measures ranking.
    $surface=$window.Radial.GetType().GetField('surface',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($window.Radial)
    $displayed=$surface.GetType().GetField('displayedRegions',[Reflection.BindingFlags]'Instance,NonPublic')
    $visibilityTimes=@()
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x010D,[IntPtr]::Zero,[IntPtr]::Zero)
    foreach($spelling in @('wei','wangyi','visual','wei','wangyi','visual','wei','wangyi','visual')) {
        $started=[Diagnostics.Stopwatch]::StartNew()
        [void]$previewMethod.Invoke($editor,[object[]]@($spelling,$spelling.Length))
        $app=@($window.Results.Items | Where-Object Kind -eq 'application')[0]
        Assert-Input ($null -ne $app) 'IME preedit must return the matching application.'
        do {
            [TokcatImeInputTest]::PumpOne()
            $visible=@($displayed.GetValue($surface) | Where-Object Id -eq $app.Key).Count -gt 0
        } while(-not $visible -and $started.ElapsedMilliseconds -lt 750)
        Assert-Input $visible 'The latest match must reach the native wheel.'
        $visibilityTimes+=$started.Elapsed.TotalMilliseconds
        Pump-Input 45
    }
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x010E,[IntPtr]::Zero,[IntPtr]::Zero)
    $orderedTimes=@($visibilityTimes | Select-Object -Skip 1 | Sort-Object)
    Write-Output ('IME update to first clickable result: median '+[Math]::Round($orderedTimes[$orderedTimes.Count/2],1)+' ms; maximum '+[Math]::Round($orderedTimes[-1],1)+' ms.')
    Assert-Input ($orderedTimes[$orderedTimes.Count/2] -lt 90) 'New matches should be visible and clickable without waiting for the entrance fade.'
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x010D,[IntPtr]::Zero,[IntPtr]::Zero)
    [void]$previewMethod.Invoke($editor,[object[]]@('wei',3))
    Assert-Input ($editor.Composing -and $editor.Text -eq '' -and $editor.DisplayText -eq 'wei') 'IME preedit must remain separate from committed text.'
    Assert-Input (@($window.Results.Items | Where-Object {$_.Kind -eq 'application' -and $_.Title -eq '微信'}).Count -eq 1) 'Pinyin preedit must match applications before Chinese is committed.'
    [void]$previewMethod.Invoke($editor,[object[]]@("wei'xin",7))
    Assert-Input (@($window.Results.Items | Where-Object {$_.Kind -eq 'application' -and $_.Title -eq '微信开发者工具'}).Count -eq 1) 'Pinyin syllable separators must match immediately.'
    [void]$previewMethod.Invoke($editor,[object[]]@("wang'yi",7))
    Assert-Input (@($window.Results.Items | Where-Object {$_.Kind -eq 'application' -and $_.Title -eq '网易云音乐'}).Count -eq 1 -and @($window.Results.Items | Where-Object {$_.Kind -eq 'application' -and $_.Title -eq '微信'}).Count -eq 0) 'Each preedit update must replace the old matches.'
    Assert-Input ([TokcatRadialMotion]::ReducedMotion -or $window.Radial.Motion.IsAnimating) 'Preedit matches update immediately while their reflow remains animated.'
    $keydown=$window.GetType().GetMethod('QueryKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
    $enter=[Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::Enter)
    [void]$keydown.Invoke($window,[object[]]@($editor,$enter))
    Assert-Input ($window.Visible -and $editor.Composing -and -not $enter.SuppressKeyPress) 'Enter must remain available to the IME for candidate selection.'
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x010E,[IntPtr]::Zero,[IntPtr]::Zero)
    Assert-Input (-not $editor.Composing -and $window.Results.Items.Count -eq 0) 'Cancelling IME input must restore the committed-query results.'

    $editor.Text='Visual old';$editor.Select(7,3)
    Assert-Input ([TokcatRadialMotion]::ReducedMotion -or $window.Radial.Motion.IsAnimating) 'Committed typing must retain the reflow animation.'
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x010D,[IntPtr]::Zero,[IntPtr]::Zero)
    [void]$previewMethod.Invoke($editor,[object[]]@('stu',3))
    Assert-Input ($editor.DisplayText -eq 'Visual stu' -and @($window.Results.Items | Where-Object Title -eq 'Visual Studio').Count -eq 1) 'Composition must replace the selected span and retain the committed prefix.'
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x010E,[IntPtr]::Zero,[IntPtr]::Zero)
    $editor.Text=''
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x010D,[IntPtr]::Zero,[IntPtr]::Zero)
    [void]$previewMethod.Invoke($editor,[object[]]@('微信',2))
    Assert-Input (@($window.Results.Items | Where-Object Title -eq '微信').Count -eq 1 -and $editor.Text -eq '') 'Uncommitted Chinese candidate text must also match.'
    [void]$previewMethod.Invoke($editor,[object[]]@('',0))
    $editor.Text='微信'
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x010E,[IntPtr]::Zero,[IntPtr]::Zero)
    Assert-Input ($editor.DisplayText -eq '微信' -and @($window.Results.Items | Where-Object Title -eq '微信').Count -eq 1) 'Committing must keep the selected Chinese text exactly once.'
    $editor.Text='网';$editor.Select(1,0)
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x010D,[IntPtr]::Zero,[IntPtr]::Zero)
    [void]$previewMethod.Invoke($editor,[object[]]@('yi',2))
    Assert-Input ($editor.DisplayText -eq '网yi' -and @($window.Results.Items | Where-Object Title -eq '网易云音乐').Count -eq 1) 'A committed Chinese prefix plus pending pinyin must also match.'
    [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x010E,[IntPtr]::Zero,[IntPtr]::Zero)

    $window.IsPreview=$true
    $inputTimes=[Collections.Generic.List[double]]::new()
    foreach($iteration in 1..3) {
        foreach($query in @('w','we','wei','weix','weixin','微信','微信kai','网yi','wangyi','Visual','Visual stu')) {
            $watch=[Diagnostics.Stopwatch]::StartNew();$editor.Text=$query;$editor.Select($editor.TextLength,0)
            $frame=$window.Radial.Render();$frame.Dispose();$watch.Stop()
            if($iteration -gt 1) { $inputTimes.Add($watch.Elapsed.TotalMilliseconds) }
        }
    }
    $ordered=@($inputTimes | Sort-Object);$inputMedian=$ordered[$ordered.Count/2]
    Assert-Input ($inputMedian -lt 40) ('Actual query changes, matching and rendering must stay below 40 ms; observed '+[Math]::Round($inputMedian,2)+' ms.')
    $editor.Text=''
    foreach($keyCode in @(119,101,105,8,8)) {
        [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0102,[IntPtr]$keyCode,[IntPtr]::Zero)
    }
    Assert-Input ($editor.Text -eq 'w' -and @($window.Results.Items | Where-Object Title -eq '微信').Count -eq 1) 'Typing and backspacing through a prefix must immediately restore its earlier matches.'
    $editor.SelectAll()
    foreach($keyCode in @(118,105,115)) {
        [void][TokcatImeInputTest]::SendMessage($editor.Handle,0x0102,[IntPtr]$keyCode,[IntPtr]::Zero)
    }
    Assert-Input ($editor.Text -eq 'vis' -and @($window.Results.Items | Where-Object Title -eq 'Visual Studio').Count -eq 1) 'Replacing the current prefix must immediately show matches for the new word.'
    Write-Output ('Query change, matching and render median: '+[Math]::Round($inputMedian,2)+' ms.')
    $window.IsPreview=$false

    $rows=[TokcatLauncherResult[]]@(1..50 | ForEach-Object {[TokcatLauncherResult]@{Title=('Choice '+$_);Kind='fill';Key=('choice:'+$_);RadialWeight=(51-$_)}})
    $search=[TokcatLauncherResult]@{Title='网页搜索';Kind='website';Key='web-search';RadialWeight=0.25}
    $window.SetResults([TokcatLauncherResult[]]@($rows+$search),'')
    $window.Radial.Motion.Finish()
    Assert-Input ($window.Results.Items.Count -eq 9 -and $window.Radial.Layout.RingCount -eq 3 -and @($window.Results.Items | Where-Object Key -eq 'web-search').Count -eq 1) 'The real window must cap overflow and reserve web search.'
    Assert-Input ($window.Results.Items[0].Key -eq 'choice:1' -and @($window.Results.Items | Where-Object Key -eq 'choice:9').Count -eq 0) 'Only the top eight primary choices accompany web search.'
    Assert-Input (@($window.Radial.Motion.Entries | Where-Object {$_.Ring -ge 3}).Count -eq 0 -and $window.Radial.Motion.Extent -eq 225) 'Presentation and hit testing must never grow a fourth ring.'
    $window.Appearance.Configure('classic',$false)
    $window.SetResults($rows,'')
    Assert-Input ($window.Results.Items.Count -eq 50) 'The radial display limit must not alter Classic.'

    # Measure changed search results, including a fresh mask/content rebuild,
    # rather than a stationary frame that can conceal keystroke stalls.
    $window.Hide();$window.IsPreview=$true;$window.Appearance.Configure('radial',$false)
    $times=[Collections.Generic.List[double]]::new()
    foreach($iteration in 1..30) {
        $count=@(9,4,9,2,8,9)[($iteration-1)%6]
        $rows=[TokcatLauncherResult[]]@(0..($count-1) | ForEach-Object {[TokcatLauncherResult]@{Title=('应用 '+$iteration+'-'+$_);Kind='settings';Key=('typing:'+$iteration+':'+$_);RadialWeight=(2/(1+$_*.25))}})
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $editor.Text='连续输入'+$iteration;$editor.Select($editor.TextLength,0)
        $window.SetResults($rows,'');$frame=$window.Radial.Render();$frame.Dispose();$watch.Stop()
        Assert-Input (-not $window.Radial.Motion.IsAnimating -and -not $window.Results.Visible) 'Static previews must settle immediately without showing the hidden results list.'
        if($iteration -gt 6) { $times.Add($watch.Elapsed.TotalMilliseconds) }
    }
    $ordered=@($times | Sort-Object);$median=$ordered[$ordered.Count/2]
    Assert-Input ($median -lt 40) ('Changed-result typing must render below 40 ms; observed '+[Math]::Round($median,2)+' ms.')
    Write-Output ('Changed-result typing render median: '+[Math]::Round($median,2)+' ms; maximum: '+[Math]::Round(($times | Measure-Object -Maximum).Maximum,2)+' ms.')

    $masks=$window.Radial.MaskBuildCount;$contents=$window.Radial.ContentBuildCount
    $hashes=@()
    foreach($text in @('输入一','输入二')) {
        $editor.Text=$text;$editor.Select($editor.TextLength,0)
        $frame=$window.Radial.Render();$stream=[IO.MemoryStream]::new();$hash=[Security.Cryptography.SHA256]::Create()
        try { $frame.Save($stream,[Drawing.Imaging.ImageFormat]::Png);$hashes += [Convert]::ToBase64String($hash.ComputeHash($stream.ToArray())) }
        finally { $hash.Dispose();$stream.Dispose();$frame.Dispose() }
    }
    Assert-Input ($hashes[0] -ne $hashes[1] -and $window.Radial.MaskBuildCount -eq $masks -and $window.Radial.ContentBuildCount -eq $contents) 'Changing input must change its pixels while reusing result labels, glows and geometry.'
    $rows[0].Title='新结果文字';$window.SetResults($rows,'');$frame=$window.Radial.Render();$frame.Dispose()
    Assert-Input ($window.Radial.ContentBuildCount -eq $contents+1) 'A changed result title must invalidate the cached results.'
    Write-Output 'Windows live IME matching and three-ring checks passed.'

    # Exercise the production host. This thread deliberately does not pump the
    # dashboard while the native editor receives WM_CHAR messages.
    $dashboard=[Windows.Forms.Form]::new()
    $hostSettings=Join-Path $testRoot 'isolated-launcher.json';$settings.Save($hostSettings)
    $inputHost=$null
    try {
        $inputHost=[TokcatLauncherHost]::new($dashboard,$hostSettings,$palette,$false)
        $hostController=$inputHost.GetType().GetField('controller',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($inputHost)
        $hostWindow=$hostController.Window
        $inputHost.Show()
        $readHandle=[Delegate]::CreateDelegate([Func[IntPtr]],$hostWindow.Query,'get_Handle')
        $handle=[IntPtr]$hostWindow.Invoke($readHandle)
        $hostSurface=$hostWindow.Radial.GetType().GetField('surface',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($hostWindow.Radial)
        $presents=$hostSurface.NativePresentCount
        foreach($letter in 'weixin'.ToCharArray()) {
            [void][TokcatImeInputTest]::PostMessage($handle,0x0102,[IntPtr][int]$letter,[IntPtr]::Zero)
            [Threading.Thread]::Sleep(40)
        }
        $readText=[Delegate]::CreateDelegate([Func[string]],$hostWindow.Query,'get_Text')
        $read=$hostWindow.BeginInvoke($readText)
        [Threading.Thread]::Sleep(150)
        Assert-Input ($read.IsCompleted -and $hostWindow.EndInvoke($read) -eq 'weixin' -and $hostSurface.NativePresentCount -gt $presents) 'Typing and visible frames must progress independently of a blocked dashboard.'
        Write-Output 'Native typing and presentation continued with the dashboard thread occupied.'
        $page=$inputHost.CreateSettingsPage()
        $dashboard.Controls.Add($page);$dashboard.Show()
        $skin=$page.Editor.GetType().GetField('skin',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($page.Editor)
        $skin.SelectedIndex=1
        $page.Editor.SaveSettings.PerformClick()
        Assert-Input (([TokcatLauncherSettings]::Load($hostSettings)).Skin -eq 'cyber' -and $page.Editor.PreviewSkin -eq 'cyber') 'Dashboard settings must save and reload on the owning threads.'
    } finally { if($inputHost) { $inputHost.Dispose() };$dashboard.Dispose() }
} finally {
    if($controller) { $controller.Dispose() }
    $resolved=[IO.Path]::GetFullPath($testRoot)
    if($resolved.StartsWith($tempParent,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^tokcat-input-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
