[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\iriscale-voice'),
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$SourcePath,
    [switch]$Update,
    [switch]$Uninstall,
    [switch]$SkipPath,
    [switch]$SkipProfile
)

$ErrorActionPreference = 'Stop'
$repo = 'https://raw.githubusercontent.com/justbuild-it/iriscale_voice/main'
$binDir = Join-Path $InstallRoot 'bin'
$scriptPath = Join-Path $binDir 'iriscale-voice'
$launcherPath = Join-Path $binDir 'iriscale-voice.cmd'
$completionPath = Join-Path $InstallRoot 'iriscale-voice-completion.ps1'
$profileMarker = '# iriscale-voice completion'
$skillDir = Join-Path $CodexHome 'skills\iriscale-voice'

function Backup-File([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination "$Path.iriscale-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Remove-InstallerConfiguration {
    $configPath = Join-Path $CodexHome 'config.toml'
    if (Test-Path -LiteralPath $configPath) {
        $lines = @(Get-Content -LiteralPath $configPath)
        $kept = @($lines | Where-Object { $_ -notmatch '^\s*notify\s*=.*iriscale-voice' })
        if ($kept.Count -ne $lines.Count) {
            Backup-File $configPath
            Write-Utf8NoBom $configPath (($kept -join [Environment]::NewLine) + [Environment]::NewLine)
        }
    }
    $hooksPath = Join-Path $CodexHome 'hooks.json'
    if (Test-Path -LiteralPath $hooksPath) {
        $doc = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json
        $changed = $false
        foreach ($event in @('UserPromptSubmit', 'PermissionRequest')) {
            $property = $doc.hooks.PSObject.Properties[$event]
            if ($property -and (($property.Value | ConvertTo-Json -Depth 20) -match 'iriscale-voice')) {
                $doc.hooks.PSObject.Properties.Remove($event)
                $changed = $true
            }
        }
        if ($changed) {
            Backup-File $hooksPath
            Write-Utf8NoBom $hooksPath (($doc | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
        }
    }
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

$gitCandidates = @((Join-Path $env:ProgramFiles 'Git\bin\bash.exe'))
if (${env:ProgramFiles(x86)}) { $gitCandidates += (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe') }
$gitBash = $gitCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $gitBash) { throw 'Git for Windows is required. Install it from https://git-scm.com/download/win' }

New-Item -ItemType Directory -Force -Path $binDir, $CodexHome | Out-Null
if ($SourcePath) {
    Copy-Item -LiteralPath (Join-Path $SourcePath 'bin\iriscale-voice') -Destination $scriptPath -Force
} else {
    Invoke-WebRequest "$repo/bin/iriscale-voice" -OutFile $scriptPath
}
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
$launcher = "@echo off`r`n`"$gitBash`" `"$scriptPath`" %*`r`n"
Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding ASCII -NoNewline

$completion = @(& $launcherPath completions powershell) -join [Environment]::NewLine
if (-not $completion) { throw 'Could not generate PowerShell completion from the installed launcher' }
Write-Utf8NoBom $completionPath ($completion + [Environment]::NewLine)

if (-not $SkipPath) {
    $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
    if (@($userPath -split ';') -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';') + ';' + $binDir).TrimStart(';')), 'User')
    }
    if (@($env:Path -split ';') -notcontains $binDir) { $env:Path += ";$binDir" }
}
if (-not $SkipProfile) {
    $profileDir = Split-Path -Parent $PROFILE
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    if (-not (Test-Path -LiteralPath $PROFILE) -or
        -not (Select-String -Quiet -LiteralPath $PROFILE -Pattern $profileMarker -SimpleMatch)) {
        $profileContent = $(if (Test-Path -LiteralPath $PROFILE) { Get-Content -Raw -LiteralPath $PROFILE } else { '' })
        Write-Utf8NoBom $PROFILE ($profileContent.TrimEnd() + "`n`n$profileMarker`n. '$completionPath'`n")
    }
}

$configPath = Join-Path $CodexHome 'config.toml'
$tomlLauncher = $launcherPath.Replace('\', '/')
$notify = 'notify = ["' + $tomlLauncher.Replace('"', '\"') + '", "notify"]'
if (Test-Path -LiteralPath $configPath) {
    Backup-File $configPath
    $lines = @(Get-Content -LiteralPath $configPath)
    if ($lines -match '^\s*notify\s*=') {
        $lines = @($lines | ForEach-Object { if ($_ -match '^\s*notify\s*=') { $notify } else { $_ } })
    } else { $lines = @($notify, '') + $lines }
    Write-Utf8NoBom $configPath (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
} else { Write-Utf8NoBom $configPath ($notify + [Environment]::NewLine) }

$hooksPath = Join-Path $CodexHome 'hooks.json'
if (Test-Path -LiteralPath $hooksPath) {
    Backup-File $hooksPath
    $hooksDoc = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json
} else { $hooksDoc = [pscustomobject]@{ hooks = [pscustomobject]@{} } }
if (-not $hooksDoc.hooks) { $hooksDoc | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force }
foreach ($definition in @(@('UserPromptSubmit','stamp',10), @('PermissionRequest','PermissionRequest',30))) {
    $event, $argument, $timeout = $definition
    $commandWindows = '"' + $launcherPath + '" ' + $argument
    # Codex requires the portable command field even when commandWindows is
    # present. The Windows override alone is ignored and appears as Installed 0.
    $hook = @([pscustomobject]@{ hooks = @([pscustomobject]@{
        type='command'
        command=$commandWindows
        commandWindows=$commandWindows
        timeout=$timeout
    }) })
    $hooksDoc.hooks | Add-Member -NotePropertyName $event -NotePropertyValue $hook -Force
}
Write-Utf8NoBom $hooksPath (($hooksDoc | ConvertTo-Json -Depth 20) + [Environment]::NewLine)

Write-Host $(if ($Update) { 'Iriscale Voice updated.' } else { 'Iriscale Voice installed.' })
Write-Host "  executable: $launcherPath"
Write-Host "  Codex config: $configPath"
Write-Host "  Codex hooks:  $hooksPath"
Write-Host "  Codex skill:  $skillDir"
Write-Host 'Restart Codex and your terminal, then open /hooks and trust hooks showing Installed 1.'
