# BlenderCustom: fetch pinned Windows libraries and compile a separate Blender build.
# Intended for Windows PowerShell 5.1+ with VS 2022 Build Tools.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File "D:\BlenderCustom\custom_tools\build_blender.ps1"
param([switch]$LibrariesOnly)
$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$libPath = Join-Path $root "lib\windows_x64"
$buildPath = Join-Path (Split-Path $root -Parent) "build_windows_x64_vc17_Release"

function Assert-NativeSuccess([string]$step) {
    if ($LASTEXITCODE -ne 0) {
        throw ("FAILED at " + $step + " (exit code: " + $LASTEXITCODE + "). Running this script again is safe.")
    }
}

if (-not (Test-Path (Join-Path $root ".git"))) { throw "Git checkout missing: $root" }
if (-not (Test-Path (Join-Path $root "make.bat"))) { throw "Blender make.bat missing: $root" }
if (-not (Get-Command "git.exe" -ErrorAction SilentlyContinue)) { throw "Git was not found on PATH." }

$vswhere = Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "Visual Studio Installer was not found." }
$vsPath = (& $vswhere -latest -products * -version "[17.0,18.0)" -requires "Microsoft.VisualStudio.Component.VC.Tools.x86.x64" -property installationPath | Select-Object -First 1)
if (-not $vsPath) { throw "Visual Studio 2022 with MSVC C++ tools was not found." }
# Verify the actual VS product patch version before any multi-gigabyte downloads.
# vswhere installationVersion (e.g. 17.14.36408.4) is NOT the patch-level product version.
# Avoid -format json | ConvertFrom-Json: Windows PowerShell 5.1 may corrupt localized output.
$installationName = (& $vswhere -latest -products * -version "[17.0,18.0)" -requires "Microsoft.VisualStudio.Component.VC.Tools.x86.x64" -property installationName | Select-Object -First 1)
if ($installationName -notmatch "^VisualStudio/(?<ver>\d+\.\d+\.\d+)\+") {
    throw ("Unrecognized Visual Studio installation name: " + $installationName)
}
$productVersion = $Matches["ver"]
if (-not $productVersion) { throw "Could not determine Visual Studio product version. Build not started." }
try { $parsedProductVersion = [version]$productVersion } catch { throw ("Unrecognized Visual Studio product version: " + $productVersion) }
Write-Host ("Visual Studio product version: " + $productVersion)
if ($parsedProductVersion -lt [version]"17.14.14") {
    throw ("VS2022 Build Tools " + $productVersion + " is unsupported. Update it to 17.14.14 or newer before building. The downloaded libraries remain cached.")
}
$cmakeExe = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (-not (Test-Path $cmakeExe)) { throw "Bundled Visual Studio CMake is missing: $cmakeExe" }
$env:PATH = ((Split-Path $cmakeExe -Parent) + ";" + $env:PATH)

$driveName = [IO.Path]::GetPathRoot($root).TrimEnd("\").TrimEnd(":")
$drive = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
if ($drive -and $drive.Free -lt 35GB) {
    throw ("Insufficient free disk space on " + $driveName + ": (less than 35 GiB). Free space before downloading/building.")
}

Write-Host "=== BlenderCustom dependencies ==="
Write-Host ("Source: " + $root)
Write-Host ("Libraries: " + $libPath)
Write-Host ("Build output: " + $buildPath)
Write-Host "Downloading may require multiple gigabytes of data. Do not interrupt Git LFS while it is working."

& git -C $root lfs version
Assert-NativeSuccess "Git LFS detection"
& git -C $root lfs install --skip-repo
Assert-NativeSuccess "Git LFS initialization"

# Do NOT use 'make update' here: the fork has an 'upstream' remote, and
# 'make update' can attempt to update the main source branch too.
# Blender's .gitmodules sets the library submodule update mode to 'none'.
# Override only in local .git/config, never modify committed source files.
& git -C $root config --local "submodule.lib/windows_x64.update" "checkout"
Assert-NativeSuccess "Enable Windows library submodule"

$previousSkipSmudge = [Environment]::GetEnvironmentVariable("GIT_LFS_SKIP_SMUDGE", "Process")
try {
    $env:GIT_LFS_SKIP_SMUDGE = "1"
    & git -C $root submodule update --init --progress -- "lib/windows_x64"
    Assert-NativeSuccess "Windows library submodule checkout"
}
finally {
    if ($null -eq $previousSkipSmudge) {
        Remove-Item Env:GIT_LFS_SKIP_SMUDGE -ErrorAction SilentlyContinue
    } else {
        $env:GIT_LFS_SKIP_SMUDGE = $previousSkipSmudge
    }
}

# Get large assets from Blender's own library repository, not the GitHub fork.
& git -C $libPath lfs pull
Assert-NativeSuccess "Windows library Git LFS download"

# The source checkout was initially cloned with GIT_LFS_SKIP_SMUDGE=1.
# Fetch only LFS assets for its current HEAD from the official upstream.
& git -C $root lfs fetch upstream HEAD
Assert-NativeSuccess "Source Git LFS fetch"
& git -C $root lfs checkout
Assert-NativeSuccess "Source Git LFS checkout"

Write-Host "=== Library download complete ==="
if ($LibrariesOnly) {
    Write-Host "Build was skipped because -LibrariesOnly was supplied."
    exit 0
}

Write-Host "=== Building BlenderCustom (Release / x64 / VS2022 Build Tools) ==="
Write-Host "This does not overwrite your installed Blender."
Push-Location $root
try {
    & cmd.exe /d /c "call make.bat 2022b"
    Assert-NativeSuccess "Blender compilation and install target"
}
finally {
    Pop-Location
}

$exe = Join-Path $buildPath "bin\Release\blender.exe"
if (Test-Path $exe) {
    Write-Host "BUILD SUCCESS"
    Write-Host ("Blender executable: " + $exe)
} else {
    Write-Warning "Build command succeeded, but blender.exe was not found in the expected location."
    Write-Host ("Check output folder: " + $buildPath)
}
