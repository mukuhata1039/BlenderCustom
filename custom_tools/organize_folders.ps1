# Move BlenderCustom and its build into D:\Blender without leaving junctions.
# Run only AFTER closing BlenderCustom and build/compiler processes.
# This is a same-volume move: it does not download libraries or discard compiled output.
# The existing CMake configuration must be regenerated after paths change.
# PowerShell 5.1, NTFS.
$ErrorActionPreference = "Stop"

$oldSource = "D:\BlenderCustom"
$oldBuild = "D:\build_windows_x64_vc17_Release"
$parent = "D:\Blender"
$newSource = "D:\Blender\BlenderCustom"
$newBuild = "D:\Blender\Build"

function Entry([string]$path) {
    Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}
function Require-File([string]$dir, [string]$relative) {
    if (-not (Test-Path -LiteralPath (Join-Path $dir $relative))) {
        throw ("Required file missing: " + (Join-Path $dir $relative))
    }
}
function Check-MigrationPair([string]$old, [string]$new, [string]$required) {
    $o = Entry $old
    $n = Entry $new
    if ($o -and ($o.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw ("A link already exists at " + $old + ". Stop; do not delete links manually.")
    }
    if ($n -and ($n.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw ("Unexpected target link: " + $new)
    }
    if ($o -and $n) { throw ("Both paths already exist; refusing to merge: " + $old + " and " + $new) }
    if (-not $o -and -not $n) { throw ("Neither path exists: " + $old + " or " + $new) }
    $existing = if ($o) { $old } else { $new }
    Require-File $existing $required
}
function Move-If-Needed([string]$old, [string]$new) {
    if (Entry $old) {
        Write-Host ("Moving " + $old + " -> " + $new)
        Move-Item -LiteralPath $old -Destination $new -ErrorAction Stop
    } else {
        Write-Host ("Already moved: " + $new)
    }
}

Write-Host "=== BlenderCustom clean folder organization ==="
Write-Host "Final locations:"
Write-Host ("  " + $newSource)
Write-Host ("  " + $newBuild)
Write-Host "No junctions or old-path folders will be created."

if (([System.IO.DriveInfo]::new("D:\")).DriveFormat -ne "NTFS") {
    throw "D: must be NTFS."
}
$current = (Get-Location).Path
foreach ($p in @($oldSource,$oldBuild,$newSource,$newBuild)) {
    if ($current -ieq $p -or $current.StartsWith($p.TrimEnd("\") + "\", [StringComparison]::OrdinalIgnoreCase)) {
        throw ("PowerShell's current directory is in a folder being moved: " + $current + ". Run from C:\Windows\system32.")
    }
}

# Do not relocate folders while BlenderCustom or a compiler is accessing them.
$running = @(Get-CimInstance Win32_Process -Filter "Name = 'blender.exe' OR Name = 'MSBuild.exe' OR Name = 'cmake.exe' OR Name = 'cl.exe' OR Name = 'link.exe'")
foreach ($proc in $running) {
    $exe = [string]$proc.ExecutablePath
    $cmd = [string]$proc.CommandLine
    $usesCustomBlender = (($proc.Name -ieq "blender.exe") -and
        ($exe.StartsWith($oldBuild + "\", [StringComparison]::OrdinalIgnoreCase) -or
         $exe.StartsWith($newBuild + "\", [StringComparison]::OrdinalIgnoreCase)))
    $usesCustomBuild = ($proc.Name -ine "blender.exe" -and (
        $cmd.Contains($oldSource) -or $cmd.Contains($oldBuild) -or
        $cmd.Contains($newSource) -or $cmd.Contains($newBuild)))
    if ($usesCustomBlender -or $usesCustomBuild) {
        throw ("Close " + $proc.Name + " (PID " + $proc.ProcessId + ") before migration.")
    }
}

Check-MigrationPair $oldSource $newSource "make.bat"
Check-MigrationPair $oldBuild $newBuild "bin\Release\blender.exe"
$srcToValidate = if (Entry $oldSource) { $oldSource } else { $newSource }
Require-File $srcToValidate ".git"
$buildToValidate = if (Entry $oldBuild) { $oldBuild } else { $newBuild }
Require-File $buildToValidate "CMakeCache.txt"

# Make sure that this build belongs to this exact fork and not another project.
$cacheFile = Join-Path $buildToValidate "CMakeCache.txt"
$cmakeHomeLine = Get-Content -LiteralPath $cacheFile |
    Where-Object { $_ -match '^CMAKE_HOME_DIRECTORY:INTERNAL=' } |
    Select-Object -First 1
if (-not $cmakeHomeLine) { throw "CMake cache has no source identification. Nothing moved." }
$cachedSource = (($cmakeHomeLine -split '=',2)[1] -replace '\\','/').TrimEnd('/')
$expectedSources = @($oldSource,$newSource) | ForEach-Object { ($_ -replace '\\','/').TrimEnd('/') }
if ($cachedSource -notin $expectedSources) {
    throw ("CMake build belongs to another source: " + $cachedSource)
}

if (-not (Entry $parent)) {
    New-Item -ItemType Directory -Path $parent -ErrorAction Stop | Out-Null
}
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    throw ("Not a directory: " + $parent)
}

# Same NTFS drive: this moves directory records, not copies multi-GB content.
# It can resume when one move succeeded and the other didn't.
Move-If-Needed $oldBuild $newBuild
Move-If-Needed $oldSource $newSource

Require-File $newSource ".git"
Require-File $newBuild "bin\Release\blender.exe"
& git -C $newSource rev-parse --is-inside-work-tree
if ($LASTEXITCODE -ne 0) { throw "Git checkout did not survive the move." }

# CMake stores absolute paths in its configuration. Clear only generated
# configuration files, not libraries, objects, executables or source code.
$cache = Join-Path $newBuild "CMakeCache.txt"
$cmakeFiles = Join-Path $newBuild "CMakeFiles"
$solution = Join-Path $newBuild "Blender.sln"
if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Force }
if (Test-Path -LiteralPath $cmakeFiles) { Remove-Item -LiteralPath $cmakeFiles -Recurse -Force }
if (Test-Path -LiteralPath $solution) { Remove-Item -LiteralPath $solution -Force }

if ((Entry $oldSource) -or (Entry $oldBuild)) {
    throw "Unexpected old-path entry still exists. No cleanup was attempted."
}

Write-Host "ORGANIZATION SUCCESS"
Write-Host ("Source: " + $newSource)
Write-Host ("Build: " + $newBuild)
Write-Host ("Existing Blender executable: " + (Join-Path $newBuild "bin\Release\blender.exe"))
Write-Host "Old top-level folders: absent. No junctions created."
Write-Host "IMPORTANT: CMake configuration will be regenerated on the next build."
Write-Host "This may trigger significant recompilation because both paths changed."
