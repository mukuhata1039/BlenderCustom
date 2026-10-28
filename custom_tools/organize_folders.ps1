# Organize an already built BlenderCustom checkout without invalidating CMake paths.
# Windows PowerShell 5.1 / NTFS / D: only.
#
# BEFORE RUNNING: close custom Blender, Visual Studio, build shells and Explorer
# windows whose current directory is inside the old folders.
#
# Physical directories after migration:
#   D:\Blender\BlenderCustom   <- source + Git
#   D:\Blender\Build           <- existing compiled build
#
# Backward-compatible NTFS junctions retained for CMake/Visual Studio:
#   D:\BlenderCustom -> D:\Blender\BlenderCustom
#   D:\build_windows_x64_vc17_Release -> D:\Blender\Build
#
# This script does NOT delete any source files, build files or library downloads.
$ErrorActionPreference = "Stop"

$parent = "D:\Blender"
$oldSource = "D:\BlenderCustom"
$newSource = "D:\Blender\BlenderCustom"
$oldBuild = "D:\build_windows_x64_vc17_Release"
$newBuild = "D:\Blender\Build"

function Get-Entry([string]$path) {
    Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}
function Assert-DirectoryHas([string]$path, [string]$relative) {
    if (-not (Test-Path -LiteralPath (Join-Path $path $relative))) {
        throw ("Missing " + $relative + " in " + $path + ". Nothing will be overwritten.")
    }
}
function Assert-ExpectedJunction([string]$old, [string]$new) {
    $entry = Get-Entry $old
    if (-not $entry -or $entry.LinkType -ne "Junction") {
        throw ("Expected an NTFS junction at: " + $old)
    }
    $target = @($entry.Target)[0]
    if ([string]::IsNullOrWhiteSpace($target)) {
        throw ("Cannot read junction target: " + $old)
    }
    if ($target.TrimEnd('\') -ine $new.TrimEnd('\')) {
        throw ("Unexpected junction target for " + $old + ": " + $target)
    }
    if (-not (Test-Path -LiteralPath $old -PathType Container)) {
        throw ("Junction target is not accessible: " + $old)
    }
}
function Move-And-Link([string]$old, [string]$new, [string]$required) {
    $oldEntry = Get-Entry $old
    $newEntry = Get-Entry $new

    if ($oldEntry -and $oldEntry.LinkType -eq "Junction") {
        Assert-ExpectedJunction $old $new
        Assert-DirectoryHas $new $required
        Write-Host ("Already organized: " + $new)
        return
    }

    if ($oldEntry -and ($oldEntry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw ("Refusing to move unexpected reparse point: " + $old)
    }

    if ($oldEntry -and $newEntry) {
        throw ("Both source and target exist. Refusing to merge or overwrite: " + $old + " and " + $new)
    }

    if (-not $oldEntry -and -not $newEntry) {
        throw ("Neither the old nor the new directory exists: " + $old)
    }

    if ($oldEntry) {
        Assert-DirectoryHas $old $required
        Write-Host ("Moving " + $old + " -> " + $new)
        # Same NTFS volume: Windows moves the existing directory, not its contents
        # through a new download or re-compilation.
        Move-Item -LiteralPath $old -Destination $new -ErrorAction Stop
    } else {
        # Recover safely if the previous attempt moved the folder but was
        # interrupted before the junction was created.
        Assert-DirectoryHas $new $required
        Write-Host ("Resuming migration: destination already exists at " + $new)
    }

    try {
        Write-Host ("Creating compatibility junction: " + $old + " -> " + $new)
        New-Item -ItemType Junction -Path $old -Target $new -ErrorAction Stop | Out-Null
        Assert-ExpectedJunction $old $new
    } catch {
        Write-Warning ("Could not create junction for " + $old + ". The files are preserved in " + $new)
        throw
    }
}

Write-Host "=== BlenderCustom folder organization ==="
Write-Host "WARNING: close BlenderCustom and any active build process before continuing."

$driveFormat = ([System.IO.DriveInfo]::new("D:\")).DriveFormat
if ($driveFormat -ne "NTFS") { throw ("D: must use NTFS for this migration. Detected: " + $driveFormat) }
if ((Get-Location).Path -like "D:\BlenderCustom*" -or (Get-Location).Path -like "D:\build_windows_x64_vc17_Release*") {
    throw "Current PowerShell directory is inside a folder being moved. Open PowerShell from another directory."
}

# Do not move directories while a custom Blender or an active compiler is running.
$running = @(Get-CimInstance Win32_Process -Filter "Name = 'blender.exe' OR Name = 'MSBuild.exe' OR Name = 'cmake.exe' OR Name = 'cl.exe' OR Name = 'link.exe'" -ErrorAction Stop)
foreach ($proc in $running) {
    $exe = [string]$proc.ExecutablePath
    $cmd = [string]$proc.CommandLine
    $customExe = (($exe -like "$oldBuild\*") -or ($exe -like "$newBuild\*"))
    $activeBuild = ($proc.Name -ne "blender.exe" -and (($cmd -like "*D:\BlenderCustom*") -or ($cmd -like "*D:\build_windows_x64_vc17_Release*") -or ($cmd -like "*D:\Blender\Build*")))
    if ($customExe -or $activeBuild) {
        throw ("Close this program before moving build files: " + $proc.Name + " (PID " + $proc.ProcessId + ")")
    }
}

$oldSourceEntry = Get-Entry $oldSource
$newSourceEntry = Get-Entry $newSource
$oldBuildEntry = Get-Entry $oldBuild
$newBuildEntry = Get-Entry $newBuild
if ($oldSourceEntry -and $newSourceEntry -and $oldSourceEntry.LinkType -ne "Junction") {
    throw "The new source folder already exists, refusing to overwrite anything."
}
if ($oldBuildEntry -and $newBuildEntry -and $oldBuildEntry.LinkType -ne "Junction") {
    throw "The new build folder already exists, refusing to overwrite anything."
}
if (-not $oldSourceEntry -and -not $newSourceEntry) { throw "Source folder not found." }
if (-not $oldBuildEntry -and -not $newBuildEntry) { throw "Build folder not found." }

$sourceToCheck = if ($oldSourceEntry -and $oldSourceEntry.LinkType -ne "Junction") { $oldSource } else { $newSource }
$buildToCheck = if ($oldBuildEntry -and $oldBuildEntry.LinkType -ne "Junction") { $oldBuild } else { $newBuild }
Assert-DirectoryHas $sourceToCheck ".git"
Assert-DirectoryHas $sourceToCheck "make.bat"
Assert-DirectoryHas $buildToCheck "CMakeCache.txt"
Assert-DirectoryHas $buildToCheck "Blender.sln"
Assert-DirectoryHas $buildToCheck "bin\Release\blender.exe"

# Validate the configuration belongs to this exact source checkout and build.
$cacheHome = Get-Content -LiteralPath (Join-Path $buildToCheck "CMakeCache.txt") |
    Where-Object { $_ -match '^CMAKE_HOME_DIRECTORY:INTERNAL=' } | Select-Object -First 1
$expectedHome = ($oldSource -replace '\\', '/').TrimEnd('/')
if (-not $cacheHome) { throw "CMAKE_HOME_DIRECTORY missing from CMakeCache.txt." }
$actualHome = ((($cacheHome -split '=', 2)[1]) -replace '\\', '/').TrimEnd('/')
if ($actualHome -ine $expectedHome) {
    throw ("Build cache points at a different source checkout: " + $actualHome)
}

if (-not (Get-Entry $parent)) { New-Item -ItemType Directory -Path $parent -ErrorAction Stop | Out-Null }
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw ("Not a directory: " + $parent) }

# Source first; keep original location accessible immediately via its junction.
Move-And-Link $oldSource $newSource ".git"
Move-And-Link $oldBuild $newBuild "CMakeCache.txt"

Write-Host "=== Validating Git, CMake and Blender executable ==="
Assert-ExpectedJunction $oldSource $newSource
Assert-ExpectedJunction $oldBuild $newBuild

& git -C $oldSource rev-parse --is-inside-work-tree
if ($LASTEXITCODE -ne 0) { throw "Git could not open the old-path junction." }
& git -C $newSource rev-parse --is-inside-work-tree
if ($LASTEXITCODE -ne 0) { throw "Git could not open the organized source folder." }

Assert-DirectoryHas $newBuild "bin\Release\blender.exe"
Write-Host "ORGANIZATION SUCCESS"
Write-Host ("Source: " + $newSource)
Write-Host ("Build: " + $newBuild)
Write-Host ("Executable: " + (Join-Path $newBuild "bin\Release\blender.exe"))
Write-Host "Keep both compatibility junctions in D:\; existing CMake incremental builds reference them."
Write-Host "The original source and build were moved, not copied or rebuilt."
