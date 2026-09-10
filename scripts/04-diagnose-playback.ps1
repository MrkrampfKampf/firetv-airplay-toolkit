#Requires -Version 5.1
<#
.SYNOPSIS
    Records what the receiver does while a video fails, then explains why.
.DESCRIPTION
    Run this, reproduce the problem on your Apple device, press Enter. The script
    captures the receiver's log, saves it, and sorts what it found into causes:
    protected content, a decoder that refused the stream, a network failure, or
    something unclassified worth reading by hand.

    Use it before reporting a video that will not play, and attach the saved log.
.EXAMPLE
    .\scripts\04-diagnose-playback.ps1
    Uses the connection from the install step, or prompts for the address.
.EXAMPLE
    .\scripts\04-diagnose-playback.ps1 -FireTvIp <FIRE-TV-IP> -Label netflix
    Names the saved log so several attempts stay apart.
#>
[CmdletBinding()]
param(
    [string]$FireTvIp,
    [int]$Port = 5555,
    # Goes into the log file name, so one run per site stays identifiable.
    [string]$Label = 'session'
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogDir      = Join-Path $ProjectRoot 'logs'
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
if ($null -eq $adb) { throw 'adb not found. Run scripts\00a-get-adb.ps1 first.' }

# ------------------------------------------------------------ pick the device
$target = $null
if (-not [string]::IsNullOrEmpty($FireTvIp)) {
    $target = "${FireTvIp}:${Port}"
    & $adb connect $target | Out-Null
    Start-Sleep -Seconds 2
} else {
    # Reuse whatever the install step already connected.
    $devices = & $adb devices | Where-Object { $_ -match "`t device$" }
    if ($devices.Count -eq 1) {
        $target = ($devices[0] -split "`t")[0]
        Write-Host "Using the already connected device: $target"
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

# ---------------------------------------------------------------- context
Write-Step 'Device'
$model = (& $adb -s $target shell getprop ro.product.model) -join ''
$sdk   = (& $adb -s $target shell getprop ro.build.version.sdk) -join ''
$abi   = (& $adb -s $target shell getprop ro.product.cpu.abi) -join ''
$appVer = (& $adb -s $target shell dumpsys package $PackageName) |
          Where-Object { $_ -match 'versionName' } | Select-Object -First 1
Write-Host "  model $model, API $sdk, ABI $abi"
if ($appVer) { Write-Host "  app  $($appVer.Trim())" }

$running = (& $adb -s $target shell pidof $PackageName) -join ''
if ([string]::IsNullOrWhiteSpace($running)) {
    Write-Warning 'The receiver app is not running on the TV. Start it first, otherwise there is nothing to record.'
}

# ---------------------------------------------------------------- capture
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $LogDir "$stamp-$Label.log"

& $adb -s $target logcat -c
Write-Step 'Recording'
Write-Host @'
  1. On your Apple device, start mirroring if it is not already running.
  2. Open the site or app whose video fails and try to play it.
  3. Wait until you see the problem, a black picture, a stall, an error.
  4. Come back here and press Enter.
'@

$proc = Start-Process -FilePath $adb `
    -ArgumentList @('-s', $target, 'logcat', '-v', 'threadtime') `
    -RedirectStandardOutput $logFile -NoNewWindow -PassThru

try {
    Read-Host 'Press Enter when you have reproduced the problem'
} finally {
    if (-not $proc.HasExited) { $proc.Kill() }
    Start-Sleep -Milliseconds 500
}

if (-not (Test-Path $logFile)) { throw "No log was written to $logFile" }
$lines = Get-Content -Path $logFile
Write-Host "  captured $($lines.Count) lines into $logFile"

# ---------------------------------------------------------------- classify
# Ordered most to least conclusive: the first group that matches usually is the
# answer, so the report keeps them in this order.
$patterns = [ordered]@{
    'Protected content, cannot be shown' =
        'ERROR_CODE_DRM|MediaDrm|Widevine|FairPlay|secure buffer|SecureBufferPool|requires a secure decoder|protected content|OUTPUT_PROTECTION'
    'Decoder refused or crashed on the stream' =
        'Codec reported err|MediaCodec.*[Ee]xception|DecoderInitializationError|ERROR_CODE_DECODING|OMX.*[Ee]rror|c2\..*[Ee]rror|Decoder failed'
    'No decoder available for this format' =
        'DecoderQueryException|no decoder|NoDecoderException|ERROR_CODE_DECODER_INIT|not whitelisted|unsupported mime'
    'Network or server refused the stream' =
        'HttpDataSourceException|InvalidResponseCodeException|Response code|ERROR_CODE_IO|UnknownHostException|SSLHandshake|CleartextNotPermitted'
    'Stream parsed but stalled' =
        'ERROR_CODE_PARSING|ParserException|BehindLiveWindow|source error|Playback stalled'
    'Receiver logged a playback error' =
        'playback error|PlaybackException|onPlayerError'
}

Write-Step 'What the log shows'
$anyHit = $false
foreach ($name in $patterns.Keys) {
    $hits = $lines | Select-String -Pattern $patterns[$name] -CaseSensitive:$false
    if ($hits) {
        $anyHit = $true
        Write-Host "`n[$($hits.Count)] $name" -ForegroundColor Yellow
        $hits | Select-Object -First 4 | ForEach-Object { Write-Host "    $($_.Line.Trim())" }
        if ($hits.Count -gt 4) { Write-Host "    ... $($hits.Count - 4) more, see the log file" }
    }
}

# Which decoder was actually chosen tells you a lot about a stuttering picture.
$chosen = $lines | Select-String -Pattern 'DecoderSelector|configuring decoder|gl renderer' -CaseSensitive:$false
if ($chosen) {
    Write-Host "`n[info] Decoder decisions" -ForegroundColor Cyan
    $chosen | Select-Object -First 5 | ForEach-Object { Write-Host "    $($_.Line.Trim())" }
}

if (-not $anyHit) {
    Write-Host @'
  Nothing matched the known causes. Either the receiver never saw the stream, or
  the failure happens on the sending device before anything is transmitted. The
  latter is what protected video looks like: the picture goes black on the TV and
  the receiver logs nothing at all, because those frames are never sent.
'@
}

Write-Step 'Done'
Write-Host "Full log: $logFile"
Write-Host @'
Reading the result:

  Protected content        Nothing can be changed here. The sending device
                           refuses to transmit those frames to any receiver that
                           is not a genuine Apple TV.
  Decoder problems         Worth reporting. Lower the resolution or frame rate in
                           the app settings on the TV and try once more first.
  Network problems         Usually the site needs headers or cookies the receiver
                           does not send. Worth reporting with the log.
  Nothing at all           See the note above about protected video.
'@
