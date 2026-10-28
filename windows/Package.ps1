param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$files = @('Tokcat.cmd','Tokcat.ps1','Monitor.ps1','Conversation.ps1','ClaudeHook.ps1','Configure-ClaudeHooks.ps1','CodexLogReader.cs','WorkCatalog.cs','SystemMetrics.cs','README.md','README.zh-CN.md','Test-Monitor.ps1')
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$name = 'tokcat-windows-' + [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.zip'
$destination = Join-Path $OutputDirectory $name
$output = $null; $archive = $null; $created = $false; $complete = $false
try {
    # CreateNew prevents overwriting an existing artifact, including on collision.
    $output = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $created = $true
    $archive = New-Object IO.Compression.ZipArchive($output, [IO.Compression.ZipArchiveMode]::Create, $true)
    foreach ($file in ($files + 'LICENSE')) {
        $source = if ($file -eq 'LICENSE') { Join-Path (Split-Path $PSScriptRoot -Parent) 'LICENSE' } else { Join-Path $PSScriptRoot $file }
        $sourceStream = $null; $entryStream = $null
        try {
            $sourceStream = [IO.File]::Open($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            $entry = $archive.CreateEntry('tokcat-windows/' + $file, [IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()
            $sourceStream.CopyTo($entryStream)
        } finally { if ($entryStream) { $entryStream.Dispose() }; if ($sourceStream) { $sourceStream.Dispose() } }
    }
    $archive.Dispose(); $archive = $null
    $output.Dispose(); $output = $null
    $complete = $true
    Write-Output $destination
} finally {
    if ($archive) { $archive.Dispose() }; if ($output) { $output.Dispose() }
    if ($created -and -not $complete -and [IO.File]::Exists($destination)) { [IO.File]::Delete($destination) }
}
