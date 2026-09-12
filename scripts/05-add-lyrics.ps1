#Requires -Version 5.1
<#
.SYNOPSIS
    Puts a lyrics file on the Fire TV so the receiver uses it for a track.
.DESCRIPTION
    The receiver looks in its own folder on the device before asking the online
    database, so anything you put there wins. That is how to get words for a song
    the database does not carry, and how to correct a match you disagree with.

    Two formats:
      .lrc  timestamped, so the highlight follows the music
      .txt  plain, shown without highlighting

    An .lrc line looks like "[01:23.45] the words", one line per lyric line. The
    file name is matched loosely against the track, so "Artist - Title.lrc",
    "Title.lrc" and "Title (Whatever).lrc" all work. Nothing here writes lyrics for
    you; supply a file you already have.
.EXAMPLE
    .\scripts\05-add-lyrics.ps1 -File .\my-song.lrc -FireTvIp <FIRE-TV-IP>
.EXAMPLE
    .\scripts\05-add-lyrics.ps1 -List
    Shows what is already on the device.
#>
[CmdletBinding()]
param(
    [string]$File,
    [string]$FireTvIp,
    [int]$Port = 5555,
    [switch]$List,
    [string]$Remove
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EnvScript   = Join-Path $ProjectRoot 'toolchain-env.ps1'
$PackageName = 'io.github.jqssun.airplay'
$DeviceDir   = "/sdcard/Android/data/$PackageName/files/lyrics"

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }

if (Test-Path $EnvScript) { . $EnvScript }

$adb = $null
if ($env:ANDROID_HOME) {
    $candidate = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
    if (Test-Path $candidate) { $adb = $candidate }
}
if ($null -eq $adb) {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { $adb = $cmd.Source }
}
if ($null -eq $adb) { throw 'adb not found. Run scripts\00a-get-adb.ps1 first.' }

# Reuse an existing connection when there is exactly one, the way the diagnostic does.
$target = $null
if (-not [string]::IsNullOrEmpty($FireTvIp)) {
    $target = "${FireTvIp}:${Port}"
    & $adb connect $target | Out-Null
    Start-Sleep -Seconds 2
} else {
    $devices = & $adb devices | Where-Object { $_ -match "`t device$" }
    if ($devices.Count -eq 1) {
        $target = ($devices[0] -split "`t")[0]
    } else {
        $entered = Read-Host 'IP address of your Fire TV Stick'
        $target = "${entered}:${Port}"
        & $adb connect $target | Out-Null
        Start-Sleep -Seconds 2
    }
}

$state = & $adb devices | Where-Object { $_ -match [regex]::Escape($target) }
if ($null -eq $state) { throw "$target is not connected. Check that ADB debugging is on." }
if ($state -match 'unauthorized') { throw 'Connection unauthorized. Accept the dialog on your TV, then run this again.' }

& $adb -s $target shell mkdir -p $DeviceDir | Out-Null

if ($List) {
    Write-Step 'Lyrics files on the device'
    $listing = & $adb -s $target shell ls -1 $DeviceDir
    if ($listing) { $listing | ForEach-Object { Write-Host "  $_" } } else { Write-Host '  none' }
    return
}

if (-not [string]::IsNullOrEmpty($Remove)) {
    Write-Step "Removing $Remove"
    & $adb -s $target shell rm -f "$DeviceDir/$Remove"
    Write-Host '  done'
    return
}

if ([string]::IsNullOrEmpty($File)) {
    throw 'Give -File the path to an .lrc or .txt file, or pass -List to see what is there.'
}
if (-not (Test-Path $File)) { throw "No such file: $File" }
$item = Get-Item $File
if ($item.Extension.ToLower() -notin @('.lrc', '.txt')) {
    throw "Expected an .lrc or .txt file, got $($item.Extension)"
}

Write-Step "Sending $($item.Name)"
& $adb -s $target push $item.FullName "$DeviceDir/$($item.Name)"
if ($LASTEXITCODE -ne 0) { throw "adb push failed with exit code $LASTEXITCODE" }

$timed = (Get-Content -Path $item.FullName -TotalCount 40 | Where-Object { $_ -match '^\s*\[\d{1,3}:\d{2}' }).Count
Write-Step 'Done'
if ($timed -gt 0) {
    Write-Host "  $timed timestamped lines found, the highlight will follow the music"
} else {
    Write-Host '  no timestamps found, the words will be shown without highlighting'
}
Write-Host '  play the track again on the TV to pick it up'
