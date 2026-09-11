#Requires -Version 5.1
<#
.SYNOPSIS
    Installs a self-contained Android build toolchain (JDK 21 + SDK + NDK 27 + CMake).
.DESCRIPTION
    Everything lands under -ToolchainRoot, by default a "toolchain" folder next
    to this repository. Point it at another drive if your system drive is tight.
    The NDK alone needs roughly 5 GB unpacked.
.NOTES
    Installing the Android SDK/NDK requires accepting Google's Android SDK
    licence terms. This script refuses to run until you pass -AcceptSdkLicenses.
#>
[CmdletBinding()]
param(
    [string]$ToolchainRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'toolchain'),
    [string]$NdkVersion    = '27.0.12077973',
    [string]$PlatformApi   = 'android-36',
    [string]$BuildToolsVer = '36.0.0',
    [string]$CmakeVersion  = '3.31.5',
    [switch]$AcceptSdkLicenses
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # Invoke-WebRequest is ~10x faster without the progress bar

# Pinned, verified sources.
$JdkUrl          = 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse'
$CmdlineToolsUrl = 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip'

$Downloads  = Join-Path $ToolchainRoot 'downloads'
$JdkRoot    = Join-Path $ToolchainRoot 'jdk21'
$SdkRoot    = Join-Path $ToolchainRoot 'android-sdk'
$GradleHome = Join-Path $ToolchainRoot 'gradle-home'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot    = Join-Path $ProjectRoot 'airplay-server'

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }

if (-not $AcceptSdkLicenses) {
    Write-Host @'
This installs the Android SDK, NDK and CMake from dl.google.com, which requires
accepting the Android Software Development Kit Licence Agreement:

    https://developer.android.com/studio/terms

Read those terms, then re-run with the switch that records your acceptance:

    .\scripts\01-setup-toolchain.ps1 -AcceptSdkLicenses

Download budget: JDK 21 ~196 MB, command-line tools ~136 MB,
platform + build-tools ~120 MB, NDK 27 ~2.5 GB, CMake ~40 MB.
Unpacked footprint: roughly 9-11 GB under the toolchain root.
'@
    exit 1
}

function Get-Archive {
    param([string]$Url, [string]$OutFile, [string]$Label)
    if (Test-Path $OutFile) {
        $mb = [math]::Round((Get-Item $OutFile).Length / 1MB, 1)
        Write-Host "  reusing cached download: $(Split-Path -Leaf $OutFile) ($mb MB)"
        return
    }
    Write-Step "Downloading $Label"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    $mb = [math]::Round((Get-Item $OutFile).Length / 1MB, 1)
    Write-Host "  saved $OutFile ($mb MB)"
}

function Expand-Into {
    param([string]$Zip, [string]$Target, [string]$InnerName)
    $staging = Join-Path $Downloads ('staging-' + [IO.Path]::GetFileNameWithoutExtension($Zip))
    if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
    Expand-Archive -Path $Zip -DestinationPath $staging -Force
    if ([string]::IsNullOrEmpty($InnerName)) {
        $inner = (Get-ChildItem -Path $staging -Directory | Select-Object -First 1).FullName
    } else {
        $inner = Join-Path $staging $InnerName
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
    if (Test-Path $Target) { Remove-Item -Recurse -Force $Target }
    Move-Item -Path $inner -Destination $Target
    Remove-Item -Recurse -Force $staging
}

New-Item -ItemType Directory -Force -Path $ToolchainRoot, $Downloads, $GradleHome | Out-Null

# ---------------------------------------------------------------- JDK 21
$jdkZip = Join-Path $Downloads 'temurin-jdk21-windows-x64.zip'
Get-Archive -Url $JdkUrl -OutFile $jdkZip -Label 'Eclipse Temurin JDK 21 (~196 MB)'
if (-not (Test-Path (Join-Path $JdkRoot 'bin\javac.exe'))) {
    Write-Step 'Unpacking JDK 21'
    Expand-Into -Zip $jdkZip -Target $JdkRoot -InnerName ''
}
$env:JAVA_HOME = $JdkRoot
$env:PATH      = (Join-Path $JdkRoot 'bin') + ';' + $env:PATH
& (Join-Path $JdkRoot 'bin\java.exe') -version

# ------------------------------------------------- Android command-line tools
$ctZip    = Join-Path $Downloads 'commandlinetools-windows.zip'
$ctLatest = Join-Path $SdkRoot 'cmdline-tools\latest'
Get-Archive -Url $CmdlineToolsUrl -OutFile $ctZip -Label 'Android command-line tools (~136 MB)'
if (-not (Test-Path (Join-Path $ctLatest 'bin\sdkmanager.bat'))) {
    Write-Step 'Unpacking command-line tools'
    Expand-Into -Zip $ctZip -Target $ctLatest -InnerName 'cmdline-tools'
}

$sdkmanager = Join-Path $ctLatest 'bin\sdkmanager.bat'

Write-Step 'Accepting Android SDK licences (you passed -AcceptSdkLicenses)'
# sdkmanager.bat is a wrapper that launches java, and a PowerShell pipeline does
# not reach the prompts behind it: every answer is swallowed and all packages stay
# unlicensed. Redirecting stdin from a file of answers does get through.
$answerFile = Join-Path $Downloads 'licence-answers.txt'
Set-Content -Path $answerFile -Value (@('y') * 200) -Encoding ascii
$licenceLog = Join-Path $Downloads 'licence-output.txt'
$licenceProc = Start-Process -FilePath $sdkmanager `
    -ArgumentList "--sdk_root=$SdkRoot", '--licenses' `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardInput $answerFile -RedirectStandardOutput $licenceLog
if ($licenceProc.ExitCode -ne 0) { throw "sdkmanager --licenses failed with exit code $($licenceProc.ExitCode). See $licenceLog" }

$licenceDir = Join-Path $SdkRoot 'licenses'
if (-not (Test-Path $licenceDir)) { throw "No licences were recorded in $licenceDir. See $licenceLog" }
Write-Host "  recorded $(@(Get-ChildItem -Path $licenceDir -File).Count) licence file(s)"

# -------------------------------------------------------------- SDK packages
$packages = @(
    'platform-tools',
    "platforms;$PlatformApi",
    "build-tools;$BuildToolsVer",
    "ndk;$NdkVersion",
    "cmake;$CmakeVersion"
)
Write-Step "Installing SDK packages: $($packages -join ', ')"
Write-Host '  the NDK is the slow one (~2.5 GB download, ~5 GB unpacked)'
& $sdkmanager "--sdk_root=$SdkRoot" --install $packages
if ($LASTEXITCODE -ne 0) { throw "sdkmanager --install failed with exit code $LASTEXITCODE" }

# sdkmanager exits 0 even when it installed nothing because a licence was missing,
# so the only trustworthy check is whether the files landed on disk. Without this
# the script cheerfully reports a ready toolchain over an empty SDK.
$expected = [ordered]@{
    'platform-tools'             = 'platform-tools/adb.exe'
    "platforms;$PlatformApi"     = "platforms/$PlatformApi/android.jar"
    "build-tools;$BuildToolsVer" = "build-tools/$BuildToolsVer/aapt2.exe"
    "ndk;$NdkVersion"            = "ndk/$NdkVersion/source.properties"
    "cmake;$CmakeVersion"        = "cmake/$CmakeVersion/bin/cmake.exe"
}
$missing = @()
foreach ($pkg in $expected.Keys) {
    if (-not (Test-Path (Join-Path $SdkRoot $expected[$pkg]))) { $missing += $pkg }
}
if ($missing.Count -gt 0) {
    throw "Not installed: $($missing -join ', '). An unaccepted licence is the usual cause."
}
Write-Host '  all packages verified on disk'

# ------------------------------------------------------ wire up the project
Write-Step 'Writing local.properties and toolchain-env.ps1'

# Java .properties treats a backslash as an escape. Forward slashes work fine on
# Windows, so normalise instead of doubling up, and keep the separator out of
# this source entirely.
function ConvertTo-JavaPropsPath { param([string]$Path) return $Path.Replace([char]92, '/') }


# Java's Properties.load knows nothing about a byte order mark: it folds one into
# the first key name, so sdk.dir silently stops being sdk.dir. PowerShell 5.1 emits
# a BOM with -Encoding utf8, so these files go through .NET instead.
function Write-PropsFile {
    param([string]$Path, [string[]]$Lines)
    [System.IO.File]::WriteAllLines($Path, $Lines, (New-Object System.Text.UTF8Encoding($false)))
}

$localProps = Join-Path $RepoRoot 'local.properties'
$sdkLine    = 'sdk.dir=' + (ConvertTo-JavaPropsPath $SdkRoot)
$propLines  = @($sdkLine)
if (Test-Path $localProps) {
    $propLines += @(Get-Content $localProps | Where-Object { $_ -notmatch '^\s*sdk\.dir\s*=' })
}
Write-PropsFile -Path $localProps -Lines $propLines

$envScript = Join-Path $ProjectRoot 'toolchain-env.ps1'
@"
# Generated by scripts\01-setup-toolchain.ps1 -- dot-source this to get the toolchain on PATH.
`$env:JAVA_HOME        = '$JdkRoot'
`$env:ANDROID_HOME     = '$SdkRoot'
`$env:ANDROID_SDK_ROOT = '$SdkRoot'
`$env:GRADLE_USER_HOME = '$GradleHome'
`$env:PATH             = '$JdkRoot\bin;$SdkRoot\platform-tools;' + `$env:PATH
"@ | Set-Content -Path $envScript -Encoding utf8

Write-Step 'Toolchain ready'
Write-Host "  JAVA_HOME        $JdkRoot"
Write-Host "  ANDROID_HOME     $SdkRoot"
Write-Host "  GRADLE_USER_HOME $GradleHome   (keeps Gradle caches off C:)"
Write-Host "  NDK              $(Join-Path $SdkRoot ('ndk\' + $NdkVersion))"
Write-Host "`nNext:  .\scripts\02-build-apk.ps1" -ForegroundColor Green
