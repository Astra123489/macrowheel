<#
.SYNOPSIS
    Configures the Macro Wheel Menu CMake build.

.DESCRIPTION
    Shared by .github/workflows/build.yml and .github/workflows/release.yml so
    the two jobs cannot drift apart.

    Two things are resolved here that a plain `cmake -G ...` invocation gets
    wrong on a hosted runner:

    1. Qt location.

       install-qt-action exports QT_ROOT_DIR, and Qt6_DIR when it installs Qt 6.
       Either is a valid CMAKE_PREFIX_PATH. Neither is guaranteed, and an unset
       variable expands to an empty string in PowerShell, so the previous
       `-DCMAKE_PREFIX_PATH="$env:Qt6_DIR"` silently configured against nothing
       and failed later with "Could not find a package configuration file
       provided by Qt6". Both names are tried here, and a missing Qt fails
       immediately with a message naming the cause.

    2. Generator.

       "Visual Studio 17 2022" was pinned by name because that is the toolset
       this project is developed against. A runner image that ships only a
       newer Visual Studio does not have that generator at all and CMake aborts
       with "Could not create named generator Visual Studio 17 2022". The
       generator is therefore pinned only when a 17.x Visual Studio is actually
       installed; otherwise CMake selects the newest one it can find.

.PARAMETER Version
    Package version. When supplied, it is forwarded as CPACK_PACKAGE_VERSION
    and CPACK_PACKAGE_FILE_NAME so a tagged build is not stuck on the
    hardcoded project version.

.PARAMETER BuildDirectory
    Build directory, relative to the menu project. Default: build

.EXAMPLE
    ./menu/tools/configure-menu.ps1

.EXAMPLE
    ./menu/tools/configure-menu.ps1 -Version 0.1.0
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$BuildDirectory = 'build'
)

$ErrorActionPreference = 'Stop'

function Get-QtPrefix {
    # QT_ROOT_DIR is the installation root; Qt6_DIR is <root>/lib/cmake/Qt6.
    # Either works as CMAKE_PREFIX_PATH, so prefer whichever is set and real.
    foreach ($name in @('QT_ROOT_DIR', 'Qt6_DIR')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value -and (Test-Path -LiteralPath $value)) {
            return $value
        }
    }
    return $null
}

function Test-VisualStudio2022 {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        return $false
    }
    $found = & $vswhere -version '[17.0,18.0)' -property installationPath 2>$null
    return [bool]$found
}

$sourceDir = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath $sourceDir)) {
    throw "Menu source directory not found: $sourceDir"
}

$qtPrefix = Get-QtPrefix
if (-not $qtPrefix) {
    throw ("Qt location not found. Neither QT_ROOT_DIR nor Qt6_DIR points at an " +
           "existing directory. The 'Install Qt' step must run before this script.")
}

Write-Host "CMake version : $((cmake --version | Select-Object -First 1))"
Write-Host "Qt prefix     : $qtPrefix"
Write-Host "Source dir    : $sourceDir"
Write-Host "Build dir     : $BuildDirectory"

$arguments = @(
    '-S', '.',
    '-B', $BuildDirectory,
    '-DCMAKE_PREFIX_PATH=' + $qtPrefix
)

if (Test-VisualStudio2022) {
    Write-Host 'Generator     : Visual Studio 17 2022 (pinned)'
    $arguments += @('-G', 'Visual Studio 17 2022', '-A', 'x64')
} else {
    Write-Host 'Generator     : CMake default (no 17.x Visual Studio present)'
}

if ($Version) {
    Write-Host "Package version: $Version"
    $arguments += "-DCPACK_PACKAGE_VERSION=$Version"
    $arguments += "-DCPACK_PACKAGE_FILE_NAME=MacroWheelMenu-$Version-windows-x64"
}

# CMake writes progress and warnings to stderr. With $ErrorActionPreference set
# to Stop, Windows PowerShell treats native stderr output as a terminating
# error and aborts the script even when CMake itself succeeded, which is what
# the warning at the end of a normal configure run would do. The preference is
# relaxed for the duration of the call and the exit code is checked instead.
Push-Location $sourceDir
try {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & cmake @arguments
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -ne 0) {
        throw "cmake configure failed with exit code $exitCode."
    }
} finally {
    Pop-Location
}

Write-Host 'Configuration complete.'