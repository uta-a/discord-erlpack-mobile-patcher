[CmdletBinding()]
param(
    [ValidateSet("menu", "status", "install", "uninstall")]
    [string]$Action = "menu",

    [ValidateSet("auto", "stable", "canary")]
    [string]$Channel = "auto",

    [string]$DiscordPath
)

$ErrorActionPreference = "Stop"
$Repository = "uta-a/discord-erlpack-mobile-patcher"
$ScriptName = "patcher.ps1"
$ChecksumName = "$ScriptName.sha256"
$ReleasesApi = "https://api.github.com/repos/$Repository/releases?per_page=30"
$Headers = @{
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "discord-erlpack-mobile-patcher"
}

function Get-ReleaseAssetUrl {
    param([object]$Release, [string]$Name)
    $asset = $Release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $asset) {
        throw "Release asset '$Name' was not found in $($Release.html_url)"
    }
    return $asset.browser_download_url
}

function Get-ExpectedHash {
    param([string]$ChecksumPath)
    $line = (Get-Content -LiteralPath $ChecksumPath -Raw).Trim()
    if ($line -notmatch "^(?<hash>[0-9a-fA-F]{64})\s+") {
        throw "Invalid SHA-256 file: $ChecksumName"
    }
    return $Matches.hash.ToLowerInvariant()
}

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("discord-erlpack-patcher-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

try {
    Write-Host "Checking the latest PowerShell patcher release..."
    $releases = Invoke-RestMethod -Uri $ReleasesApi -Headers $Headers
    $release = $releases | Where-Object {
        $_.assets.name -contains $ScriptName -and $_.assets.name -contains $ChecksumName
    } | Select-Object -First 1
    if (-not $release) {
        throw "No published release contains the required PowerShell patcher assets."
    }

    $scriptPath = Join-Path $temporaryDirectory $ScriptName
    $checksumPath = Join-Path $temporaryDirectory $ChecksumName
    Invoke-WebRequest -Uri (Get-ReleaseAssetUrl $release $ScriptName) -Headers $Headers -OutFile $scriptPath
    Invoke-WebRequest -Uri (Get-ReleaseAssetUrl $release $ChecksumName) -Headers $Headers -OutFile $checksumPath

    $expectedHash = Get-ExpectedHash $checksumPath
    $actualHash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "SHA-256 verification failed. The downloaded script will not be executed."
    }

    Write-Host "Verified $($release.tag_name). Starting PowerShell patcher..."
    $source = Get-Content -LiteralPath $scriptPath -Raw
    $patcher = [ScriptBlock]::Create($source)
    if ($DiscordPath) {
        & $patcher -Action $Action -Channel $Channel -DiscordPath $DiscordPath
    }
    else {
        & $patcher -Action $Action -Channel $Channel
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}
