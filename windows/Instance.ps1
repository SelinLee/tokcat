function Open-TokcatInstance([string]$Identity) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $digest = $hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Identity.ToLowerInvariant())) } finally { $hash.Dispose() }
    $suffix = [BitConverter]::ToString($digest, 0, 12).Replace('-', '')
    $event = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, ('Local\TokcatShow-' + $suffix))
    try {
        $created = $false
        $mutex = New-Object Threading.Mutex($true, ('Local\TokcatInstance-' + $suffix), [ref]$created)
        return [pscustomobject]@{ Mutex=$mutex; Event=$event; IsFirst=$created }
    } catch { $event.Dispose(); throw }
}

function Close-TokcatInstance($Guard) {
    if ($null -eq $Guard) { return }
    if ($Guard.IsFirst) { try { $Guard.Mutex.ReleaseMutex() } catch [ApplicationException] {} }
    $Guard.Mutex.Dispose(); $Guard.Event.Dispose()
}
