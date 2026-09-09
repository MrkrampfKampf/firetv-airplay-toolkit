#Requires -Version 5.1
<#
.SYNOPSIS
    Sideloads the AirPlay receiver onto a Fire TV Stick over the network.
.DESCRIPTION
    Enable this on the stick first:
      Settings > My Fire TV > Developer Options > ADB Debugging = On
      Settings > My Fire TV > About > Network  (read the IP address there)
    The very first connect pops a "Allow USB debugging?" dialog on the TV.
    Accept it with the remote, then re-run this script.
.EXAMPLE
    .\scripts\03-sideload-firetv.ps1
    Prompts for the IP address of your Fire TV Stick.
.EXAMPLE
    .\scripts\03-sideload-firetv.ps1 -FireTvIp <FIRE-TV-IP>
    Pass the address directly if you already know it.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true,
        HelpMessage = 'IP address of your Fire TV Stick, from Settings > My Fire TV > About > Network')]
    [string]$FireTvIp,
    [string]$ApkPath,
    [int]$Port = 5555,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DistDir     = Join-Path $ProjectRoot 'dist'
$EnvScript   = Join-Path $ProjectRoot 'toolchain-env.ps1'
$PackageName = 'io.github.jqssun.airplay'

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }

if (Test-Path $EnvScript) { . $EnvScript }

# ------------------------------------------------------------------ find adb
$adb = $null
if ($env:ANDROID_HOME) {
    $candidate = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
    if (Test-Path $candidate) { $adb = $candidate }
}
if ($null -eq $adb) {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { $adb = $cmd.Source }
}
if ($null -eq $adb) {
    throw 'adb not found. Run scripts\01-setup-toolchain.ps1 (it installs platform-tools) or install Android platform-tools manually.'
}
Write-Host "adb: $adb"

# ------------------------------------------------------------------ find APK
if ([string]::IsNullOrEmpty($ApkPath)) {
    if (-not (Test-Path $DistDir)) { throw "No dist directory. Build with scripts\02-build-apk.ps1 or fetch the prebuilt APK with scripts\00-get-prebuilt-apk.ps1." }
    $newest = Get-ChildItem -Path $DistDir -Filter '*.apk' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $newest) { throw "No APK in $DistDir." }
    $ApkPath = $newest.FullName
}
if (-not (Test-Path $ApkPath)) { throw "APK not found: $ApkPath" }
$sizeMb = [math]::Round((Get-Item $ApkPath).Length / 1MB, 1)
Write-Host "apk: $ApkPath ($sizeMb MB)"

$target = "${FireTvIp}:${Port}"

Write-Step "Connecting to $target"
& $adb disconnect $target
& $adb connect $target
Start-Sleep -Seconds 2

$devices = & $adb devices
$devices | ForEach-Object { Write-Host "  $_" }
$line = $devices | Where-Object { $_ -match [regex]::Escape($target) }
if ($null -eq $line) {
    throw "Fire TV did not appear in 'adb devices'. Check that ADB Debugging is On and the IP is right."
}
if ($line -match 'unauthorized') {
    throw "Connection is unauthorized. Look at the TV: accept the 'Allow USB debugging' dialog with the remote, then re-run this script."
}
if ($line -match 'offline') {
    throw "Device reports offline. Reboot the stick (Settings > My Fire TV > Restart) and re-run."
}

Write-Step 'Device info'
& $adb -s $target shell getprop ro.product.model
& $adb -s $target shell getprop ro.build.version.release
& $adb -s $target shell getprop ro.product.cpu.abi

Write-Step "Installing $PackageName"
& $adb -s $target install -r $ApkPath
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'Install failed. If the error mentions signatures, the app is already installed with a different key.'
    Write-Warning "Uninstall it first:  $adb -s $target uninstall $PackageName"
    throw "adb install failed with exit code $LASTEXITCODE"
}

if (-not $NoLaunch) {
    Write-Step 'Launching the app on the TV'
    & $adb -s $target shell monkey -p $PackageName -c android.intent.category.LEANBACK_LAUNCHER 1
}

Write-Step 'Done'
Write-Host @"
On the TV the receiver is now listening. On your iPhone / iPad / Mac:
  open Control Center > Screen Mirroring and pick the receiver.

Useful follow-ups:
  live log:   $adb -s $target logcat -s AirPlay:V *:S
  uninstall:  $adb -s $target uninstall $PackageName
  disconnect: $adb disconnect $target

The app also appears in the Fire TV home under Settings > Applications, and
in "Your Apps & Channels" because it declares a Leanback launcher entry.
"@
