[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PatcherArguments
)

$ErrorActionPreference = "Stop"
$Repository = "uta-a/discord-erlpack-mobile-patcher"
$BinaryName = "erlpack-patcher-windows-x64.exe"
$ChecksumName = "$BinaryName.sha256"
$ReleasesApi = "https://api.github.com/repos/$Repository/releases?per_page=30"
$Headers = @{
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "fake-mobile-status-installer"
}

function Get-ReleaseAssetUrl {
    param(
        [Parameter(Mandatory)]
        [object]$Release,
        [Parameter(Mandatory)]
        [string]$Name
    )

    $asset = $Release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $asset) {
        throw "Release asset '$Name' was not found in $($Release.html_url)"
    }
    return $asset.browser_download_url
}

function Get-ExpectedHash {
    param([Parameter(Mandatory)][string]$ChecksumPath)

    $line = (Get-Content -LiteralPath $ChecksumPath -Raw).Trim()
    if ($line -notmatch "^(?<hash>[0-9a-fA-F]{64})\s+") {
        throw "Invalid SHA-256 file: $ChecksumName"
    }
    return $Matches.hash.ToLowerInvariant()
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw "Only 64-bit Windows is supported."
}

$TemporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("fake-mobile-status-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $TemporaryDirectory | Out-Null

try {
    Write-Host "Checking the latest Fake Mobile Status release..."
    $releases = Invoke-RestMethod -Uri $ReleasesApi -Headers $Headers
    $release = $releases | Where-Object {
        $_.assets.name -contains $BinaryName -and $_.assets.name -contains $ChecksumName
    } | Select-Object -First 1
    if (-not $release) {
        throw "No published release contains the required Windows patcher assets."
    }
    $binaryPath = Join-Path $TemporaryDirectory $BinaryName
    $checksumPath = Join-Path $TemporaryDirectory $ChecksumName

    Invoke-WebRequest -Uri (Get-ReleaseAssetUrl $release $BinaryName) -Headers $Headers -OutFile $binaryPath
    Invoke-WebRequest -Uri (Get-ReleaseAssetUrl $release $ChecksumName) -Headers $Headers -OutFile $checksumPath

    $expectedHash = Get-ExpectedHash $checksumPath
    $actualHash = (Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "SHA-256 verification failed. The downloaded file will not be executed."
    }

    Write-Host "Verified $($release.tag_name). Starting installer..."
    & $binaryPath @PatcherArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Installer exited with code $LASTEXITCODE."
    }
}
finally {
    if (Test-Path -LiteralPath $TemporaryDirectory) {
        Remove-Item -LiteralPath $TemporaryDirectory -Recurse -Force
    }
}
