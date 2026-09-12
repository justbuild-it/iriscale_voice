[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\iriscale-voice'),
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$SourcePath,
    [switch]$Update,
    [switch]$Uninstall,
    [switch]$SkipPath,
    [switch]$SkipProfile,
    # Git ref to install from. Defaults to the release tag matching this installer, so a
    # pinned install.ps1 installs exactly that release. Pass -Ref main for the tip.
    [string]$Ref = 'v0.1.29'
)

$ErrorActionPreference = 'Stop'
# The installed copy of this file is pinned to the release it installed, so a bare
# -Update re-installed the same version forever (0.1.17 -> 0.1.17). Now -Update with no
# explicit -Ref asks GitHub for the latest release tag and installs that.
if ($Update -and -not $SourcePath -and -not $PSBoundParameters.ContainsKey('Ref')) {
    try {
        $latest = (Invoke-RestMethod 'https://api.github.com/repos/justbuild-it/iriscale_voice/releases/latest' -Headers @{ 'User-Agent' = 'iriscale-voice' }).tag_name
        if ($latest -match '^v\d+\.\d+\.\d+$') { $Ref = $latest }
    } catch { Write-Host "could not look up the latest release; staying on $Ref" }
}
$repo = "https://raw.githubusercontent.com/justbuild-it/iriscale_voice/$Ref"
$binDir = Join-Path $InstallRoot 'bin'
$scriptPath = Join-Path $binDir 'iriscale-voice'
$launcherPath = Join-Path $binDir 'iriscale-voice.cmd'
$notifyBridge = Join-Path $binDir 'iriscale-voice-notify.ps1'
$completionPath = Join-Path $InstallRoot 'iriscale-voice-completion.ps1'
$profileMarker = '# iriscale-voice completion'
$skillDir = Join-Path $CodexHome 'skills\iriscale-voice'

function Backup-File([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination "$Path.iriscale-backup-$([guid]::NewGuid().ToString('N'))"
    }
}

# Same lexical boundary rules as npm/toml.js, covered by test/audit-installer.js.
# Never consume unrelated settings because a bracket appears inside a string/comment.
function Get-NotifySpan([string[]]$Lines) {
    $found = $null
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*(#.*)?$') { continue }
        if ($Lines[$i] -match '^\s*\[') { break }
        if ($Lines[$i] -notmatch '^\s*([^=]+?)\s*=') { throw "Cannot safely edit config.toml: expected assignment at line $($i+1)" }
        $key = $Matches[1].Trim(); $offset = $Matches[0].Length; $start = $i
        if ($key.StartsWith('"')) {
            $encodedKey = [regex]::Replace($key, '\\U([0-9a-fA-F]{8})', {
                param($m)
                $json = ConvertTo-Json -Compress -InputObject ([char]::ConvertFromUtf32([Convert]::ToInt32($m.Groups[1].Value, 16)))
                $json.Substring(1, $json.Length-2)
            })
            $key = ConvertFrom-Json -InputObject $encodedKey
        } elseif ($key.StartsWith("'")) { $key = $key.Substring(1, $key.Length-2) }
        $quote = ''; $triple = $false; $escaped = $false; $stack = ''; $value = $false; $complete = $false
        for (; $i -lt $Lines.Count; $i++) {
            $line = $Lines[$i]
            $c = if ($i -eq $start) { $offset } else { 0 }
            for (; $c -lt $line.Length; $c++) {
                $ch = [string]$line[$c]
                if ($quote) {
                    if ($escaped) { $escaped = $false; continue }
                    if ($quote -eq '"' -and $ch -eq '\') { $escaped = $true; continue }
                    if ($ch -eq $quote) {
                        if (-not $triple) { $quote = '' }
                        elseif ($c + 2 -lt $line.Length -and $line.Substring($c,3) -eq ($quote * 3)) {
                            $n = 3
                            while ($n -lt 5 -and $c + $n -lt $line.Length -and [string]$line[$c+$n] -eq $quote) { $n++ }
                            $c += $n - 1; $quote = ''
                        }
                    }
                    continue
                }
                if ($ch -eq '#') { break }
                if ($ch -match '\s') { continue }
                $value = $true
                if ($ch -eq '"' -or $ch -eq "'") {
                    $quote = $ch; $triple = $c + 2 -lt $line.Length -and $line.Substring($c,3) -eq ($ch * 3)
                    if ($triple) { $c += 2 }
                } elseif ($ch -eq '[' -or $ch -eq '{') { $stack += $ch }
                elseif ($ch -eq ']' -or $ch -eq '}') {
                    $opening = if ($ch -eq ']') { '[' } else { '{' }
                    if (-not $stack -or [string]$stack[$stack.Length-1] -ne $opening) { throw 'Cannot safely edit config.toml: unbalanced value' }
                    $stack = $stack.Substring(0, $stack.Length-1)
                }
            }
            if ($quote -and -not $triple) { throw 'Cannot safely edit config.toml: unfinished string' }
            $escaped = $false
            if (-not $quote -and -not $stack) { $complete = $value; break }
        }
        if (-not $complete) { throw 'Cannot safely edit config.toml: unfinished value' }
        if ($key -ceq 'notify') {
            if ($null -ne $found) { throw 'Cannot safely edit config.toml: duplicate notify' }
            $found = @($start, $i)
        }
    }
    if ($null -ne $found) { return ,$found }
}

function Replace-NotifyText([string]$Content, [string[]]$Replacement) {
    $eol = if ($Content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.AddRange([string[]]($Content -split '\r?\n'))
    $span = Get-NotifySpan $lines.ToArray()
    if ($null -ne $span) {
        $lines.RemoveRange($span[0], $span[1] - $span[0] + 1)
        $lines.InsertRange($span[0], [string[]]@($Replacement))
    } elseif ($Replacement.Count) { $lines.InsertRange(0, $Replacement) }
    return $lines -join $eol
}

function Test-LegacyVoiceNotify([string[]]$Lines) {
    try {
        $assignment = $Lines -join "`n"
        $rhs = $assignment.Substring($assignment.IndexOf('=') + 1)
        $rhs = [regex]::Replace($rhs, '"(?:[^"\\]|\\.)*"|#[^\r\n]*', {
            param($match)
            if ($match.Value.StartsWith('#')) { '' } else { $match.Value }
        }).Trim() -replace ',\s*\]$', ']'
        if (-not $rhs.StartsWith('[')) { return $false }
        $values = ConvertFrom-Json -InputObject $rhs
        if ($values -isnot [array]) { return $false }
        foreach ($value in $values) { if ($value -isnot [string]) { return $false } }
        $names = @($values | ForEach-Object { ($_ -replace '^.*[\\/]', '').ToLowerInvariant() })
        $voiceNames = @('iriscale-voice', 'iriscale-voice.cmd')
        $shellNames = @('sh', 'sh.exe', 'bash', 'bash.exe')
        if ($values.Count -eq 2) { return $names[0] -in $voiceNames -and $values[1] -ceq 'notify' }
        if ($values.Count -eq 3) { return $names[0] -in $shellNames -and $names[1] -in $voiceNames -and $values[2] -ceq 'notify' }
        return $values.Count -eq 8 -and $names[0] -in @('powershell.exe', 'pwsh.exe') -and
            ($values[1..5] -join ' ') -ieq '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File' -and
            $names[6] -eq 'iriscale-voice-notify.ps1' -and $names[7] -in $shellNames
    } catch { return $false }
}

function Test-OurCommand($Command) {
    if ($Command -is [string] -and $Command -cmatch '^powershell\.exe -NoProfile -NonInteractive -EncodedCommand ([A-Za-z0-9+/=]+)$') {
        try { $Command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1])) } catch { return $false }
        if (-not $Command.StartsWith('& ') -or -not $Command.EndsWith('; exit $LASTEXITCODE')) { return $false }
        $Command = $Command.Substring(0, $Command.Length - '; exit $LASTEXITCODE'.Length)
    }
    return $Command -is [string] -and $Command -match 'iriscale-voice' -and
        $Command -match '\s(codex-)?(stamp|PermissionRequest|resume|Stop|SessionEnd)\s*$'
}
function Remove-OurHooks($Groups) {
    foreach ($group in $Groups) {
        $kept = @($group.hooks | Where-Object { -not ((Test-OurCommand $_.command) -or (Test-OurCommand $_.commandWindows)) })
        if ($kept.Count -eq @($group.hooks).Count) { $group; continue }
        if ($kept.Count) { $group.hooks = $kept; $group }
    }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

# Replace a file that may still be open by a process that is about to exit (the
# launcher that invoked `iriscale-voice update` is running this very script).
# Stage to .new, then swap with retries for up to ~10 s instead of failing outright.
function Replace-File([string]$Staged, [string]$Target) {
    for ($i = 0; $i -lt 20; $i++) {
        try { Move-Item -LiteralPath $Staged -Destination $Target -Force -ErrorAction Stop; return }
        catch { Start-Sleep -Milliseconds 500 }
    }
    throw "Could not replace $Target - is iriscale-voice still running (e.g. the board)? Close it and re-run."
}

function Remove-InstallerConfiguration {
    $configPath = Join-Path $CodexHome 'config.toml'
    if (Test-Path -LiteralPath $configPath) {
        $content = [IO.File]::ReadAllText($configPath)
        $lines = $content -split '\r?\n'
        $span = Get-NotifySpan $lines
        if ($null -ne $span -and (Test-LegacyVoiceNotify @($lines[$span[0]..$span[1]]))) {
            $restore = @()
            $recordPath = Join-Path $InstallRoot 'powershell-install.json'
            if (Test-Path -LiteralPath $recordPath) { $restore = @((Get-Content -Raw -Encoding UTF8 -LiteralPath $recordPath | ConvertFrom-Json).replacedNotify) | Where-Object { $null -ne $_ } }
            Backup-File $configPath
            Write-Utf8NoBom $configPath (Replace-NotifyText $content @($restore))
        }
    }
    $hooksPath = Join-Path $CodexHome 'hooks.json'
    if (Test-Path -LiteralPath $hooksPath) {
        $doc = Get-Content -Raw -Encoding UTF8 -LiteralPath $hooksPath | ConvertFrom-Json
        $changed = $false
        foreach ($event in @('UserPromptSubmit', 'PermissionRequest', 'PostToolUse', 'Stop', 'SessionEnd')) {
            $property = $doc.hooks.PSObject.Properties[$event]
            if ($property) {
                $before = $property.Value | ConvertTo-Json -Depth 20 -Compress
                $kept = @(Remove-OurHooks $property.Value)
                if (($kept | ConvertTo-Json -Depth 20 -Compress) -eq $before) { continue }
                if ($kept.Count) { $property.Value = $kept } else { $doc.hooks.PSObject.Properties.Remove($event) }
                $changed = $true
            }
        }
        if ($changed) {
            Backup-File $hooksPath
            Write-Utf8NoBom $hooksPath (($doc | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
        }
    }
}

if ((Test-Path -LiteralPath (Join-Path $InstallRoot 'install.json'))) {
    throw 'This installation is managed by npm. Use npx @iriscale/voice@latest update or uninstall codex.'
}
if ($Uninstall) {
    Remove-InstallerConfiguration
    $skillFile = Join-Path $skillDir 'SKILL.md'
    if ((Test-Path -LiteralPath $skillFile) -and
        (Select-String -Quiet -LiteralPath $skillFile -Pattern 'name: iriscale-voice' -SimpleMatch)) {
        $resolvedSkill = (Resolve-Path -LiteralPath $skillDir).Path
        $resolvedCodex = (Resolve-Path -LiteralPath $CodexHome).Path
        if (-not $resolvedSkill.StartsWith($resolvedCodex + [IO.Path]::DirectorySeparatorChar)) {
            throw "Refusing to remove unexpected skill directory: $resolvedSkill"
        }
        Remove-Item -LiteralPath $resolvedSkill -Recurse -Force
    }
    if (-not $SkipProfile -and (Test-Path -LiteralPath $PROFILE)) {
        $profileLines = @(Get-Content -LiteralPath $PROFILE)
        $filtered = @($profileLines | Where-Object {
            $_ -notmatch [regex]::Escape($profileMarker) -and $_ -notmatch 'iriscale-voice-completion\.ps1'
        })
        if ($filtered.Count -ne $profileLines.Count) {
            Backup-File $PROFILE
            Write-Utf8NoBom $PROFILE (($filtered -join [Environment]::NewLine) + [Environment]::NewLine)
        }
    }
    if (-not $SkipPath) {
        $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
        $parts = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $binDir })
        [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
    }
    if (Test-Path -LiteralPath $InstallRoot) {
        $resolvedRoot = (Resolve-Path -LiteralPath $InstallRoot).Path
        if ($resolvedRoot -notlike "*$([IO.Path]::DirectorySeparatorChar)iriscale-voice") {
            throw "Refusing to remove unexpected install directory: $resolvedRoot"
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
    Write-Host 'Iriscale Voice uninstalled. Restart Codex and your terminal.'
    exit 0
}

# Validate what we will edit BEFORE changing anything, so a bad hooks.json cannot leave
# PATH/profile/config half-modified. Any later failure prints what was already changed.
$hooksPathPre = Join-Path $CodexHome 'hooks.json'
if (Test-Path -LiteralPath $hooksPathPre) {
    try {
        $preDoc = Get-Content -Raw -Encoding UTF8 -LiteralPath $hooksPathPre | ConvertFrom-Json
        if ($preDoc -isnot [pscustomobject]) { throw 'expected an object' }
    }
    catch { throw "$hooksPathPre is not valid JSON; fix or move it aside, then re-run. Nothing was changed." }
}
$configPath = Join-Path $CodexHome 'config.toml'
$configContent = if (Test-Path -LiteralPath $configPath) { [IO.File]::ReadAllText($configPath) } else { '' }
$null = Get-NotifySpan ($configContent -split '\r?\n')
# The npm install may be shared with Claude; only npm can safely update/remove it.
if (Test-Path -LiteralPath (Join-Path $InstallRoot 'install.json')) { throw 'This installation is managed by npm. Run: npx @iriscale/voice@latest update' }
$script:done = New-Object System.Collections.ArrayList
trap {
    if ($script:done.Count -gt 0) {
        Write-Host "Install failed after these steps completed: $($script:done -join ', ')." -ForegroundColor Yellow
        Write-Host 'Backups of edited files sit next to them as *.iriscale-backup-*. Re-run to finish, or run with -Uninstall to revert.' -ForegroundColor Yellow
    }
    break
}

$gitCandidates = @((Join-Path $env:ProgramFiles 'Git\bin\bash.exe'))
if (${env:ProgramFiles(x86)}) { $gitCandidates += (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe') }
$gitBash = $gitCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $gitBash) { throw 'Git for Windows is required. Install it from https://git-scm.com/download/win' }

New-Item -ItemType Directory -Force -Path $binDir, $CodexHome | Out-Null
if ($SourcePath) {
    Copy-Item -LiteralPath (Join-Path $SourcePath 'bin\iriscale-voice') -Destination "$scriptPath.new" -Force
} else {
    Invoke-WebRequest "$repo/bin/iriscale-voice" -OutFile "$scriptPath.new"
}
Replace-File "$scriptPath.new" $scriptPath
if ($SourcePath) {
    Copy-Item -LiteralPath (Join-Path $SourcePath 'bin\iriscale-voice-notify.ps1') -Destination "$notifyBridge.new" -Force
} else {
    Invoke-WebRequest "$repo/bin/iriscale-voice-notify.ps1" -OutFile "$notifyBridge.new"
}
Replace-File "$notifyBridge.new" $notifyBridge
$installedInstaller = Join-Path $InstallRoot 'install.ps1'
if ($PSCommandPath) {
    if ((Resolve-Path -LiteralPath $PSCommandPath).Path -ne $installedInstaller) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $installedInstaller -Force
    } elseif ($Update -and -not $SourcePath) {
        Invoke-WebRequest "$repo/install.ps1" -OutFile "$installedInstaller.new"
        Move-Item -LiteralPath "$installedInstaller.new" -Destination $installedInstaller -Force
    }
} elseif (-not $SourcePath) {
    Invoke-WebRequest "$repo/install.ps1" -OutFile $installedInstaller
}

$skillAgents = Join-Path $skillDir 'agents'
New-Item -ItemType Directory -Force -Path $skillAgents | Out-Null
if ($SourcePath) {
    Copy-Item -LiteralPath (Join-Path $SourcePath 'skills\iriscale-voice\SKILL.md') -Destination (Join-Path $skillDir 'SKILL.md') -Force
    Copy-Item -LiteralPath (Join-Path $SourcePath 'skills\iriscale-voice\agents\openai.yaml') -Destination (Join-Path $skillAgents 'openai.yaml') -Force
} else {
    Invoke-WebRequest "$repo/skills/iriscale-voice/SKILL.md" -OutFile (Join-Path $skillDir 'SKILL.md')
    Invoke-WebRequest "$repo/skills/iriscale-voice/agents/openai.yaml" -OutFile (Join-Path $skillAgents 'openai.yaml')
}

# No --login: Git's bin\bash.exe wrapper already sets up /usr/bin on PATH, and
# --login costs ~550 ms per hook event AND sources the user's .bash_profile -
# anything it echoes would corrupt captured output (measured: profile noise
# became line 1 of the generated completion file, breaking the PS profile).
$launcher = "@echo off`r`n`"$gitBash`" `"%~dp0iriscale-voice`" %*`r`n"
Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding ASCII -NoNewline

$completion = @(& $launcherPath completions powershell) -join [Environment]::NewLine
if (-not $completion) { throw 'Could not generate PowerShell completion from the installed launcher' }
Write-Utf8NoBom $completionPath ($completion + [Environment]::NewLine)

if (-not $SkipPath) {
    $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
    if (@($userPath -split ';') -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';') + ';' + $binDir).TrimStart(';')), 'User')
    }
    [void]$script:done.Add('PATH')
    if (@($env:Path -split ';') -notcontains $binDir) { $env:Path += ";$binDir" }
}
if (-not $SkipProfile) {
    $profileDir = Split-Path -Parent $PROFILE
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    if (-not (Test-Path -LiteralPath $PROFILE) -or
        -not (Select-String -Quiet -LiteralPath $PROFILE -Pattern $profileMarker -SimpleMatch)) {
        $profileContent = $(if (Test-Path -LiteralPath $PROFILE) { Get-Content -Raw -LiteralPath $PROFILE } else { '' })
        Backup-File $PROFILE
        $quotedCompletion = $completionPath.Replace("'", "''")
        Write-Utf8NoBom $PROFILE ($profileContent.TrimEnd() + "`n`n$profileMarker`n. '$quotedCompletion'`n")
    }
    [void]$script:done.Add('PowerShell profile')
}

$configPath = Join-Path $CodexHome 'config.toml'
# Stop hooks replace the legacy notifier, which also fires for internal threads.
$recordPath = Join-Path $InstallRoot 'powershell-install.json'
$replaced = @()
if (Test-Path -LiteralPath $recordPath) { $replaced = @((Get-Content -Raw -Encoding UTF8 -LiteralPath $recordPath | ConvertFrom-Json).replacedNotify) | Where-Object { $null -ne $_ } }
$lines = $configContent -split '\r?\n'; $span = Get-NotifySpan $lines
if ($null -ne $span -and (Test-LegacyVoiceNotify @($lines[$span[0]..$span[1]]))) {
    Backup-File $configPath
    Write-Utf8NoBom $configPath (Replace-NotifyText $configContent @($replaced))
    [void]$script:done.Add('config.toml')
} elseif (-not (Test-Path -LiteralPath $configPath)) { Write-Utf8NoBom $configPath '' }
Write-Utf8NoBom $recordPath (([pscustomobject]@{ replacedNotify = @(); home = $CodexHome } | ConvertTo-Json -Depth 20) + "`n")

$hooksPath = Join-Path $CodexHome 'hooks.json'
if (Test-Path -LiteralPath $hooksPath) {
    Backup-File $hooksPath
    $hooksDoc = Get-Content -Raw -Encoding UTF8 -LiteralPath $hooksPath | ConvertFrom-Json
} else { $hooksDoc = [pscustomobject]@{ hooks = [pscustomobject]@{} } }
if ($hooksDoc.hooks -isnot [pscustomobject]) { $hooksDoc | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force }
foreach ($definition in @(@('UserPromptSubmit','stamp',10), @('PermissionRequest','PermissionRequest',30), @('PostToolUse','resume',10), @('Stop','Stop',10), @('SessionEnd','SessionEnd',3))) {
    $event, $argument, $timeout = $definition
    # The session shell can be PowerShell or cmd. Neither may reinterpret paths.
    $invocation = "& '" + $launcherPath.Replace("'", "''") + "' codex-" + $argument + '; exit $LASTEXITCODE'
    $commandWindows = 'powershell.exe -NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($invocation))
    # Codex requires the portable command field even when commandWindows is
    # present. The Windows override alone is ignored and appears as Installed 0.
    $hook = @([pscustomobject]@{ hooks = @([pscustomobject]@{
        type='command'
        command=$commandWindows
        commandWindows=$commandWindows
        timeout=$timeout
    }) })
    $existing = @()
    $property = $hooksDoc.hooks.PSObject.Properties[$event]
    if ($property) { $existing = @(Remove-OurHooks $property.Value) }
    $hooksDoc.hooks | Add-Member -NotePropertyName $event -NotePropertyValue @($existing + $hook) -Force
}
Write-Utf8NoBom $hooksPath (($hooksDoc | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
[void]$script:done.Add('hooks.json')

Write-Host $(if ($Update) { 'Iriscale Voice updated.' } else { 'Iriscale Voice installed.' })
Write-Host "  executable: $launcherPath"
Write-Host "  release:    $Ref"
Write-Host "  Codex config: $configPath"
Write-Host "  Codex hooks:  $hooksPath"
Write-Host "  Codex skill:  $skillDir"
Write-Host 'Requires Codex 0.154.0+. Restart Codex and your terminal, then open /hooks and trust all five hooks.'
