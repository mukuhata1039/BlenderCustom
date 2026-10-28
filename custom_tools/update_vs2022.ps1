# Update only the installed VS 2022 Build Tools instance to the newest available 17.14.x servicing release.
# Blender source/libraries are unaffected.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File "D:\BlenderCustom\custom_tools\update_vs2022.ps1"
$ErrorActionPreference = "Stop"

$pf86 = [Environment]::GetFolderPath("ProgramFilesX86")
$setup = Join-Path $pf86 "Microsoft Visual Studio\Installer\setup.exe"
$buildToolsPath = Join-Path $pf86 "Microsoft Visual Studio\2022\BuildTools"
$vswhere = Join-Path $pf86 "Microsoft Visual Studio\Installer\vswhere.exe"

if (-not (Test-Path $setup)) { throw "Visual Studio Installer setup.exe not found: $setup" }
if (-not (Test-Path $buildToolsPath)) { throw "Visual Studio 2022 Build Tools not found: $buildToolsPath" }
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found: $vswhere" }

Write-Host "=== Update Visual Studio 2022 Build Tools ==="
Write-Host ("Target: " + $buildToolsPath)
Write-Host "This updates Visual Studio Build Tools only; installed Blender and Blender source are not changed."
Write-Host "Windows may ask for administrator permission. Updating may require a restart."

# setup.exe is the Microsoft-documented updater. Run it elevated from a different working directory.
$arguments = 'update --passive --norestart --installPath "' + $buildToolsPath + '"'
$process = Start-Process -FilePath $setup -ArgumentList $arguments -WorkingDirectory $env:SystemRoot -Verb RunAs -Wait -PassThru
if ($process.ExitCode -eq 3010) {
    Write-Warning "Visual Studio updated; Windows restart is required before building Blender."
} elseif ($process.ExitCode -ne 0) {
    throw ("Visual Studio Installer exited with code " + $process.ExitCode)
}

$vs = & $vswhere -latest -products * -version "[17.0,18.0)" -format json -utf8 | ConvertFrom-Json
$versionText = @($vs)[0].catalog.productDisplayVersion
Write-Host ("Detected VS2022 product version: " + $versionText)

if (-not $versionText) {
    Write-Warning "Unable to read installed VS version. Run the build environment check before building."
    exit 0
}
try { $version = [version]$versionText } catch { throw ("Cannot parse product version: " + $versionText) }
if ($version -lt [version]"17.14.14") {
    Write-Warning "Build Tools is still older than Blender's minimum 17.14.14. Check the Visual Studio Installer update channel."
} elseif ($process.ExitCode -ne 3010) {
    Write-Host "UPDATE SUCCESS: VS2022 meets Blender's minimum product version."
}
