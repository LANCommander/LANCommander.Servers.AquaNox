#Requires -Modules Logging
#Requires -Modules Hooks
#Requires -Modules OverlayFS

# AquaNox is retail software with no public download. Use an existing v1.18 install in
# /config/Server, or set AQUANOX_ARCHIVE_URL to a zip of the game folder (Aqua.exe at the zip root,
# or in a single top-level folder), e.g. a LANCommander archive. The intro movies (vfx/mov/) are
# not needed by a server and are left out of the extracted copy.

Invoke-Hook "PreInstallAquaNox"

$exe = Join-Path $Env:SERVER_DIR 'Aqua.exe'

if (Test-Path -Path $exe) {
    Write-Log "AquaNox found in $Env:SERVER_DIR"
} elseif ($Env:AQUANOX_ARCHIVE_URL) {
    Write-Log "Downloading AquaNox from $Env:AQUANOX_ARCHIVE_URL"

    $zip     = '/tmp/aquanox.zip'
    $extract = '/tmp/aquanox'

    curl -fL --retry 3 --output $zip "$Env:AQUANOX_ARCHIVE_URL"
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Env:AQUANOX_ARCHIVE_URL" }

    Remove-Item -Recurse -Force -Path $extract -ErrorAction SilentlyContinue
    unzip -q -o $zip -d $extract -x '*vfx/mov/*'
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $zip" }

    # Accept the game at the zip root or inside one top-level folder
    $root = Get-ChildItem -Path $extract -Filter 'Aqua.exe' -Recurse -File -Depth 1 |
        Select-Object -First 1 -ExpandProperty DirectoryName
    if (-not $root) { throw "Aqua.exe not found in $Env:AQUANOX_ARCHIVE_URL" }

    New-Item -ItemType Directory -Path $Env:SERVER_DIR -Force | Out-Null
    Move-Item -Force -Path (Join-Path $root '*') -Destination $Env:SERVER_DIR
    chown -R "$($Env:UID):$($Env:GID)" $Env:SERVER_DIR

    Remove-Item -Recurse -Force -Path $zip, $extract

    # The overlay was mounted before Server/ was populated, and overlayfs doesn't reliably show
    # lower-dir changes made while mounted.
    mountpoint -q $Env:SERVER_ROOT
    if ($LASTEXITCODE -eq 0) {
        umount $Env:SERVER_ROOT
        Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue
        Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $Env:SERVER_DIR -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
        Write-Log "OverlayFS remounted"
    }

    Write-Log "AquaNox installed"
} else {
    Write-Log -Level Error "Aqua.exe not found in $Env:SERVER_DIR. Copy an AquaNox v1.18 install there or set AQUANOX_ARCHIVE_URL."
}

Invoke-Hook "PostInstallAquaNox"

Set-Location $Env:SERVER_ROOT
