# Install bundled DesignDoll Animation PNG Export into already-built BlenderCustom.
# Only a Python add-on is copied; CMake and compilation are not run.
# Does not change saved preferences or other Blender installations.
# Compatible with Windows PowerShell 5.1 (no --python-expr quoting).
$ErrorActionPreference = "Stop"
$source = "D:\Blender\BlenderCustom\scripts\addons_core\design_doll_animation_export.py"
$buildRoot = "D:\Blender\Build"
$exe = Join-Path $buildRoot "bin\Release\blender.exe"

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw ("Addon source not found. Pull latest GitHub changes: " + $source)
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw ("BlenderCustom executable not found: " + $exe)
}

# Use temporary .py files instead of --python-expr, whose embedded double-quotes
# can be stripped by Windows PowerShell 5.1 when invoking a native executable.
# Start-Process also prevents normal Blender stderr from being misinterpreted as
# a terminating NativeCommandError by PowerShell 5.1.
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("BlenderDDAX_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir -ErrorAction Stop | Out-Null
function Invoke-BlenderPython([string]$name, [string]$code) {
    $scriptPath = Join-Path $tempDir ($name + ".py")
    $stdoutPath = Join-Path $tempDir ($name + ".out")
    $stderrPath = Join-Path $tempDir ($name + ".err")
    [System.IO.File]::WriteAllText($scriptPath, $code, ([System.Text.UTF8Encoding]::new($false)))
    $procArgs = @{
        FilePath = $exe
        ArgumentList = @("--background", "--factory-startup", "--python", ('"' + $scriptPath + '"'))
        NoNewWindow = $true
        Wait = $true
        PassThru = $true
        RedirectStandardOutput = $stdoutPath
        RedirectStandardError = $stderrPath
        ErrorAction = "Stop"
    }
    $proc = Start-Process @procArgs
    $standardOutput = [System.IO.File]::ReadAllText($stdoutPath)
    $standardError = [System.IO.File]::ReadAllText($stderrPath)
    if ($proc.ExitCode -ne 0) {
        throw ("BlenderCustom Python test " + $name + " failed with exit code " +
            $proc.ExitCode + [Environment]::NewLine + $standardOutput +
            [Environment]::NewLine + $standardError)
    }
    return $standardOutput
}

try {
    Write-Host "Finding BlenderCustom's built-in add-on directory..."
    $probeCode = @'
import bpy
print("DDAX_PATHS=" + "|".join(bpy.utils.script_paths(subdir="addons_core")))
'@
    $info = Invoke-BlenderPython "probe_addon_paths" $probeCode
    $pathLine = @($info -split '\r?\n' | Where-Object { $_ -match '^DDAX_PATHS=' } | Select-Object -First 1)
    if ($pathLine.Count -ne 1) {
        throw ("No DDAX_PATHS line from BlenderCustom: " + $info)
    }
    $reported = ($pathLine[0] -replace '^DDAX_PATHS=', '') -split '\|'
    $buildPrefix = $buildRoot.TrimEnd('\') + '\'
    $destination = $null
    foreach ($candidate in $reported) {
        $normalized = $candidate.Trim().Replace('/', '\')
        if ($normalized.StartsWith($buildPrefix, [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $normalized -PathType Container)) {
            $destination = Join-Path $normalized "design_doll_animation_export.py"
            break
        }
    }
    if (-not $destination) {
        throw ("Could not find BlenderCustom built-in addons_core under D:\Blender\Build. Reported: " +
            ($reported -join '; '))
    }

    Write-Host ("Installing: " + $destination)
    Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
        throw "Addon file verification failed."
    }

    Write-Host "Testing add-on registration in BlenderCustom..."
    $testCode = @'
import bpy
import addon_utils
addon_utils.modules_refresh()
addon_utils.enable("design_doll_animation_export", default_set=False)
print("DDAX_REGISTER_OK=" + str(hasattr(bpy.types.Scene, "ddax_settings")))
'@
    $test = Invoke-BlenderPython "test_addon_registration" $testCode
    if (-not (@($test -split '\r?\n') -contains 'DDAX_REGISTER_OK=True')) {
        throw ("Addon copied but Blender did not register it. Test output: " + $test)
    }
    Write-Host "ADDON INSTALL SUCCESS"
    Write-Host "BlenderCustom: Edit > Preferences > Add-ons > enable 'DesignDoll Animation PNG Export'."
    Write-Host "No recompilation and no changes to another Blender installation."
}
finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
