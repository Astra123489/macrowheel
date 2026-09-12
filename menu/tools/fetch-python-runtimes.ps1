<#
.SYNOPSIS
    Downloads and lays out the two embedded Python runtimes used by Macro Wheel.

.DESCRIPTION
    Macro Wheel keeps two hard-isolated Python environments (spec section 13.2,
    rules 25-31):

      command_runtime/   application-owned, locked, not user-configurable.
                         Used only by built-in command functionality that
                         genuinely needs the Resolve scripting API.

      script_runtime/    user-facing, configurable. Runs user-authored .py
                         files from the fixed Scripts folder and may have
                         packages installed into it by the user.

    Both come from the same python-build-standalone archive. After extraction
    the Command Runtime is stripped of its package-management tooling so it
    cannot be modified through Studio.

    The Command Runtime support module (macro_wheel_commands.py) is kept in
    tools/python/ and copied in here, because command_runtime/ is deleted and
    re-extracted on every fetch.

.PARAMETER PythonVersion
    Python series to fetch, e.g. 3.12. Default: 3.12.

.PARAMETER BuildTag
    python-build-standalone release tag. Omit to resolve the newest release
    that contains the requested Python version.

.PARAMETER Force
    Re-download and re-extract even when the archive is already cached.

.EXAMPLE
    pwsh -File menu/tools/fetch-python-runtimes.ps1
#>
[CmdletBinding()]
param(
    [string]$PythonVersion = '3.12',
    [string]$BuildTag,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# This script targets Windows PowerShell 5.1 as well as PowerShell 7+, so it
# avoids $IsWindows / $IsMacOS (PowerShell 7+ only) and Set-StrictMode.
#
# Windows PowerShell 5.1 still negotiates TLS 1.0/1.1 by default, which GitHub
# refuses. Opt into TLS 1.2 for this process before any web request.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.SecurityProtocolType]::Tls12 -bor `
        [Net.SecurityProtocolType]::Tls11 -bor `
        [Net.SecurityProtocolType]::Tls
}

$repoRoot   = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$pythonRoot = Join-Path $repoRoot 'resources/python'
$cacheDir   = Join-Path $repoRoot 'tools/.cache'

$commandDir = Join-Path $pythonRoot 'command_runtime'
$scriptDir  = Join-Path $pythonRoot 'script_runtime'

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Reset-Directory([string]$Path) {
    if (Test-Path $Path) {
        Remove-Item -Path $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Copy-Tree {
    <#
        Copies every file from $Source into $Destination.

        robocopy is used on Windows rather than Copy-Item. A wildcard
        Copy-Item run enumerates the source and then copies, so a single stale
        entry aborts the whole tree. robocopy walks the source itself, so a
        file that is absent from the archive is simply not copied and reported
        through its exit code (0-7 mean success).
    #>
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if ($isWindowsHost -and (Get-Command robocopy.exe -ErrorAction SilentlyContinue)) {
        & robocopy.exe $Source $Destination /E /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "robocopy failed copying $Source -> $Destination (exit $LASTEXITCODE)."
        }
        return
    }

    # macOS / Linux.
    & cp -a "$Source/." "$Destination/"
    if ($LASTEXITCODE -ne 0) {
        throw "cp failed copying $Source -> $Destination (exit $LASTEXITCODE)."
    }
}

function Assert-Runtime {
    <#
        Confirms a runtime tree contains a working interpreter. This is the
        real acceptance criterion: a tree that copied cleanly but cannot run
        Python is useless, and a tree missing an obsolete stdlib helper is not.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Label
    )

    $exe = Join-Path $Root $pythonExeRel
    if (-not (Test-Path $exe)) {
        throw "$Label has no interpreter at $exe."
    }

    $version = (& $exe --version 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$Label interpreter did not run: $version"
    }

    Write-Host "    $Label : $version"
}

# --- Platform detection ------------------------------------------------------
#
# Works on both Windows PowerShell 5.1 and PowerShell 7+. On 5.1 the runtime
# platform is always Windows, so the macOS/Linux branches only matter on 7+.

$isWindowsHost = $true
$isMacHost     = $false

if ($PSVersionTable.PSVersion.Major -ge 6) {
    $isWindowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)
    $isMacHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::OSX)
} else {
    $isWindowsHost = $env:OS -eq 'Windows_NT'
}

$platformAsset = if ($isWindowsHost) {
    'x86_64-pc-windows-msvc'
} elseif ($isMacHost) {
    if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') {
        'aarch64-apple-darwin'
    } else {
        'x86_64-apple-darwin'
    }
} else {
    'x86_64-unknown-linux-gnu'
}

$pythonExeRel = if ($isWindowsHost) { 'python.exe' } else { 'bin/python3' }

# --- Resolve the download ----------------------------------------------------

if (-not $BuildTag) {
    Write-Step "Resolving the newest python-build-standalone release for $PythonVersion"
    $releases = Invoke-RestMethod `
        -Uri 'https://api.github.com/repos/astral-sh/python-build-standalone/releases?per_page=15' `
        -Headers @{ 'User-Agent' = 'MacroWheel' }

    $match = $null
    foreach ($release in $releases) {
        $asset = $release.assets | Where-Object {
            $_.name -like "cpython-$PythonVersion.*-$platformAsset-install_only.tar.gz"
        } | Select-Object -First 1
        if ($asset) {
            $match = [pscustomobject]@{ Tag = $release.tag_name; Asset = $asset }
            break
        }
    }
    if (-not $match) {
        throw "No python-build-standalone asset found for Python $PythonVersion / $platformAsset."
    }
    $BuildTag  = $match.Tag
    $assetUrl  = $match.Asset.browser_download_url
    $assetName = $match.Asset.name
} else {
    $assetName = "cpython-$PythonVersion.0+$BuildTag-$platformAsset-install_only.tar.gz"
    $assetUrl  = "https://github.com/astral-sh/python-build-standalone/releases/download/$BuildTag/$assetName"
}

Write-Step "Runtime: $assetName (tag $BuildTag)"

if (-not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
}
$archivePath = Join-Path $cacheDir $assetName

# --- Download ----------------------------------------------------------------

if ($Force -or -not (Test-Path $archivePath) -or ((Get-Item $archivePath).Length -eq 0)) {
    Write-Step "Downloading to $archivePath"

    # A dropped connection is common on large archives; retry a few times
    # rather than leaving a truncated file in the cache.
    $downloaded = $false
    for ($attempt = 1; $attempt -le 4 -and -not $downloaded; $attempt++) {
        try {
            Invoke-WebRequest -Uri $assetUrl -OutFile $archivePath `
                -Headers @{ 'User-Agent' = 'MacroWheel' } -ErrorAction Stop
            $downloaded = (Test-Path $archivePath) -and ((Get-Item $archivePath).Length -gt 0)
        } catch {
            Write-Warning "Download attempt $attempt failed: $($_.Exception.Message)"
            if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
            if ($attempt -lt 4) { Start-Sleep -Seconds (2 * $attempt) }
        }
    }
    if (-not $downloaded) {
        throw "Could not download $assetName after 4 attempts."
    }
} else {
    Write-Step 'Archive already cached'
}

# --- Verify checksum when the release publishes one --------------------------

# Fetch the published digest with retries. A failure here means we could not
# verify, not that the archive is bad, so it downgrades to a warning. An
# actual mismatch is always fatal.
$expected = $null
for ($attempt = 1; $attempt -le 3 -and -not $expected; $attempt++) {
    try {
        $text = (Invoke-WebRequest -Uri "$assetUrl.sha256" `
                    -Headers @{ 'User-Agent' = 'MacroWheel' } -ErrorAction Stop).Content
        $candidate = ($text -split '\s+')[0].Trim().ToLower()
        if ($candidate) { $expected = $candidate }
    } catch {
        if ($attempt -lt 3) { Start-Sleep -Seconds (2 * $attempt) }
    }
}

if ($expected) {
    $actual = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        throw "Checksum mismatch for $assetName (expected $expected, got $actual)."
    }
    Write-Step 'Checksum verified'
} else {
    Write-Warning 'No .sha256 published for this asset; checksum verification skipped.'
}

# --- Extract ------------------------------------------------------------------

$staging = Join-Path $cacheDir 'staging'
Reset-Directory $staging

Write-Step 'Extracting'
tar -xzf $archivePath -C $staging
if ($LASTEXITCODE -ne 0) {
    throw "Extraction failed (tar exit $LASTEXITCODE)."
}

# The archive contains a single top-level `python/` directory.
$extracted = Join-Path $staging 'python'
if (-not (Test-Path $extracted)) {
    throw "Unexpected archive layout: $extracted not found."
}

# --- Script Runtime (full, user-facing) --------------------------------------

Write-Step "Installing Script Runtime -> $scriptDir"
Reset-Directory $scriptDir
Copy-Tree -Source $extracted -Destination $scriptDir

# Bundled Script packages live apart from user packages so a user operation can
# never silently replace or downgrade a Macro Wheel-managed dependency
# (spec 13.2.5, rule 29).
$bundled = Join-Path $scriptDir 'site-packages/bundled'
$user    = Join-Path $scriptDir 'site-packages/user'
New-Item -ItemType Directory -Path $bundled, $user -Force | Out-Null

# --- Command Runtime (locked, application-owned) -----------------------------

# Copied from the Script Runtime tree rather than straight from staging. That
# tree has already been materialised on disk once, so this avoids re-walking
# the extracted archive and cannot be tripped by a second enumeration of the
# same source.
Write-Step "Installing Command Runtime -> $commandDir"
Reset-Directory $commandDir
Copy-Tree -Source $scriptDir -Destination $commandDir

# Strip anything that would let a user change the Command Runtime. The
# interpreter itself stays so built-in commands can still reach the Resolve
# scripting API when they need it.
$strip = @(
    'pip', 'pip-*', 'setuptools', 'setuptools-*', 'wheel', 'wheel-*',
    'ensurepip', 'pip.exe', 'pip3.exe', 'easy_install.exe',
    # Deprecated or unused by built-in commands; removing them keeps the
    # locked runtime small as well as sealed.
    'lib2to3', 'idlelib'
)
foreach ($pattern in $strip) {
    Get-ChildItem -Path $commandDir -Filter $pattern -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
}

# The support module lives in tools/python/ because command_runtime/ is wiped
# above on every fetch.
$moduleSource = Join-Path $repoRoot 'tools/python/macro_wheel_commands.py'
if (-not (Test-Path $moduleSource)) {
    throw "Command Runtime support module not found: $moduleSource"
}
Copy-Item -Path $moduleSource -Destination $commandDir -Force

# A marker file recording how this runtime was produced.
$pythonExe = Join-Path $commandDir $pythonExeRel
$version = if (Test-Path $pythonExe) { (& $pythonExe --version) 2>&1 } else { 'python (not runnable here)' }
@"
Macro Wheel Command Runtime
Locked and application-owned (spec section 13.2.1 / rules 25-26).

Do not modify, add packages to, or point Macro Wheel at a replacement
interpreter. User package operations target the Script Runtime only.

$version
Fetched from python-build-standalone $BuildTag
"@ | Set-Content -Path (Join-Path $commandDir 'RUNTIME.txt') -Encoding UTF8

Remove-Item -Path $staging -Recurse -Force

Write-Step 'Done'
Write-Host "  Script Runtime : $scriptDir"
Write-Host "  Command Runtime: $commandDir"
Write-Host ''
Write-Host 'Both trees are gitignored. See resources/python/README.md for the runtime contract.'