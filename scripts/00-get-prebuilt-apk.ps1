#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads the upstream-signed release APK from the project's GitHub Releases.
.DESCRIPTION
    The fast path: no toolchain, no native build. This is the maintainer's own
    signed build of the exact source tree in .\airplay-server. Roughly 25 MB and
    it contains all three ABIs, so it runs on any Fire TV generation.
#>
[CmdletBinding()]
param(
    [string]$Repo = 'jqssun/android-airplay-server',
    [string]$Tag  = 'latest'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DistDir     = Join-Path $ProjectRoot 'dist'

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }

$api = "https://api.github.com/repos/$Repo/releases/latest"
if ($Tag -ne 'latest') { $api = "https://api.github.com/repos/$Repo/releases/tags/$Tag" }

Write-Step "Querying $api"
$release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'firetv-airplay-setup' }
Write-Host "  release $($release.tag_name) published $($release.published_at)"

$asset = $release.assets | Where-Object { $_.name -like '*.apk' } | Select-Object -First 1
if ($null -eq $asset) { throw "No .apk asset in release $($release.tag_name)." }

$sizeMb = [math]::Round($asset.size / 1MB, 1)
Write-Host "  asset $($asset.name) ($sizeMb MB)"

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$outPath = Join-Path $DistDir "airplay-receiver-$($release.tag_name)-upstream.apk"

Write-Step 'Downloading'
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $outPath -UseBasicParsing

$sha = (Get-FileHash -Path $outPath -Algorithm SHA256).Hash.ToLower()
Write-Step 'Downloaded'
Write-Host "  file    $outPath"
Write-Host "  sha256  $sha"
if ($asset.digest) { Write-Host "  github  $($asset.digest)" }
Write-Host "`nNext:  .\scripts\03-sideload-firetv.ps1 -FireTvIp <ip-of-your-stick>" -ForegroundColor Green
