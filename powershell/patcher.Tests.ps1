$scriptPath = Join-Path $PSScriptRoot "patcher.ps1"
. $scriptPath -NoRun

Describe "PowerShell patcher" {
    BeforeEach {
        $script:SkipProcessCheck = $true
        $script:OriginalLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive "local"
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
        $script:Official = "`"use strict`";`r`nmodule.exports = require('./discord_erlpack.node');`r`n"
    }

    AfterEach {
        $script:SkipProcessCheck = $false
        $env:LOCALAPPDATA = $script:OriginalLocalAppData
    }

    function New-TestDiscord {
        param([string]$Name, [string]$Version = "app-1.0.100", [string]$Content = $script:Official)
        $root = Join-Path $TestDrive $Name
        $wrapperDirectory = Join-Path $root "$Version\modules\discord_erlpack-1\discord_erlpack"
        New-Item -ItemType Directory -Path $wrapperDirectory -Force | Out-Null
        $wrapper = Join-Path $wrapperDirectory "index.js"
        [IO.File]::WriteAllText($wrapper, $Content)
        return $root
    }

    It "selects the newest complete Discord version" {
        $root = New-TestDiscord "discord" "app-1.0.99"
        $null = New-TestDiscord "discord" "app-1.0.100"
        New-Item -ItemType Directory -Path (Join-Path $root "app-1.0.101\modules") -Force | Out-Null

        $target = Get-DiscordTarget $root

        $target.AppVersion | Should Be "app-1.0.100"
    }

    It "installs and uninstalls without changing unknown files" {
        $root = New-TestDiscord "discord"
        $installation = Get-InstallationStatus "stable" $root

        (Install-MobilePatch $installation) | Should Be "patch applied"
        (Get-InstallationStatus "stable" $root).Status | Should Be "patched"

        $installation = Get-InstallationStatus "stable" $root
        (Uninstall-MobilePatch $installation) | Should Be "official wrapper restored"
        (Get-InstallationStatus "stable" $root).Status | Should Be "official"
    }

    It "refuses an unknown wrapper" {
        $root = New-TestDiscord "discord" "app-1.0.100" "module.exports = thirdParty;"
        $installation = Get-InstallationStatus "stable" $root

        { Install-MobilePatch $installation } | Should Throw
        [IO.File]::ReadAllText($installation.Wrapper) | Should Be "module.exports = thirdParty;"
    }

    It "detects Stable and Canary" {
        $null = New-TestDiscord "local\Discord"
        $null = New-TestDiscord "local\DiscordCanary"

        $installations = @(Get-DetectedInstallations)

        $installations.Count | Should Be 2
        $installations[0].Channel | Should Be "stable"
        $installations[1].Channel | Should Be "canary"
    }

    It "fails immediately when no Discord installation is detected" {
        Mock Get-DetectedInstallations { @() }

        { Invoke-Patcher "status" "auto" "" } | Should Throw
    }
}
