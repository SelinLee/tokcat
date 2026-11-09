param(
    [switch]$RequireEverything,
    [string]$EverythingTestPath = (Join-Path $PSScriptRoot 'Tokcat.ps1')
)
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
    foreach($text in @('Chrome','google','Notepad','setup','> Get-Date','2026论文.pdf','123report.txt')) {
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
    $shellItem=[TokcatLauncherApp]::FromShellItem('Virtual Application','virtual|registered-app')
    Assert-Launcher ($shellItem.Packaged -and $shellItem.TargetAlias -eq 'virtual|registered-app') 'Shell identifiers retain their opaque parsing names.'
    $withVirtual=[TokcatLauncherApp[]](@($apps)+@($shellItem))
    $mixedIndex=[TokcatLauncherIndex]::new($withVirtual)
    Assert-Launcher ($mixedIndex.Search('chrome')[0].Target -eq 'chrome.exe') 'A virtual shell identifier cannot abort the entire application index.'
    if (Test-Path (Join-Path $env:WINDIR 'System32\icu.dll')) {
        Assert-Launcher ($index.Search('jishiben')[0].Target -eq 'notepad.exe') 'Search matches full pinyin.'
        Assert-Launcher ($index.Search('jsb')[0].Target -eq 'notepad.exe') 'Search matches pinyin initials.'
    }
    $emptyMatches=[TokcatLauncherMatch[]]@()
    $emptyFiles=[TokcatEverythingFile[]]@()
    $files=[TokcatEverythingFile[]]@([TokcatEverythingFile]@{Name='Chrome';FullPath='C:\fixture\Chrome';IsFolder=$true})
    $ranked=[TokcatLauncherRanking]::Build('chrome',$settings,$index.SearchMatches('chrome',200),$files,$true,$null)
    Assert-Launcher ($ranked[0].Kind -eq 'application' -and $ranked[1].Kind -eq 'file') 'Applications rank ahead of matching files in one list.'
    $ranked=[TokcatLauncherRanking]::Build('chrome',$settings,$emptyMatches,$files,$true,$null)
    Assert-Launcher ($ranked.Count -eq 1 -and $ranked[0].Kind -eq 'file') 'Files are offered when no application matches.'
    $ranked=[TokcatLauncherRanking]::Build('unmatched fixture',$settings,$emptyMatches,$emptyFiles,$false,$null)
    Assert-Launcher ($ranked.Count -eq 0) 'Web fallback waits for local sources.'
    $ranked=[TokcatLauncherRanking]::Build('unmatched fixture',$settings,$emptyMatches,$emptyFiles,$true,$null)
    Assert-Launcher ($ranked[0].Kind -eq 'website' -and $ranked[0].Value.Contains('unmatched%20fixture')) 'Web search is suggested after local sources return no match.'
    $ranked=[TokcatLauncherRanking]::Build('sqrt(9)+2^3',$settings,$emptyMatches,$files,$true,$null)
    Assert-Launcher ($ranked[0].Kind -eq 'calculation' -and $ranked[0].Value -eq '11') 'Math results share the weighted list.'
    Assert-Launcher ([TokcatLauncherRanking]::Build('1/0',$settings,$emptyMatches,$emptyFiles,$true,$null).Count -eq 0) 'Invalid math retains its error instead of becoming a web search.'
    $ranked=[TokcatLauncherRanking]::Build('https://example.com',$settings,$emptyMatches,$files,$true,$null)
    Assert-Launcher ($ranked[0].Kind -eq 'website') 'An explicit URL ranks ahead of unrelated files.'
    $settings.Commands.Add([TokcatLauncherShortcut]@{Keyword='clock';Name='查看时间';Value='Get-Date';Enabled=$true})
    $ranked=[TokcatLauncherRanking]::Build('clock',$settings,$emptyMatches,$files,$true,$null)
    Assert-Launcher ($ranked[0].Key -eq 'command:clock' -and $ranked[0].Value -eq 'Get-Date') 'Exact command keywords rank first.'
    $settings.Commands.Clear()
    $ranked=[TokcatLauncherRanking]::Build('baidu 中文 & 计算',$settings,$emptyMatches,$emptyFiles,$true,$null)
    Assert-Launcher ($ranked[0].Key -eq 'website:baidu' -and $ranked[0].Value.Contains('%E4%B8%AD%E6%96%87')) 'Website keyword queries retain URL encoding in unified results.'
    $ranked=[TokcatLauncherRanking]::Build('baidu',$settings,$emptyMatches,$emptyFiles,$true,$null)
    Assert-Launcher ($ranked[0].Kind -eq 'fill' -and $ranked[0].Value -eq 'baidu ') 'A search keyword offers to complete its query.'

    $frequent=New-Object TokcatLauncherSettings
    $editors=[TokcatLauncherApp[]]@(
        [TokcatLauncherApp]@{Name='Alpha Editor';Target='alpha.exe'},
        [TokcatLauncherApp]@{Name='Beta Editor';Target='beta.exe'}
    )
    $editorIndex=[TokcatLauncherIndex]::new($editors)
    Assert-Launcher ([TokcatLauncherRanking]::Build('editor',$frequent,$editorIndex.SearchMatches('editor',200),$emptyFiles,$true,$null)[0].App.Target -eq 'alpha.exe') 'Equal matches initially sort by name.'
    foreach($number in 1..12) { $frequent.Remember('editor',$editors[1]) }
    $frequent.Remember('beta',$editors[1])
    $frequent.Remember('alpha',$editors[0])
    Assert-Launcher ([TokcatLauncherRanking]::Build('editor',$frequent,$editorIndex.SearchMatches('editor',200),$emptyFiles,$true,$null)[0].App.Target -eq 'beta.exe') 'Frequently selected apps gain weight across different queries.'
    Assert-Launcher ([TokcatLauncherRanking]::Build('alpha',$frequent,$editorIndex.SearchMatches('alpha',200),$emptyFiles,$true,$null)[0].App.Target -eq 'alpha.exe') 'Usage never introduces unrelated applications.'
    Assert-Launcher ([TokcatLauncherRanking]::History($frequent)[0].App.Target -eq 'beta.exe') 'Empty input offers frequent history entries.'
    $usagePath=Join-Path $testRoot 'usage.json'; $frequent.Save($usagePath)
    $restored=[TokcatLauncherSettings]::Load($usagePath)
    Assert-Launcher (@($restored.Usage | Where-Object Key -eq 'application:beta.exe')[0].Count -eq 13) 'Usage counts survive restart without duplicate-query loss.'
    $legacyPath=Join-Path $testRoot 'legacy.json'
    [IO.File]::WriteAllText($legacyPath,'{"Version":1,"History":[{"Text":"editor","Application":{"Name":"Beta Editor","Target":"beta.exe"}}]}')
    $legacy=[TokcatLauncherSettings]::Load($legacyPath)
    Assert-Launcher ($legacy.History.Count -eq 1 -and $legacy.Usage[0].Count -eq 1 -and [TokcatLauncherRanking]::History($legacy)[0].Kind -eq 'application') 'Older history is migrated into usage statistics.'

    # Exercise the documented Unicode IPC reply layout, including malformed offsets.
    $names=@('论文.txt','项目','C:'); $paths=@('D:\测试','D:\测试','')
    $stream=New-Object IO.MemoryStream; $writer=New-Object IO.BinaryWriter($stream)
    try {
        foreach($value in @(2,1,3,2,1,3,0)) { $writer.Write([uint32]$value) }
        $stringOffset=28+3*12
        foreach($i in 0..2) {
            $nameBytes=[Text.Encoding]::Unicode.GetBytes($names[$i]+[char]0)
            $pathBytes=[Text.Encoding]::Unicode.GetBytes($paths[$i]+[char]0)
            $flags=@(0,1,2)[$i]
            $writer.Write([uint32]$flags); $writer.Write([uint32]$stringOffset); $writer.Write([uint32]($stringOffset+$nameBytes.Length))
            $stringOffset+=$nameBytes.Length+$pathBytes.Length
        }
        foreach($i in 0..2) {
            $writer.Write([Text.Encoding]::Unicode.GetBytes($names[$i]+[char]0))
            $writer.Write([Text.Encoding]::Unicode.GetBytes($paths[$i]+[char]0))
        }
        $payload=$stream.ToArray()
    } finally { $writer.Dispose(); $stream.Dispose() }
    $parsed=[TokcatEverythingSearch]::ParseReply($payload)
    Assert-Launcher ($parsed.Count -eq 3 -and $parsed[0].FullPath -eq 'D:\测试\论文.txt' -and $parsed[1].IsFolder -and $parsed[2].FullPath -eq 'C:\') 'Unicode file, folder and drive paths decode correctly.'
    foreach($invalid in @('short','count','offset','unaligned','unterminated')) {
        $bad=[byte[]]$payload.Clone()
        switch($invalid) {
            short { $bad=[byte[]]@(0,0) }
            count { [BitConverter]::GetBytes([uint32]129).CopyTo($bad,20) }
            offset { [BitConverter]::GetBytes([uint32]0).CopyTo($bad,32) }
            unaligned { [BitConverter]::GetBytes([uint32]65).CopyTo($bad,32) }
            unterminated { $bad=$bad[0..($bad.Length-2)] }
        }
        $rejected=$false
        try { [void][TokcatEverythingSearch]::ParseReply($bad) } catch { $rejected=$true }
        Assert-Launcher $rejected ('Malformed Everything reply is rejected '+$invalid)
    }
    $provider=[TokcatEverythingSearch]::new(); $reply=@{Value=$null}
    $provider.add_Completed({param($sender,$result) $reply.Value=$result}.GetNewClosure())
    try {
        $provider.Query([string][char]0)
        Assert-Launcher ($reply.Value.Error -and $reply.Value.Files.Count -eq 0) 'Invalid IPC queries report a controlled error.'
        $reply.Value=$null
        if ([TokcatEverythingSearch]::IsRunning) {
            $provider.Query('"'+$EverythingTestPath+'"')
            $deadline=[datetimeoffset]::UtcNow.AddSeconds(6)
            while ($null -eq $reply.Value -and [datetimeoffset]::UtcNow -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
            Assert-Launcher ($null -ne $reply.Value -and -not $reply.Value.Error) ('Live Everything query failed '+$reply.Value.Error)
            if ($RequireEverything) {
                Assert-Launcher (@($reply.Value.Files | Where-Object FullPath -eq $EverythingTestPath).Count -gt 0) 'Live IPC finds the specified indexed test file.'
            }
            $reply.Value=$null; $provider.Query('tokcat'); $provider.Cancel()
            $deadline=[datetimeoffset]::UtcNow.AddMilliseconds(300)
            while ([datetimeoffset]::UtcNow -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
            Assert-Launcher ($null -eq $reply.Value) 'Cancelled IPC replies are ignored.'
            Write-Output 'Live Everything IPC checks passed.'
        } else {
            Assert-Launcher (-not $RequireEverything) 'Everything must be running for the required live IPC check.'
            $provider.Query('tokcat')
            Assert-Launcher ($reply.Value.Error) 'Missing Everything produces a readable status.'
            Write-Output 'Everything client unavailable. Live IPC checks skipped.'
        }
    } finally { $provider.Dispose() }

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
        $deadline=[datetimeoffset]::UtcNow.AddSeconds(30)
        while ($controller.IsIndexing -and [datetimeoffset]::UtcNow -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
        Assert-Launcher (-not $controller.IsIndexing) 'The background application index must finish.'
        $catalog=[TokcatLauncherCatalog]::Scan()
        if ($catalog.Count -gt 0) {
            Assert-Launcher ($controller.IndexedApplicationCount -gt 0) 'The real launcher must publish its background application index.'
            $sample=$catalog[0].Name
            $controller.Window.Query.Text=$sample
            Assert-Launcher ($controller.Window.Results.Items.Count -gt 0) 'Typing an indexed application name must show a result in the real launcher window.'
        }
        if ($RequireEverything) {
            $controller.Window.Query.Text='"'+$EverythingTestPath+'"'
            $deadline=[datetimeoffset]::UtcNow.AddSeconds(6)
            do {
                [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10
                $matchedFiles=@($controller.Window.Results.Items | Where-Object { $_.Kind -eq 'file' -and $_.Value -eq $EverythingTestPath })
            } while ($matchedFiles.Count -eq 0 -and [datetimeoffset]::UtcNow -lt $deadline)
            Assert-Launcher ($matchedFiles.Count -eq 1) 'Typing an indexed file path publishes a file result through the real launcher window.'
        }
        $controller.Window.Query.Text='sqrt(9)+2^3'
        $row=$controller.Window.Results.Items[0]
        Assert-Launcher ($row.Kind -eq 'calculation' -and $row.Value -eq '11') 'Typing calculates through the actual window event.'
        $controller.Window.Query.Text='> Write-Output "a & b"'
        $row=$controller.Window.Results.Items[0]
        Assert-Launcher ($row.Kind -eq 'terminal' -and $row.Value -eq 'Write-Output "a & b"') 'Terminal input keeps exact literal command text.'
        $controller.Window.Query.Text='example.com'
        Assert-Launcher ($controller.Window.Results.Items[0].Kind -eq 'website') 'Website input creates a website action.'
        $controller.Window.Query.Text='baidu'
        $controller.SubmitSelection()
        Assert-Launcher ($controller.Window.Query.Text -eq 'baidu ' -and $controller.Window.Visible) 'Submitting an incomplete search keyword fills the input.'
        $controller.Window.Query.Text='selection fixture'
        $firstRow=[TokcatLauncherResult]@{Title='first';Key='first'}
        $secondRow=[TokcatLauncherResult]@{Title='second';Key='second'}
        $controller.Window.SetResults([TokcatLauncherResult[]]@($firstRow,$secondRow),'fixture')
        $controller.Window.Results.SelectedIndex=1
        $controller.Window.SetResults([TokcatLauncherResult[]]@($secondRow,$firstRow),'fixture refresh')
        Assert-Launcher ($controller.Window.Results.SelectedItem.Key -eq 'second') 'Asynchronous results preserve the selected action.'
        $controller.Window.Query.Text='setup'
        $opened=@{Value=$false}; $controller.Add_OpenSettings({$opened.Value=$true}.GetNewClosure())
        $controller.SubmitSelection()
        Assert-Launcher ($opened.Value -and -not $controller.Window.Visible) 'Submitting setup closes the launcher and opens the settings callback.'
        Assert-Launcher ([TokcatLauncherSettings]::Load($uiPath).History[0].Text -eq 'setup') 'Successful actions persist in launcher history.'
        $controller.Show()
        Assert-Launcher ($controller.Window.Query.TextLength -eq 0 -and $controller.Window.Results.Items[0].Kind -eq 'settings') 'Reopening with empty input shows actionable history.'
        $controller.SubmitSelection()
        $saved=[TokcatLauncherSettings]::Load($uiPath)
        Assert-Launcher ($saved.History.Count -eq 1 -and $saved.Usage[0].Count -eq 2) 'Choosing history increments usage without duplicating the same input.'
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
