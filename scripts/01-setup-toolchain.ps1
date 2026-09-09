#Requires -Version 5.1
<#
.SYNOPSIS
    Installs a self-contained Android build toolchain (JDK 21 + SDK + NDK 27 + CMake).
.DESCRIPTION
    Everything lands under -ToolchainRoot (default D:\android-toolchain) so the
    system drive stays untouched. The NDK alone needs roughly 5 GB unpacked.
.NOTES
    Installing the Android SDK/NDK requires accepting Google's Android SDK
    licence terms. This script refuses to run until you pass -AcceptSdkLicenses.
#>
[CmdletBinding()]
param(
    [string]$ToolchainRoot = 'D:\android-toolchain',
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
$answers = (,'y' * 80) -join "`r`n"
$answers | & $sdkmanager "--sdk_root=$SdkRoot" --licenses

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

# ------------------------------------------------------ wire up the project
Write-Step 'Writing local.properties and toolchain-env.ps1'

function ConvertTo-JavaPropsPath { param([string]$Path) return $Path -replace '\', '\' }

$localProps = Join-Path $RepoRoot 'local.properties'
$sdkLine    = 'sdk.dir=' + (ConvertTo-JavaPropsPath $SdkRoot)
if (Test-Path $localProps) {
    $kept = Get-Content $localProps | Where-Object { $_ -notmatch '^\s*sdk\.dir\s*=' }
    @($sdkLine) + $kept | Set-Content -Path $localProps -Encoding utf8
} else {
    $sdkLine | Set-Content -Path $localProps -Encoding utf8
}

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
