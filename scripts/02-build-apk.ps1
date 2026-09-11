#Requires -Version 5.1
<#
.SYNOPSIS
    Builds a signed, sideloadable AirPlay-receiver APK for Fire TV.
.DESCRIPTION
    Initialises the native submodules (UxPlay, FFmpeg, OpenSSL, libplist),
    creates a local signing key on first run, and runs the Gradle build for the
    ABIs a Fire TV actually needs. The native part is the slow half: expect
    45-120 minutes on the first build, minutes on later ones.
#>
[CmdletBinding()]
param(
    # Fire TV sticks are all ARM; x86_64 is dropped to save a third of the native build.
    [string]$Abis = 'arm64-v8a,armeabi-v7a',
    [ValidateSet('release', 'debug')]
    [string]$BuildType = 'release',
    [switch]$SkipSubmodules
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot    = Join-Path $ProjectRoot 'airplay-server'
$DistDir     = Join-Path $ProjectRoot 'dist'
$KeystoreDir = Join-Path $ProjectRoot 'keystore'
$EnvScript   = Join-Path $ProjectRoot 'toolchain-env.ps1'

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }

if (-not (Test-Path $EnvScript)) {
    throw "toolchain-env.ps1 not found. Run .\scripts\01-setup-toolchain.ps1 -AcceptSdkLicenses first."
}
. $EnvScript
Write-Host "JAVA_HOME    $env:JAVA_HOME"
Write-Host "ANDROID_HOME $env:ANDROID_HOME"

# ------------------------------------------------------------- submodules
if (-not $SkipSubmodules) {
    Write-Step 'Fetching submodules (upstream app, then UxPlay, FFmpeg, OpenSSL, libplist)'
    Write-Host '  shallow clones, but FFmpeg and OpenSSL are still a few hundred MB'
    # Recursing from the project root populates airplay-server and its own submodules in one pass.
    & git -C $ProjectRoot submodule update --init --recursive --progress
    if ($LASTEXITCODE -ne 0) { throw "git submodule update failed with exit code $LASTEXITCODE" }
} else {
    Write-Host 'Skipping submodule update (-SkipSubmodules)'
}

if (-not (Test-Path (Join-Path $RepoRoot 'app\build.gradle.kts'))) {
    throw "The airplay-server submodule is empty. Run: git submodule update --init --recursive"
}

# ------------------------------------------------------- our patches on the app
# The submodule is upstream's code, so fixes of our own live as patch files here
# and are reapplied on every build. This mirrors how upstream carries its own
# patches against UxPlay, and it keeps the submodule at its pinned commit.
$patchDir = Join-Path $ProjectRoot 'patches\app'
$patches = @()
if (Test-Path $patchDir) {
    $patches = @(Get-ChildItem -Path $patchDir -Filter '*.patch' | Sort-Object Name)
}
if ($patches.Count -gt 0) {
    Write-Step "Applying $($patches.Count) patch(es) from patches\app"
    foreach ($patch in $patches) {
        # --numstat only parses the patch, so it works whether or not it is applied.
        $numstat = & git -C $RepoRoot apply --numstat $patch.FullName
        if ($LASTEXITCODE -ne 0) { throw "Cannot read patch $($patch.Name). It probably no longer matches the pinned submodule commit." }
        $files = @($numstat | ForEach-Object { ($_ -split "`t")[-1] } | Where-Object { $_ })
        # Reset what the patch touches first, so rebuilding never stacks it twice.
        foreach ($file in $files) { & git -C $RepoRoot checkout -- $file }
        & git -C $RepoRoot apply $patch.FullName
        if ($LASTEXITCODE -ne 0) { throw "Failed to apply $($patch.Name)" }
        Write-Host "  $($patch.Name) -> $($files -join ', ')"
    }
} else {
    Write-Host 'No patches in patches\app, building upstream unchanged'
}

# ------------------------------------------------- make the ABI list settable
# Upstream hardcodes three ABIs. Turn that into a Gradle property so we can
# build only what a Fire TV runs. Idempotent: re-running changes nothing.
Write-Step "Restricting build to ABIs: $Abis"
$appGradle = Join-Path $RepoRoot 'app\build.gradle.kts'
$needle    = 'val allAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")'
$patched   = 'val allAbis = ((project.findProperty("firetvAbis") as String?) ?: "arm64-v8a,armeabi-v7a,x86_64").split(",")'
$content   = Get-Content -Path $appGradle -Raw
if ($content.Contains($patched)) {
    Write-Host '  build.gradle.kts already accepts -PfiretvAbis'
} elseif ($content.Contains($needle)) {
    $content.Replace($needle, $patched) | Set-Content -Path $appGradle -Encoding utf8 -NoNewline
    Write-Host '  patched build.gradle.kts to read -PfiretvAbis'
} else {
    Write-Warning '  ABI line not found upstream; building all ABIs instead'
}

# ---------------------------------------------------------------- signing key
function ConvertTo-JavaPropsPath { param([string]$Path) return $Path -replace '\', '\' }

$keystore = Join-Path $KeystoreDir 'firetv-sideload.p12'
$pwFile   = Join-Path $KeystoreDir 'keystore-password.txt'
$keyAlias = 'firetv'

if ($BuildType -eq 'release') {
    New-Item -ItemType Directory -Force -Path $KeystoreDir | Out-Null
    if (-not (Test-Path $keystore)) {
        Write-Step 'Creating a local signing key (valid 30 years)'
        $bytes = New-Object byte[] 24
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $storePassword = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '')
        $storePassword | Set-Content -Path $pwFile -Encoding ascii
        & (Join-Path $env:JAVA_HOME 'bin\keytool.exe') -genkeypair `
            -keystore $keystore -storetype PKCS12 -alias $keyAlias `
            -keyalg RSA -keysize 4096 -validity 10950 `
            -storepass $storePassword -keypass $storePassword `
            -dname 'CN=AirPlay Sideload, OU=Personal, O=Personal, C=DE'
        if ($LASTEXITCODE -ne 0) { throw "keytool failed with exit code $LASTEXITCODE" }
        Write-Host "  key at $keystore"
        Write-Host "  password saved to $pwFile -- keep it, you need the same key to update the app in place"
    } else {
        Write-Host "Reusing existing signing key: $keystore"
        $storePassword = (Get-Content -Path $pwFile -Raw).Trim()
    }

    Write-Step 'Writing signing config into local.properties'
    $localProps = Join-Path $RepoRoot 'local.properties'
    $kept = @()
    if (Test-Path $localProps) {
        $kept = Get-Content $localProps | Where-Object {
            $_ -notmatch '^\s*(storeFile|storePassword|keyAlias|keyPassword)\s*='
        }
    }
    $signing = @(
        'storeFile=' + (ConvertTo-JavaPropsPath $keystore),
        "storePassword=$storePassword",
        "keyAlias=$keyAlias",
        "keyPassword=$storePassword"
    )
    ($kept + $signing) | Set-Content -Path $localProps -Encoding utf8
}

# ---------------------------------------------------------------- the build
$task = 'assembleRelease'
if ($BuildType -eq 'debug') { $task = 'assembleDebug' }

Write-Step "Running Gradle: :app:$task"
Write-Host '  first run also downloads Gradle 8.11.1 and the Compose/Hilt/media3 dependencies'
Push-Location $RepoRoot
try {
    & .\gradlew.bat ":app:$task" "-PfiretvAbis=$Abis" --console=plain
    if ($LASTEXITCODE -ne 0) { throw "Gradle build failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

# ---------------------------------------------------------------- collect APK
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$built = Get-ChildItem -Path (Join-Path $RepoRoot "app\build\outputs\apk\$BuildType") -Filter '*.apk' -Recurse |
         Where-Object { $_.Name -notmatch 'unsigned' } |
         Sort-Object LastWriteTime -Descending |
         Select-Object -First 1
if ($null -eq $built) { throw "No APK found under app\build\outputs\apk\$BuildType" }

$version = 'unknown'
$m = [regex]::Match((Get-Content -Path $appGradle -Raw), 'versionName\s*=\s*"([^"]+)"')
if ($m.Success) { $version = $m.Groups[1].Value }

$outName = "airplay-receiver-$version-$BuildType-firetv.apk"
$outPath = Join-Path $DistDir $outName
Copy-Item -Path $built.FullName -Destination $outPath -Force

$sizeMb = [math]::Round((Get-Item $outPath).Length / 1MB, 1)
$sha    = (Get-FileHash -Path $outPath -Algorithm SHA256).Hash.ToLower()

Write-Step 'APK ready'
Write-Host "  file    $outPath"
Write-Host "  size    $sizeMb MB"
Write-Host "  abis    $Abis"
Write-Host "  sha256  $sha"
Write-Host "`nNext:  .\scripts\03-sideload-firetv.ps1 -FireTvIp <ip-of-your-stick>" -ForegroundColor Green
