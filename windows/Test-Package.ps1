$ErrorActionPreference = 'Stop'
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$testRoot = Join-Path $tempParent ('tokcat-package-test-' + [guid]::NewGuid().ToString('N'))
try {
    $output = Join-Path $testRoot 'output'
    $extract = Join-Path $testRoot 'extract'
    [IO.Directory]::CreateDirectory($output) | Out-Null
    $archive = & (Join-Path $PSScriptRoot 'Package.ps1') -OutputDirectory $output
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw 'Package was not created.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $extract
    $package = Join-Path $extract 'tokcat-windows'
    foreach ($file in @('Tokcat.cmd','Tokcat.ps1','Monitor.ps1','ClaudeHook.ps1','Configure-ClaudeHooks.ps1','CodexLogReader.cs','WorkCatalog.cs','SystemMetrics.cs','README.md','README.zh-CN.md','Test-Monitor.ps1','LICENSE')) {
        if (-not (Test-Path -LiteralPath (Join-Path $package $file) -PathType Leaf)) { throw "Package is missing $file" }
    }
    $codexRoot = Join-Path $testRoot 'codex'
    $sessions = Join-Path $codexRoot 'sessions'
    [IO.Directory]::CreateDirectory($sessions) | Out-Null
    $time = [datetimeoffset]::UtcNow.ToString('o')
    $log = '{"type":"session_meta","payload":{"id":"package-fixture"}}' + "`n" + '{"type":"event_msg","timestamp":"' + $time + '","payload":{"type":"task_started","turn_id":"t1"}}' + "`n"
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
            Remove-Item -LiteralPath $resolved -Recurse -Force
        } else { throw 'Refusing to remove an unexpected test path.' }
    }
}
