# BlenderCustom - Windows build environment setup/check
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File "D:\BlenderCustom\custom_tools\prepare_build_environment.ps1"
$ErrorActionPreference = "Stop"

Write-Host "=== BlenderCustom build environment ==="

$pf86 = [Environment]::GetFolderPath("ProgramFilesX86")
$vswhere = Join-Path $pf86 "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "Visual Studio installer (vswhere.exe) not found." }

$vsArgs = @("-latest", "-products", "*", "-version", "[17.0,18.0)")
$vsPath = (& $vswhere @vsArgs -property installationPath | Select-Object -First 1)
$vsVersion = (& $vswhere @vsArgs -property installationVersion | Select-Object -First 1)
# Use the ASCII-only installationName to avoid Windows PowerShell 5.1 JSON encoding issues.
$installationName = (& $vswhere @vsArgs -property installationName | Select-Object -First 1)
if ($installationName -notmatch "^VisualStudio/(?<ver>\d+\.\d+\.\d+)\+") {
    throw ("Unrecognized Visual Studio installation name: " + $installationName)
}
$vsDisplayVersion = $Matches["ver"]
if (-not $vsPath) { throw "Visual Studio 2022 not found." }
Write-Host ("Visual Studio 2022: " + $vsPath)
Write-Host ("Visual Studio installation version: " + $vsVersion)
Write-Host ("Visual Studio PRODUCT version: " + $vsDisplayVersion)
Write-Host "Blender requires VS2022 product version >= 17.14.14 (MSVC compiler >= 19.44.35216)."
# Installation version is NOT the product version; the old check used the wrong one.

$vcPath = (& $vswhere @vsArgs -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
$vcInstalled = (-not [string]::IsNullOrWhiteSpace($vcPath)) -and (Test-Path (Join-Path $vsPath "VC\Tools\MSVC"))
if ($vcInstalled) {
    Write-Host "MSVC C++ compiler: OK"
} else {
    Write-Warning "MSVC C++ compiler not detected. In Visual Studio Installer, modify Build Tools 2022 and add Desktop development with C++."
}

$sdkRoot = Join-Path $pf86 "Windows Kits\10\Lib"
$sdkVersions = if (Test-Path $sdkRoot) { @(Get-ChildItem $sdkRoot -Directory -ErrorAction SilentlyContinue) } else { @() }
$sdkInstalled = $sdkVersions.Count -gt 0
if ($sdkInstalled) {
    Write-Host ("Windows SDK: " + (($sdkVersions | Sort-Object Name -Descending | Select-Object -First 1).Name))
} else {
    Write-Warning "Windows SDK not detected. Install it using the Visual Studio C++ workload."
}

$cmakeCommand = Get-Command cmake.exe -ErrorAction SilentlyContinue
$vsCmake = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
$standaloneCmake = Join-Path $env:ProgramFiles "CMake\bin\cmake.exe"

if ($cmakeCommand) {
    $cmakeExe = $cmakeCommand.Source
} elseif (Test-Path $vsCmake) {
    $cmakeExe = $vsCmake
    Write-Host "Using CMake bundled with Visual Studio (not on PATH)."
} elseif (Test-Path $standaloneCmake) {
    $cmakeExe = $standaloneCmake
} else {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { throw "CMake missing and winget is unavailable. Install Kitware CMake." }
    Write-Host "CMake missing. Installing Kitware CMake using winget..."
    & $winget.Source install --id Kitware.CMake --exact --source winget --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw ("CMake install failed: " + $LASTEXITCODE) }
    if (-not (Test-Path $standaloneCmake)) {
        throw "CMake installer finished, but cmake.exe is not at its default path. Restart the terminal and check installation."
    }
    $cmakeExe = $standaloneCmake
}

Write-Host ("CMake: " + $cmakeExe)
& $cmakeExe --version | Select-Object -First 1

$ready = $vcInstalled -and $sdkInstalled
if (-not $vsDisplayVersion) {
    $ready = $false
    Write-Warning "Unable to determine Visual Studio product version; do not assume build readiness."
} else {
    try {
        if ([version]$vsDisplayVersion -lt [version]"17.14.14") {
            $ready = $false
            Write-Warning ("Visual Studio product version " + $vsDisplayVersion + " is too old. Update VS2022 Build Tools to 17.14.14 or newer.")
        }
    } catch {
        $ready = $false
        Write-Warning ("Could not parse Visual Studio PRODUCT version: " + $vsDisplayVersion)
    }
}

if ($ready) {
    Write-Host "RESULT: READY for the next Blender library-download/build step."
} else {
    Write-Host "RESULT: Visual Studio C++ components or update need attention before building."
}
Write-Host "This script has not modified the Blender source or existing installed Blender."
