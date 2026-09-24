<#
.SYNOPSIS
  Send one text command to a running OPEN//77 game client's debug bridge (named pipe
  Open77.Debug.<pid>, protocol 1: one text command in, one "OK ..."/"ERR ..." line out).
  Read-only diagnostics work during a session; state-changing lab commands are refused then.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-bridge.ps1 -Command ping [-ProcessId 12345]
  Without -ProcessId the newest Cyberpunk2077.exe is used.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$Command,
    [int]$ProcessId = 0,
    [int]$TimeoutMs = 8000
)
$ErrorActionPreference = 'Stop'
if ($ProcessId -eq 0) {
    $p = Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending | Select-Object -First 1
    if (-not $p) { throw 'No Cyberpunk2077.exe running' }
    $ProcessId = $p.Id
}
$pipeName = "Open77.Debug.$ProcessId"
$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
try {
    $pipe.Connect($TimeoutMs)
} catch {
    throw "Could not connect to \\.\pipe\$pipeName : $($_.Exception.Message)"
}
try {
    try { $pipe.ReadMode = [System.IO.Pipes.PipeTransmissionMode]::Message } catch {}
    $bytes = [Text.Encoding]::UTF8.GetBytes($Command + "`n")
    $pipe.Write($bytes, 0, $bytes.Length)
    $pipe.Flush()
    $buf = New-Object byte[] 65536
    $sb = New-Object Text.StringBuilder
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        $task = $pipe.ReadAsync($buf, 0, $buf.Length)
        while (-not $task.IsCompleted -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }
        if (-not $task.IsCompleted) { break }
        $n = $task.Result
        if ($n -le 0) { break }
        [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $n))
        $text = $sb.ToString()
        if ($text.EndsWith("`n") -or ($pipe.ReadMode -eq 'Message' -and $pipe.IsMessageComplete)) { break }
    } while ((Get-Date) -lt $deadline)
    $reply = $sb.ToString().TrimEnd("`r", "`n")
    Write-Output $reply
    if ($reply.StartsWith('ERR')) { exit 2 }
    exit 0
} finally {
    $pipe.Dispose()
}
