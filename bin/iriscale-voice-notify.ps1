# Codex passes JSON as a native Windows argument. Git Bash's argv parser consumes
# JSON backslashes; move it onto stdin before crossing that boundary.
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$ShellPath,
    [Parameter(Mandatory = $true, Position = 1)][string]$Payload
)
$ErrorActionPreference = 'Stop'
$start = New-Object System.Diagnostics.ProcessStartInfo
$start.FileName = $ShellPath
$scriptPath = (Join-Path $PSScriptRoot 'iriscale-voice').Replace('\', '/')
$start.Arguments = '"' + $scriptPath + '" notify-stdin'
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardInput = $true
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $start
try {
    [void]$process.Start()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
    $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $process.StandardInput.Close()
    $process.WaitForExit()
    exit $process.ExitCode
} finally {
    $process.Dispose()
}
