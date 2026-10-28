$ErrorActionPreference = 'Stop'
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$testRoot = Join-Path $tempParent ('tokcat-package-test-' + [guid]::NewGuid().ToString('N'))
try {
    $output = Join-Path $testRoot 'output'
    # Exercise paths with spaces and non-ASCII characters on Windows PowerShell 5.1.
    $extract = Join-Path $testRoot ('extract ' + [char]0x6D4B + [char]0x8BD5)
    [IO.Directory]::CreateDirectory($output) | Out-Null
    $archive = & (Join-Path $PSScriptRoot 'Package.ps1') -OutputDirectory $output
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw 'Package was not created.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $extract
    $package = Join-Path $extract 'tokcat-windows'
    foreach ($file in @('Tokcat.cmd','Tokcat.ps1','Instance.ps1','Monitor.ps1','Conversation.ps1','Usage.ps1','UsageWindow.ps1','UsagePricing.json','ClaudeHook.ps1','Configure-ClaudeHooks.ps1','CodexLogReader.cs','WorkCatalog.cs','SystemMetrics.cs','GpuMetrics.cs','README.md','README.zh-CN.md','Test-Monitor.ps1','LICENSE')) {
        if (-not (Test-Path -LiteralPath (Join-Path $package $file) -PathType Leaf)) { throw "Package is missing $file" }
    }
    $settingsPath = Join-Path $testRoot 'claude-fixture\settings.json'
    & powershell.exe -NoProfile -File (Join-Path $package 'Configure-ClaudeHooks.ps1') -SettingsPath $settingsPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The extracted Claude hook installer failed.' }
    $configured = [IO.File]::ReadAllText($settingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($configured.hooks.Stop[0].hooks[0].args[-1] -ne (Join-Path $package 'ClaudeHook.ps1')) { throw 'The extracted hook path was not preserved.' }
    & powershell.exe -NoProfile -File (Join-Path $package 'Test-Monitor.ps1') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The extracted monitor tests failed.' }
    $codexRoot = Join-Path $testRoot 'codex'
    $sessions = Join-Path $codexRoot 'sessions'
    [IO.Directory]::CreateDirectory($sessions) | Out-Null
    $time = [datetimeoffset]::UtcNow.ToString('o')
    $log = '{"type":"session_meta","payload":{"id":"package-fixture"}}' + "`n" + '{"type":"turn_context","payload":{"model":"gpt-5.6-sol"}}' + "`n" + '{"type":"event_msg","timestamp":"' + $time + '","payload":{"type":"task_started","turn_id":"t1"}}' + "`n" + '{"type":"response_item","payload":{"type":"message","role":"user","content":"fixture conversation"}}' + "`n" + '{"type":"event_msg","timestamp":"' + $time + '","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3},"last_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}}}}' + "`n"
    [IO.File]::WriteAllText((Join-Path $sessions 'rollout-package.jsonl'), $log, (New-Object Text.UTF8Encoding($false)))
    $previousProfile = $env:USERPROFILE; $previousAppData = $env:APPDATA; $previousLocalData = $env:LOCALAPPDATA
    try {
        $env:USERPROFILE = $testRoot; $env:APPDATA = $testRoot; $env:LOCALAPPDATA = $testRoot
        & powershell.exe -NoProfile -STA -File (Join-Path $package 'Tokcat.ps1') -CodexHome $codexRoot -SmokeTest
        if ($LASTEXITCODE -ne 0) { throw 'The extracted package failed the window and tray smoke test.' }
    } finally { $env:USERPROFILE = $previousProfile; $env:APPDATA = $previousAppData; $env:LOCALAPPDATA = $previousLocalData }
    Write-Host 'Windows package checks passed.'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        if ($resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^tokcat-package-test-[0-9a-f]{32}$') {
            try { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop } catch { Write-Warning "Temporary test directory retained because a file is in use: $resolved" }
        } else { throw 'Refusing to remove an unexpected test path.' }
    }
}
