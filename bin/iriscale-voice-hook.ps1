# Run Codex hooks without passing its pipe handles to long-lived MSYS children.
param(
    [string]$ShellPath,
    [ValidateSet('codex-stamp','codex-resume','codex-PermissionRequest','codex-Stop','codex-SessionEnd')][string]$Event,
    [string]$Stage
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8 = New-Object Text.UTF8Encoding($false)
if ($Stage) {
    $stagePath = [IO.Path]::GetFullPath($Stage)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $stagePath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($stagePath) -notmatch '^iriscale-hook-[a-f0-9]{32}$') { throw 'Invalid hook staging directory' }
    $meta = [IO.File]::ReadAllText((Join-Path $Stage 'meta.json')) | ConvertFrom-Json
    $inputPath = Join-Path $Stage 'input.json'
    $payload = [IO.File]::ReadAllBytes($inputPath)
    # Delete the payload before starting descendants, so none can retain its file.
    [IO.File]::Delete($inputPath)
    $result = @{ code = 1; stdout = ''; stderr = '' }
    $process = New-Object Diagnostics.Process
    try {
        $process.StartInfo.FileName = $meta.shell
        $process.StartInfo.Arguments = '"' + (Join-Path $PSScriptRoot 'iriscale-voice').Replace('\','/') + '" ' + $meta.event
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        # An early-exiting hook can close stdin before accepting the payload.
        # Its actual exit status still takes precedence over a broken-pipe error.
        try { $process.StandardInput.BaseStream.Write($payload, 0, $payload.Length) } catch [IO.IOException] {}
        try { $process.StandardInput.Close() } catch [IO.IOException] {}
        $limit = if ($meta.event -eq 'codex-SessionEnd') { 1000 } else { 5000 }
        if (-not $process.WaitForExit($limit)) {
            $process.Kill()
            $result.stderr = 'Iriscale hook runtime exceeded its execution limit.'
        } else {
            $result.code = $process.ExitCode
            # Background MSYS children may retain these private pipes. Never wait
            # for their EOF after the foreground runtime has already exited.
            if ($stdout.Wait(100)) { $result.stdout = $stdout.Result }
            if ($stderr.Wait(100)) { $result.stderr = $stderr.Result }
        }
    } catch { $result.stderr = $_.Exception.Message }
    finally { $process.Dispose() }
    [IO.File]::WriteAllText((Join-Path $Stage 'result.json'), ($result | ConvertTo-Json -Compress), $utf8)
    exit 0
}
if (-not $ShellPath -or -not $Event) { throw 'ShellPath and Event are required' }
# SessionEnd only deletes its state; it cannot start background work. Keep this
# path direct to fit Codex's three-second ceiling even on slower Windows hosts.
if ($Event -eq 'codex-SessionEnd') {
    & $ShellPath (Join-Path $PSScriptRoot 'iriscale-voice') $Event
    exit $LASTEXITCODE
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('iriscale-hook-' + [guid]::NewGuid().ToString('N'))
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetOwner($owner)
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object Security.AccessControl.FileSystemAccessRule($owner, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($rule)
[void][IO.Directory]::CreateDirectory($work, $acl)
try {
    $inputFile = [IO.File]::Create((Join-Path $work 'input.json'))
    try { [Console]::OpenStandardInput().CopyTo($inputFile) } finally { $inputFile.Dispose() }
    [IO.File]::WriteAllText((Join-Path $work 'meta.json'), (@{shell=$ShellPath;event=$Event} | ConvertTo-Json -Compress), $utf8)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $PSHOME 'powershell.exe'
    $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Stage "' + $work + '"'
    # ShellExecute creates a separate hidden process without Codex's pipe handles.
    $start.UseShellExecute = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $child = [Diagnostics.Process]::Start($start)
    try {
        $limit = if ($Event -eq 'codex-SessionEnd') { 2200 } else { 8000 }
        if (-not $child.WaitForExit($limit)) { $child.Kill(); throw 'Iriscale hook worker timed out' }
    } finally { $child.Dispose() }
    $result = [IO.File]::ReadAllText((Join-Path $work 'result.json')) | ConvertFrom-Json
    [Console]::Out.Write($result.stdout)
    [Console]::Error.Write($result.stderr)
    $exitCode = [int]$result.code
} catch { [Console]::Error.WriteLine($_.Exception.Message); $exitCode = 1 }
finally { Remove-Item -LiteralPath $work -Recurse -Force }
exit $exitCode
