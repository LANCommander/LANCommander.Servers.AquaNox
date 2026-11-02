#Requires -Modules Logging

# AquaNox's dedicated mode (`Aqua.exe -host`) skips creating the display and the 2D sound system,
# but the start-up code that follows uses both without checking: first `display->...` while
# creating the network (page fault writing 0x00006DB0 at 0x0050D004), then the sound singleton while
# creating the movie player (read of 0x00000000 at 0x0041EAED). It only ever worked where the null
# page is mapped (Windows 9x).
#
# This patches a copy of Aqua.exe so -host creates both like a normal start: the two
# `if (-host) skip` branches become unconditional jumps into the create path. The display then
# needs a D3D8 device, which Wine provides on Xvfb; its mode must match the Xvfb screen (see the
# configure hook). The copy is written through the merged view, so it lands in Overlay/ and Server/
# keeps the original. Only the known v1.18 Aqua.exe is patched; anything else is left alone.

$exe = Join-Path $Env:SERVER_ROOT 'Aqua.exe'

$originalHash = 'EE061C4FC0176225AA664FFD663F6364CBB86C9E174A739EE6391E6390721639'
$patchedHash  = '9EEDD8D0A2E036D367168A9B9571365629B69F08028F459ACC0C6164A3670393'

if ($Env:AQUANOX_PATCH_EXE -in @('false', '0', 'no')) {
    Write-Log "AQUANOX_PATCH_EXE is off; not patching Aqua.exe"
    return
}

if (-not (Test-Path -Path $exe)) {
    Write-Log -Level Error "$exe not found; skipping Aqua.exe patch"
    return
}

$hash = (Get-FileHash -Path $exe -Algorithm SHA256).Hash

if ($hash -eq $patchedHash) {
    Write-Log "Aqua.exe is already patched for dedicated servers"
    return
}

if ($hash -ne $originalHash) {
    Write-Log -Level Warning "Unknown Aqua.exe (sha256 $hash); not patching it. Aqua.exe -host may crash on start."
    return
}

$bytes = [System.IO.File]::ReadAllBytes($exe)

# File offset = VA - 0x400000 for .text (VirtualAddress 0x1000 = PointerToRawData 0x1000)
$patches = @(
    @{ Offset = 0x28F81; Old = 0x74; New = 0xEB; What = 'create the display with -host' }      # je 428FA7 -> jmp
    @{ Offset = 0x29226; Old = 0x74; New = 0xEB; What = 'create 2D/3D sound with -host' }      # je 429267 -> jmp
)

foreach ($p in $patches) {
    if ($bytes[$p.Offset] -ne $p.Old) { throw ("Unexpected byte at Aqua.exe+0x{0:X}" -f $p.Offset) }
    $bytes[$p.Offset] = $p.New
}

[System.IO.File]::WriteAllBytes($exe, $bytes)
chown "$($Env:UID):$($Env:GID)" $exe

$hash = (Get-FileHash -Path $exe -Algorithm SHA256).Hash
if ($hash -ne $patchedHash) { throw "Patched Aqua.exe has an unexpected sha256 $hash" }

Write-Log "Patched Aqua.exe so -host creates the display and sound it depends on"
