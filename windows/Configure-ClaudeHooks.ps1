param(
    [string]$SettingsPath = (Join-Path $env:USERPROFILE '.claude\settings.json'),
    [switch]$Remove
)
$ErrorActionPreference = 'Stop'
$events = @('UserPromptSubmit','PreToolUse','PostToolUse','PostToolUseFailure','Notification','PermissionRequest','PermissionDenied','Stop','StopFailure','SessionEnd')
$hookPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'ClaudeHook.ps1')).Path
$directory = Split-Path -Parent $SettingsPath
if (-not $directory) { throw 'SettingsPath must include a directory.' }
$original = if ([IO.File]::Exists($SettingsPath)) { [IO.File]::ReadAllText($SettingsPath, [Text.Encoding]::UTF8) } else { $null }
if ($null -ne $original) {
    $root = $original | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $root -or $root -is [array] -or $root -isnot [pscustomobject]) { throw 'Claude settings must be a JSON object; no changes were made.' }
} else { $root = [pscustomobject]@{} }
$prop = $root.PSObject.Properties['hooks']
if ($null -eq $prop) { $hooks = [pscustomobject]@{}; $root | Add-Member -NotePropertyName 'hooks' -NotePropertyValue $hooks }
elseif ($null -eq $prop.Value -or $prop.Value -isnot [pscustomobject]) { throw 'The existing hooks setting is not an object; no changes were made.' }
else { $hooks = $prop.Value }
foreach ($name in $events) {
    $prop = $hooks.PSObject.Properties[$name]
    $groups = @()
    if ($prop) { $groups = $prop.Value }
    if ($null -ne $groups -and $groups -isnot [array]) { throw "The existing $name hooks are not an array; no changes were made." }
    $retained = @()
    foreach ($group in $groups) {
        if ($null -eq $group -or $group -isnot [pscustomobject] -or $null -eq $group.PSObject.Properties['hooks'] -or $group.hooks -isnot [array]) { throw "The existing $name hook group is invalid; no changes were made." }
        $handlers = @($group.hooks | Where-Object {
            $argsProperty = $_.PSObject.Properties['args']
            -not ($_.command -eq 'powershell.exe' -and $argsProperty -and @($_.args).Count -ge 1 -and $_.args[-1] -eq $hookPath)
        })
        if ($handlers.Count -gt 0) { $group.hooks = $handlers; $retained += $group }
    }
    if (-not $Remove) {
        $retained += [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = 'powershell.exe'; args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$hookPath); timeout = 10; onFailure = 'continue' }) }
    }
    if ($prop) { $hooks.PSObject.Properties.Remove($name) }
    if ($retained.Count -gt 0) { $hooks | Add-Member -NotePropertyName $name -NotePropertyValue $retained }
}
[IO.Directory]::CreateDirectory($directory) | Out-Null
if ($null -ne $original) {
    $backup = $SettingsPath + '.tokcat-backup-' + [datetime]::UtcNow.ToString('yyyyMMddHHmmssfff') + '-' + [guid]::NewGuid().ToString('N')
    [IO.File]::Copy($SettingsPath, $backup, $false)
}
$tmp = Join-Path $directory ('.tokcat-settings-' + [guid]::NewGuid().ToString('N') + '.tmp')
$json = $root | ConvertTo-Json -Depth 100
[IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
if ([IO.File]::Exists($SettingsPath)) { [IO.File]::Replace($tmp, $SettingsPath, [System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($tmp, $SettingsPath) }
if ($Remove) { Write-Host 'tokcat Claude hooks removed. Restart Claude Code sessions.' } else { Write-Host 'tokcat Claude hooks installed. Restart Claude Code sessions.' }
if ($backup) { Write-Host "Previous settings backup: $backup" }
