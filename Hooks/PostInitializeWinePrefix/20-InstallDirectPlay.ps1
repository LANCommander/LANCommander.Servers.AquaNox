#Requires -Modules Logging
#Requires -Modules Hooks

# AquaNox hosts with DirectPlay 8. Wine's builtin dpnet stubs out IDirectPlay8Server::Host, so the
# server never opens its game port; install Microsoft's DirectPlay DLLs into the prefix. The
# redist is cached in the image ($Env:W_CACHE), so this needs no download.

$prefix = $Env:WINEPREFIX
$runAs  = "$($Env:UID):$($Env:GID)"
$marker = Join-Path $prefix '.lancommander-directplay'

if (-not (Test-Path -Path $marker)) {
    Write-Log "Installing native DirectPlay into the Wine prefix"

    & gosu $runAs env "W_CACHE=$Env:W_CACHE" winetricks -q directplay
    $exitCode = $LASTEXITCODE
    & gosu $runAs wineserver --wait

    if ($exitCode -ne 0) {
        throw "winetricks directplay failed with exit code $exitCode"
    }

    New-Item -ItemType File -Path $marker -Force | Out-Null
    chown $runAs $marker

    Write-Log "Native DirectPlay installed"
} else {
    Write-Log "Native DirectPlay already installed"
}
