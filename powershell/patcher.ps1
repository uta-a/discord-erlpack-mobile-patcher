[CmdletBinding()]
param(
    [ValidateSet("menu", "status", "install", "uninstall")]
    [string]$Action = "menu",

    [ValidateSet("auto", "stable", "canary")]
    [string]$Channel = "auto",

    [string]$DiscordPath,

    [switch]$NoRun
)

$ErrorActionPreference = "Stop"
$script:PatchMarker = "fake-mobile-status:erlpack-patcher:v1"
$script:SkipProcessCheck = $false
$script:OfficialWrappers = @(
    "`"use strict`";`nmodule.exports = require('./discord_erlpack.node');",
    "`"use strict`";`nmodule.exports = require(`"./discord_erlpack.node`");"
)

function Get-OfficialWrapper {
    return "`"use strict`";`nmodule.exports = require('./discord_erlpack.node');`n"
}

function Get-PatchedWrapper {
    @'
"use strict";
// fake-mobile-status:erlpack-patcher:v1
const erlpack = require("./discord_erlpack.node");
const originalPack = erlpack.pack;

erlpack.pack = function (payload, ...rest) {
  let nextPayload = payload;
  try {
    if (payload?.op === 2 && payload?.d?.properties) {
      nextPayload = {
        ...payload,
        d: {
          ...payload.d,
          properties: {
            ...payload.d.properties,
            os: "Android",
            browser: "Discord Android",
            device: "Discord Android"
          }
        }
      };
    }
  } catch {
    nextPayload = payload;
  }
  return originalPack.call(this, nextPayload, ...rest);
};

module.exports = erlpack;
'@
}

function Get-NormalizedContent {
    param([Parameter(Mandatory)][string]$Content)
    return $Content.Replace("`r`n", "`n").Trim()
}

function Get-WrapperStatus {
    param([Parameter(Mandatory)][string]$Content)

    $normalized = Get-NormalizedContent $Content
    foreach ($official in $script:OfficialWrappers) {
        if ($normalized -ceq $official) {
            return "official"
        }
    }
    if ($normalized -ceq (Get-NormalizedContent (Get-PatchedWrapper))) {
        return "patched"
    }
    return "unknown/third-party"
}

function Get-VersionValue {
    param([Parameter(Mandatory)][string]$Name)

    $value = $Name -replace '^app-', ''
    if ($value -notmatch '^\d+(\.\d+)*$') {
        return $null
    }
    if ($value -notmatch '\.') {
        $value = "$value.0"
    }
    try {
        return [version]$value
    }
    catch {
        return $null
    }
}

function Get-DiscordTarget {
    param([Parameter(Mandatory)][string]$ChannelDirectory)

    $resolvedChannel = (Resolve-Path -LiteralPath $ChannelDirectory).Path
    $appDirectories = Get-ChildItem -LiteralPath $resolvedChannel -Directory |
        ForEach-Object {
            $version = Get-VersionValue $_.Name
            if ($null -ne $version) {
                [pscustomobject]@{ Directory = $_; Version = $version; AppPrefix = $_.Name.StartsWith("app-") }
            }
        } |
        Sort-Object -Property @{ Expression = "Version"; Descending = $true },
        @{ Expression = "AppPrefix"; Descending = $true }

    foreach ($app in $appDirectories) {
        $modules = Join-Path $app.Directory.FullName "modules"
        if (-not (Test-Path -LiteralPath $modules -PathType Container)) {
            continue
        }
        $erlpackDirectories = Get-ChildItem -LiteralPath $modules -Directory -Filter "discord_erlpack-*" |
            ForEach-Object {
                $versionName = $_.Name.Substring("discord_erlpack-".Length)
                $version = Get-VersionValue $versionName
                if ($null -ne $version) {
                    [pscustomobject]@{ Directory = $_; Version = $version }
                }
            } |
            Sort-Object -Property Version -Descending

        foreach ($erlpack in $erlpackDirectories) {
            $wrapper = Join-Path $erlpack.Directory.FullName "discord_erlpack\index.js"
            if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
                continue
            }
            $resolvedWrapper = (Resolve-Path -LiteralPath $wrapper).Path
            if ($resolvedWrapper -notlike "$($resolvedChannel.TrimEnd('\'))\*") {
                throw "discord_erlpack wrapper resolves outside Discord directory: $resolvedWrapper"
            }
            $relative = $resolvedWrapper.Substring($resolvedChannel.TrimEnd('\').Length).TrimStart('\')
            return [pscustomobject]@{
                AppVersion = $app.Directory.Name
                Wrapper = $resolvedWrapper
                RelativePath = $relative
            }
        }
    }
    throw "discord_erlpack wrapper was not found under $ChannelDirectory"
}

function Get-InstallationStatus {
    param(
        [Parameter(Mandatory)][string]$ChannelName,
        [Parameter(Mandatory)][string]$ChannelDirectory
    )

    $target = Get-DiscordTarget $ChannelDirectory
    $content = [IO.File]::ReadAllText($target.Wrapper)
    [pscustomobject]@{
        Channel = $ChannelName
        Directory = (Resolve-Path -LiteralPath $ChannelDirectory).Path
        AppVersion = $target.AppVersion
        Wrapper = $target.Wrapper
        Status = Get-WrapperStatus $content
    }
}

function Get-DefaultChannelDirectory {
    param([Parameter(Mandatory)][ValidateSet("stable", "canary")][string]$ChannelName)

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is not defined"
    }
    $name = if ($ChannelName -eq "canary") { "DiscordCanary" } else { "Discord" }
    return Join-Path $env:LOCALAPPDATA $name
}

function Get-DetectedInstallations {
    $installations = @()
    foreach ($channelName in @("stable", "canary")) {
        $directory = Get-DefaultChannelDirectory $channelName
        try {
            $installations += Get-InstallationStatus $channelName $directory
        }
        catch {
            if (Test-Path -LiteralPath $directory) {
                Write-Verbose "$channelName detection failed: $($_.Exception.Message)"
            }
        }
    }
    return $installations
}

function Assert-DiscordStopped {
    param([Parameter(Mandatory)][ValidateSet("stable", "canary")][string]$ChannelName)

    if ($script:SkipProcessCheck) {
        return
    }
    $processName = if ($ChannelName -eq "canary") { "DiscordCanary" } else { "Discord" }
    $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return
    }

    Write-Host "Discord $ChannelName is running; stopping it before changing the patch..." -ForegroundColor Yellow
    $processes | Stop-Process -Force -ErrorAction Stop

    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        Start-Sleep -Milliseconds 200
        if (-not (Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
            return
        }
    }

    throw "Discord $ChannelName is still running after stop request"
}

function Get-BackupPath {
    param(
        [Parameter(Mandatory)][string]$ChannelName,
        [Parameter(Mandatory)][string]$AppVersion
    )
    return Join-Path $env:LOCALAPPDATA "FakeMobileStatus\powershell-patcher\backups\$ChannelName\$AppVersion\discord_erlpack-index.js"
}

function Write-VerifiedFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = Join-Path $directory (".powershell-patcher-" + [Guid]::NewGuid() + ".tmp")
    try {
        $utf8WithoutBom = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($temporary, $Content, $utf8WithoutBom)
        $expected = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
        Move-Item -LiteralPath $temporary -Destination $Path -Force
        $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        if ($actual -ne $expected) {
            throw "write verification failed: $Path"
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Install-MobilePatch {
    param([Parameter(Mandatory)][pscustomobject]$Installation)

    Assert-DiscordStopped $Installation.Channel
    if ($Installation.Status -eq "patched") {
        return "patch is already applied"
    }
    if ($Installation.Status -ne "official") {
        throw "refusing to overwrite unknown discord_erlpack wrapper: $($Installation.Wrapper)"
    }

    $official = [IO.File]::ReadAllText($Installation.Wrapper)
    $backup = Get-BackupPath $Installation.Channel $Installation.AppVersion
    if (Test-Path -LiteralPath $backup) {
        $backupStatus = Get-WrapperStatus ([IO.File]::ReadAllText($backup))
        if ($backupStatus -ne "official") {
            throw "existing backup is not official: $backup"
        }
    }
    else {
        Write-VerifiedFile $backup $official
    }
    Write-VerifiedFile $Installation.Wrapper (Get-PatchedWrapper)
    return "patch applied"
}

function Uninstall-MobilePatch {
    param([Parameter(Mandatory)][pscustomobject]$Installation)

    Assert-DiscordStopped $Installation.Channel
    if ($Installation.Status -eq "official") {
        return "wrapper is already official"
    }
    if ($Installation.Status -ne "patched") {
        throw "patched wrapper has changed; refusing to overwrite it: $($Installation.Wrapper)"
    }

    $backup = Get-BackupPath $Installation.Channel $Installation.AppVersion
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
        $official = [IO.File]::ReadAllText($backup)
        if ((Get-WrapperStatus $official) -ne "official") {
            throw "backup is not an official discord_erlpack wrapper"
        }
        Write-VerifiedFile $Installation.Wrapper $official
        return "official wrapper restored"
    }

    $official = Get-OfficialWrapper
    Write-VerifiedFile $Installation.Wrapper $official
    return "official wrapper restored without backup"
}

function Select-Installation {
    param(
        [Parameter(Mandatory)][array]$Installations,
        [Parameter(Mandatory)][string]$RequestedChannel
    )

    if ($Installations.Count -eq 0) {
        throw "no supported Discord installation was detected"
    }
    if ($RequestedChannel -eq "auto") {
        return $Installations | Select-Object -First 1
    }
    $selected = $Installations | Where-Object Channel -eq $RequestedChannel | Select-Object -First 1
    if (-not $selected) {
        throw "Discord $RequestedChannel was not detected"
    }
    return $selected
}

function Show-Status {
    param([Parameter(Mandatory)][pscustomobject]$Installation)
    Write-Host ""
    Write-Host ($(if ($Installation.Channel -eq "canary") { "Discord Canary" } else { "Discord Stable" }))
    Write-Host "  Version: $($Installation.AppVersion)"
    Write-Host "  Status:  $($Installation.Status)"
    Write-Host "  Path:    $($Installation.Directory)"
}

function Read-MenuChoice {
    param([Parameter(Mandatory)][string]$Prompt, [Parameter(Mandatory)][array]$Items)

    if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
        return Read-ArrowMenuChoice $Prompt $Items
    }

    Write-Host ""
    Write-Host $Prompt
    for ($index = 0; $index -lt $Items.Count; $index++) {
        Write-Host "  $($index + 1). $($Items[$index])"
    }
    while ($true) {
        $value = Read-Host "Select"
        $number = 0
        if ([int]::TryParse($value, [ref]$number) -and $number -ge 1 -and $number -le $Items.Count) {
            return $number - 1
        }
        Write-Host "Enter a number from 1 to $($Items.Count)." -ForegroundColor Yellow
    }
}

function Read-ArrowMenuChoice {
    param([Parameter(Mandatory)][string]$Prompt, [Parameter(Mandatory)][array]$Items)

    $selectedIndex = 0
    $top = [Console]::CursorTop
    $left = [Console]::CursorLeft
    $cursorWasVisible = [Console]::CursorVisible
    [Console]::CursorVisible = $false

    try {
        while ($true) {
            [Console]::SetCursorPosition($left, $top)
            Write-Host ""
            Write-Host $Prompt
            Write-Host "Use Up/Down arrows and Enter. Esc cancels." -ForegroundColor DarkGray

            for ($index = 0; $index -lt $Items.Count; $index++) {
                $prefix = if ($index -eq $selectedIndex) { ">" } else { " " }
                $foreground = if ($index -eq $selectedIndex) { [ConsoleColor]::Black } else { [Console]::ForegroundColor }
                $background = if ($index -eq $selectedIndex) { [ConsoleColor]::White } else { [Console]::BackgroundColor }
                Write-Host ("  {0} {1}" -f $prefix, $Items[$index]) -ForegroundColor $foreground -BackgroundColor $background
            }

            $clearLines = [Math]::Max(0, [Console]::WindowHeight - [Console]::CursorTop - 1)
            if ($clearLines -gt 0) {
                Write-Host ("`n" * [Math]::Min($clearLines, 1)) -NoNewline
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow" {
                    $selectedIndex = if ($selectedIndex -le 0) { $Items.Count - 1 } else { $selectedIndex - 1 }
                }
                "DownArrow" {
                    $selectedIndex = if ($selectedIndex -ge $Items.Count - 1) { 0 } else { $selectedIndex + 1 }
                }
                "Home" {
                    $selectedIndex = 0
                }
                "End" {
                    $selectedIndex = $Items.Count - 1
                }
                "Enter" {
                    Write-Host ""
                    return $selectedIndex
                }
                "Escape" {
                    throw "cancelled"
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $cursorWasVisible
    }
}

function Invoke-Patcher {
    param([string]$RequestedAction, [string]$RequestedChannel, [string]$CustomPath)

    Write-Host "Fake Mobile Status PowerShell Patcher"
    $installations = if ($CustomPath) {
        if ($RequestedChannel -eq "auto") {
            throw "-DiscordPath requires -Channel stable or -Channel canary"
        }
        @(Get-InstallationStatus $RequestedChannel $CustomPath)
    }
    else {
        @(Get-DetectedInstallations)
    }
    if ($installations.Count -eq 0) {
        throw "no supported Discord installation was detected"
    }

    if ($RequestedAction -eq "menu") {
        $actions = @("Install", "Uninstall", "View status", "Quit")
        $actionIndex = Read-MenuChoice "What would you like to do?" $actions
        if ($actions[$actionIndex] -eq "Quit") {
            return
        }
        $RequestedAction = @("install", "uninstall", "status")[$actionIndex]
        $labels = @($installations | ForEach-Object {
            "$($_.Channel) - $($_.AppVersion) [$($_.Status)]"
        })
        $installationIndex = Read-MenuChoice "Select Discord installation" $labels
        $selected = $installations[$installationIndex]
    }
    elseif ($RequestedAction -eq "status" -and $RequestedChannel -eq "auto" -and -not $CustomPath) {
        foreach ($installation in $installations) {
            Show-Status $installation
        }
        return
    }
    else {
        $selected = Select-Installation $installations $RequestedChannel
    }

    if ($RequestedAction -eq "status") {
        Show-Status $selected
        return
    }
    $result = if ($RequestedAction -eq "install") {
        Install-MobilePatch $selected
    }
    else {
        Uninstall-MobilePatch $selected
    }
    Write-Host ""
    Write-Host "Success: $result on Discord $($selected.Channel)" -ForegroundColor Green
}

if (-not $NoRun) {
    try {
        Invoke-Patcher $Action $Channel $DiscordPath
    }
    catch {
        if ($_.Exception.Message -eq "cancelled") {
            Write-Host ""
            Write-Host "Cancelled."
            return
        }
        Write-Host ""
        Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}
