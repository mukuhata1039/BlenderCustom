# Install bundled DesignDoll Animation Export into already-built BlenderCustom.
# This copies only the Python add-on. No CMake or recompilation is needed.
# It does not change Blender user preferences or another Blender installation.
$ErrorActionPreference = "Stop"
$source = "D:\Blender\BlenderCustom\scripts\addons_core\design_doll_animation_export.py"
$buildRoot = "D:\Blender\Build"
$exe = Join-Path $buildRoot "bin\Release\blender.exe"

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw ("Addon source not found. Pull GitHub changes first: " + $source)
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw ("BlenderCustom executable not found: " + $exe)
}

# Ask THIS Blender binary where its addons_core lives. Do not guess its version.
Write-Host "Finding BlenderCustom's built-in add-on directory..."
$info = @(& $exe --background --factory-startup --python-expr 'import bpy; print("DDAX_PATHS=" + "|".join(bpy.utils.script_paths(subdir="addons_core")))' 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw ("BlenderCustom could not report its script paths: " + ($info | Out-String))
}
$pathLine = @($info | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^DDAX_PATHS=' } | Select-Object -First 1)
if ($pathLine.Count -ne 1) {
    throw ("No DDAX_PATHS line from BlenderCustom: " + ($info | Out-String))
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
    throw ("No built-in add-on directory under D:\Blender\Build. Blender reported: " + ($reported -join '; '))
}
Write-Host ("Installing: " + $destination)
Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
    throw "File verification failed."
}

# Non-persistent registration test: no user preference settings are saved.
Write-Host "Testing add-on registration in BlenderCustom..."
$test = @(& $exe --background --factory-startup --python-expr 'import bpy, addon_utils; addon_utils.modules_refresh(); addon_utils.enable("design_doll_animation_export", default_set=False); print("DDAX_REGISTER_OK=" + str(hasattr(bpy.types.Scene, "ddax_settings")))' 2>&1)
if (($LASTEXITCODE -ne 0) -or -not (@($test | ForEach-Object { [string]$_ }) -contains 'DDAX_REGISTER_OK=True')) {
    throw ("Addon was copied but registration test did not pass. Output: " + ($test | Out-String))
}
Write-Host "ADDON INSTALL SUCCESS"
Write-Host "In BlenderCustom: Edit > Preferences > Add-ons > enable 'DesignDoll Animation PNG Export'."
Write-Host "No Blender recompilation was done and no other Blender installation was modified."
