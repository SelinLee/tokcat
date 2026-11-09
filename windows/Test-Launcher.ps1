$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Launcher.ps1')
function Assert-Launcher($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$tempParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
$testRoot=Join-Path $tempParent ('tokcat-launcher-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$palette=[Drawing.Color[]]@([Drawing.Color]::WhiteSmoke,[Drawing.Color]::White,[Drawing.Color]::Black,[Drawing.Color]::Gray,[Drawing.Color]::AliceBlue)
try {
    $calculations=@{
        '2+3*4'='14'; '(2+3)*4'='20'; '-2^2'='-4'; '(-2)^2'='4'; '2^3^2'='512'; '2^-2'='0.25'; '2**3'='8';
        '200*10%'='20'; '.5*.2'='0.1'; '1e-3*2000'='2'; '0.1+0.2'='0.3'; '1.2'='1.2'; '-0'='0';
        'sqrt(9)+2^3'='11'; 'SQRT(abs(-81))+pow(2,3)'='17'; 'sin(pi/2)'='1'; 'cos(0)'='1'; 'ln(e)'='1';
        'log(100)'='2'; 'log10(1000)'='3'; 'log2(8)'='3'; 'max(2,min(3,4),-1)'='3'; 'round(2.6)'='3';
        'e-e'='0'; 'pi - pi'='0';
        '（２＋３）×４÷２'='10'; '−2+3'='1'
    }
    foreach($expression in $calculations.Keys) {
        $result=[TokcatLauncherCalculator]::Evaluate($expression)
        Assert-Launcher ($null -ne $result -and $result.Result -eq $calculations[$expression]) ('Incorrect calculation '+$expression)
    }
    foreach($expression in @('1/0','sqrt(-1)','log(0)','1e308*1e308','pow(2)','1+','=',('('*70+'1'+')'*70))) {
        $result=[TokcatLauncherCalculator]::Evaluate($expression)
        Assert-Launcher ($null -ne $result -and $null -eq $result.Result -and $result.Error) ('Invalid calculation needs a hint '+$expression)
    }
    foreach($text in @('Chrome','google','Notepad','setup','> Get-Date')) {
        Assert-Launcher ($null -eq [TokcatLauncherCalculator]::Evaluate($text)) ('Non-math text was treated as math '+$text)
    }
    foreach($text in @('1.2','0.1+0.2','2^3','example..com','javascript:alert(1)','file:///C:/test','https://user:pass@example.com','http://example.com:99999')) {
        Assert-Launcher ($null -eq [TokcatLauncherResolver]::HttpUrl($text,$true)) ('Invalid bare website '+$text)
    }
    Assert-Launcher ([TokcatLauncherResolver]::HttpUrl('example.com',$true).AbsoluteUri -eq 'https://example.com/') 'Bare domains open using HTTPS.'
    $settings=New-Object TokcatLauncherSettings
    Assert-Launcher ([TokcatLauncherResolver]::Website('baidu 中文 & 计算',$settings.Websites).AbsoluteUri -eq 'https://www.baidu.com/s?wd=%E4%B8%AD%E6%96%87%20%26%20%E8%AE%A1%E7%AE%97') 'Search text must be URL encoded.'
    Assert-Launcher ($null -eq [TokcatLauncherResolver]::Website('baidu',$settings.Websites)) 'Search keywords need search text.'
    Assert-Launcher ($null -eq [TokcatLauncherResolver]::Website('github extra',$settings.Websites)) 'Direct websites reject unexpected arguments.'
    $apps=[TokcatLauncherApp[]]@(
        [TokcatLauncherApp]@{Name='Google Chrome';Target='chrome.exe'},
        [TokcatLauncherApp]@{Name='记事本';Target='notepad.exe'},
        [TokcatLauncherApp]@{Name='Visual Studio Code';Target='code.exe'}
    )
    $index=[TokcatLauncherIndex]::new($apps)
    Assert-Launcher ($index.Search('Chrome')[0].Target -eq 'chrome.exe') 'Search finds English application names.'
    Assert-Launcher ($index.Search('记事本')[0].Target -eq 'notepad.exe') 'Search finds Chinese application names.'
    Assert-Launcher ($index.Search('notepad')[0].Target -eq 'notepad.exe') 'Search also matches executable aliases.'
    Assert-Launcher ($index.Search('vsc')[0].Target -eq 'code.exe') 'Search matches application initials.'
    if (Test-Path (Join-Path $env:WINDIR 'System32\icu.dll')) {
        Assert-Launcher ($index.Search('jishiben')[0].Target -eq 'notepad.exe') 'Search matches full pinyin.'
        Assert-Launcher ($index.Search('jsb')[0].Target -eq 'notepad.exe') 'Search matches pinyin initials.'
    }
    $path=Join-Path $testRoot 'launcher.json'
    $settings.Save($path)
    foreach($number in 1..55) { $settings.Remember(('query-'+$number),$null) }
    $settings.Remember('query-55',$null); $settings.Save($path)
    $loaded=[TokcatLauncherSettings]::Load($path)
    Assert-Launcher ($loaded.History.Count -eq 50 -and $loaded.History[0].Text -eq 'query-55') 'History is deduplicated, bounded and persisted.'
    $loaded.Commands.Add([TokcatLauncherShortcut]@{Keyword='setup';Name='conflict';Value='Get-Date';Enabled=$true})
    $rejected=$false
    try { $loaded.Validate() } catch { $rejected=$true }
    Assert-Launcher $rejected 'Custom keywords cannot shadow setup.'
    Assert-Launcher ([TokcatLauncherSettings]::Load($path).Commands.Count -eq 0) 'Rejected edits preserve the saved configuration.'
    $invalidPath=Join-Path $testRoot 'future.json'; $future='{"Version":99}'
    [IO.File]::WriteAllText($invalidPath,$future)
    $futureController=[TokcatLauncherController]::new($invalidPath,$palette,$false)
    $futureController.Dispose()
    Assert-Launcher ([IO.File]::ReadAllText($invalidPath) -eq $future) 'Unsupported settings are not overwritten.'

    $uiPath=Join-Path $testRoot 'ui.json'
    $controller=[TokcatLauncherController]::new($uiPath,$palette,$false)
    try {
        $controller.Show(); [Windows.Forms.Application]::DoEvents()
        Assert-Launcher ($controller.Window.Visible -and $controller.Window.Results.Items.Count -eq 0) 'Opening the launcher starts with an empty input.'
        $controller.Window.Query.Text='sqrt(9)+2^3'
        $row=$controller.Window.Results.Items[0]
        Assert-Launcher ($row.Kind -eq 'calculation' -and $row.Value -eq '11') 'Typing calculates through the actual window event.'
        $controller.Window.Query.Text='> Write-Output "a & b"'
        $row=$controller.Window.Results.Items[0]
        Assert-Launcher ($row.Kind -eq 'terminal' -and $row.Value -eq 'Write-Output "a & b"') 'Terminal input keeps exact literal command text.'
        $controller.Window.Query.Text='example.com'
        Assert-Launcher ($controller.Window.Results.Items[0].Kind -eq 'website') 'Website input creates a website action.'
        $controller.Window.Query.Text='setup'
        $opened=@{Value=$false}; $controller.Add_OpenSettings({$opened.Value=$true}.GetNewClosure())
        $controller.SubmitSelection()
        Assert-Launcher ($opened.Value -and -not $controller.Window.Visible) 'Submitting setup closes the launcher and opens the settings callback.'
        Assert-Launcher ([TokcatLauncherSettings]::Load($uiPath).History[0].Text -eq 'setup') 'Successful actions persist in launcher history.'
    } finally { $controller.Dispose() }

    # Exercise native registration and disposal without taking the user's shortcut.
    $hotkeyPath=Join-Path $testRoot 'hotkey.json'; $hotkeySettings=New-Object TokcatLauncherSettings
    $hotkeySettings.Modifiers=7; $hotkeySettings.Key=134; $hotkeySettings.Save($hotkeyPath)
    $first=[TokcatLauncherController]::new($hotkeyPath,$palette,$true)
    try {
        Assert-Launcher ($first.Status.StartsWith('按 ')) 'An unused global shortcut registers.'
        $second=[TokcatLauncherController]::new($hotkeyPath,$palette,$true)
        try { Assert-Launcher ($second.Status.Contains('占用')) 'A shortcut conflict is reported.' } finally { $second.Dispose() }
    } finally { $first.Dispose() }
    $third=[TokcatLauncherController]::new($hotkeyPath,$palette,$true)
    try { Assert-Launcher ($third.Status.StartsWith('按 ')) 'Disposal releases the global shortcut.' } finally { $third.Dispose() }
    Write-Output 'Windows quick launcher checks passed.'
} finally {
    $resolved=[IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith($tempParent,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^tokcat-launcher-test-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
