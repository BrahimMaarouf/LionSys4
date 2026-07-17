$ErrorActionPreference = "Stop"

$required = @(
    "assets/blender/M2_DesertAssetSlice.blend",
    "assets/export/WindBoulder.glb",
    "assets/export/LayeredMesa.glb",
    "assets/export/DryShrub.glb",
    "assets/M2_DCC_VALIDATION.json",
    "src/ServerStorage/WorldEngine/Assets/Rocks/Templates.rbxm"
)

foreach ($path in $required) {
    git ls-files --error-unmatch -- $path | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Required Milestone 2 source artifact is not tracked: $path"
    }
}

$expectedHashes = @{
    "assets/M2_DCC_VALIDATION.json" = "14060c97fee07457a255ad8ec3e58678c06d9a5af5fdc2caa5d69d08cfd87619"
    "assets/blender/M2_DesertAssetSlice.blend" = "6d5db5c6500875ef2ae1ce53de9c22f7e38e7f7a907bfcd67c9bf293f6f351c2"
    "src/ServerStorage/WorldEngine/Assets/Rocks/Templates.rbxm" = "0c8fe1aa8663bf0fa6895db9875f0f8b150e7c7ce76b51fd09e16155e222450d"
}

foreach ($entry in $expectedHashes.GetEnumerator()) {
    $actual = (Get-FileHash $entry.Key -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $entry.Value) {
        throw "Hash mismatch for $($entry.Key): expected $($entry.Value), got $actual"
    }
}

Write-Output "Milestone 2 source artifacts are tracked and match the pinned SHA-256 manifest."
