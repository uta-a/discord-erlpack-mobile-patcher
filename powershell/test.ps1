$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "patcher.ps1") -NoRun

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("discord-erlpack-patcher-test-" + [Guid]::NewGuid())
$originalLocalAppData = $env:LOCALAPPDATA
$script:SkipProcessCheck = $true
$official = "`"use strict`";`r`nmodule.exports = require('./discord_erlpack.node');`r`n"
$stalePatch = "`"use strict`";`r`n// fake-mobile-status:erlpack-patcher:v1`r`nmodule.exports = require(`"./discord_erlpack.node`");`r`n"
$passed = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

function Assert-Throws {
    param([scriptblock]$Operation, [string]$Message)
    try {
        & $Operation
    }
    catch {
        return
    }
    throw "$Message. Expected an exception."
}

function New-TestDiscord {
    param([string]$Name, [string]$Version = "app-1.0.100", [string]$Content = $official)
    $root = Join-Path $testRoot $Name
    $wrapperDirectory = Join-Path $root "$Version\modules\discord_erlpack-1\discord_erlpack"
    New-Item -ItemType Directory -Path $wrapperDirectory -Force | Out-Null
    $wrapper = Join-Path $wrapperDirectory "index.js"
    [IO.File]::WriteAllText($wrapper, $Content)
    return $root
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Test)
    & $Test
    $script:passed++
    Write-Host "PASS: $Name" -ForegroundColor Green
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    Invoke-Test "selects newest complete Discord version" {
        $root = New-TestDiscord "newest" "app-1.0.99"
        $null = New-TestDiscord "newest" "app-1.0.100"
        New-Item -ItemType Directory -Path (Join-Path $root "app-1.0.101\modules") -Force | Out-Null
        Assert-Equal (Get-DiscordTarget $root).AppVersion "app-1.0.100" "wrong app version"
    }

    Invoke-Test "installs and uninstalls" {
        $env:LOCALAPPDATA = Join-Path $testRoot "data-roundtrip"
        $root = New-TestDiscord "roundtrip"
        $installation = Get-InstallationStatus "stable" $root
        Assert-Equal (Install-MobilePatch $installation) "patch applied" "install result"
        Assert-Equal (Get-InstallationStatus "stable" $root).Status "patched" "installed status"
        $installation = Get-InstallationStatus "stable" $root
        Assert-Equal (Uninstall-MobilePatch $installation) "official wrapper restored" "uninstall result"
        Assert-Equal (Get-InstallationStatus "stable" $root).Status "official" "restored status"
    }

    Invoke-Test "uninstalls patched wrapper without backup" {
        $env:LOCALAPPDATA = Join-Path $testRoot "data-no-backup"
        $root = New-TestDiscord "no-backup" "app-1.0.100" (Get-PatchedWrapper)
        $installation = Get-InstallationStatus "canary" $root
        Assert-Equal (Uninstall-MobilePatch $installation) "official wrapper restored without backup" "uninstall result"
        Assert-Equal (Get-InstallationStatus "canary" $root).Status "official" "restored status"
    }

    Invoke-Test "refuses unknown wrapper" {
        $env:LOCALAPPDATA = Join-Path $testRoot "data-unknown"
        $root = New-TestDiscord "unknown" "app-1.0.100" "module.exports = thirdParty;"
        $installation = Get-InstallationStatus "stable" $root
        Assert-Throws { Install-MobilePatch $installation } "unknown wrapper was overwritten"
        Assert-Equal ([IO.File]::ReadAllText($installation.Wrapper)) "module.exports = thirdParty;" "unknown wrapper changed"
    }

    Invoke-Test "detects stale patch" {
        $env:LOCALAPPDATA = Join-Path $testRoot "data-stale"
        $root = New-TestDiscord "stale" "app-1.0.100" $stalePatch
        Assert-Equal (Get-InstallationStatus "stable" $root).Status "stale-patch" "stale patch status"
    }

    Invoke-Test "repairs stale patch" {
        $env:LOCALAPPDATA = Join-Path $testRoot "data-repair-stale"
        $root = New-TestDiscord "repair-stale" "app-1.0.100" $stalePatch
        $installation = Get-InstallationStatus "stable" $root
        Assert-Equal (Install-MobilePatch $installation) "patch repaired" "stale patch repair result"
        Assert-Equal (Get-InstallationStatus "stable" $root).Status "patched" "repaired status"
    }

    Invoke-Test "uninstalls stale patch" {
        $env:LOCALAPPDATA = Join-Path $testRoot "data-uninstall-stale"
        $root = New-TestDiscord "uninstall-stale"
        $installation = Get-InstallationStatus "stable" $root
        Assert-Equal (Install-MobilePatch $installation) "patch applied" "install result"
        [IO.File]::WriteAllText($installation.Wrapper, $stalePatch)
        $installation = Get-InstallationStatus "stable" $root
        Assert-Equal (Uninstall-MobilePatch $installation) "official wrapper restored" "stale patch uninstall result"
        Assert-Equal (Get-InstallationStatus "stable" $root).Status "official" "restored status"
    }

    Invoke-Test "keeps current patch status" {
        $root = New-TestDiscord "current-patch" "app-1.0.100" (Get-PatchedWrapper)
        Assert-Equal (Get-InstallationStatus "stable" $root).Status "patched" "current patch status"
    }

    Invoke-Test "detects Stable and Canary" {
        $env:LOCALAPPDATA = Join-Path $testRoot "detected"
        $null = New-TestDiscord "detected\Discord"
        $null = New-TestDiscord "detected\DiscordCanary"
        $installations = @(Get-DetectedInstallations)
        Assert-Equal $installations.Count 2 "installation count"
        Assert-Equal $installations[0].Channel "stable" "first channel"
        Assert-Equal $installations[1].Channel "canary" "second channel"
    }

    Invoke-Test "fails with no detected Discord" {
        $env:LOCALAPPDATA = Join-Path $testRoot "empty"
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
        Assert-Throws { Invoke-Patcher "status" "auto" "" } "empty detection did not fail"
    }

    Write-Host "PowerShell tests passed: $passed"
}
finally {
    $script:SkipProcessCheck = $false
    $env:LOCALAPPDATA = $originalLocalAppData
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
