#Requires -Modules Logging

# Patches a copy of Aqua.exe (GOG v1.18) for running as a LAN dedicated server:
#
# 1. Dedicated mode (`Aqua.exe -host`) skips creating the display and the 2D sound system, but the
#    start-up code that follows uses both without checking: first `display->...` while creating
#    the network (page fault writing 0x00006DB0 at 0x0050D004), then the sound singleton while
#    creating the movie player (read of 0x00000000 at 0x0041EAED). It only ever worked where the
#    null page is mapped (Windows 9x). The two `if (-host) skip` branches become unconditional
#    jumps into the create path. The display then needs a D3D8 device, which Wine provides on
#    Xvfb; its mode must match the Xvfb screen (see the configure hook).
#
# 2. When a player joins, the server counts the connected players using the same CD key and
#    rejects the newcomer with "Duplicate CD Key" when there is another one. Every GOG copy has the
#    same key, so only one GOG player could join. The counter's increment is removed, so the count
#    is always 0. The key checksum test ("Invalid CD Key") is unchanged.
#
# The copy is written through the merged view, so it lands in Overlay/ and Server/ keeps the
# original. Clients don't need it. Only the known v1.18 Aqua.exe is patched (or a copy patched by
# an earlier version of this hook); anything else is left alone.

$exe = Join-Path $Env:SERVER_ROOT 'Aqua.exe'

$patchedHash = '7C99D1B3D8ECA6DA2D00AAA310FD8A5FB7FED07F7C4B1859C641AB722E5A3713'
$knownHashes = @(
    'EE061C4FC0176225AA664FFD663F6364CBB86C9E174A739EE6391E6390721639'  # GOG v1.18
    '9EEDD8D0A2E036D367168A9B9571365629B69F08028F459ACC0C6164A3670393'  # v1.18 with patch 1 only
)

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

if ($hash -notin $knownHashes) {
    Write-Log -Level Warning "Unknown Aqua.exe (sha256 $hash); not patching it. Aqua.exe -host may crash on start."
    return
}

$bytes = [System.IO.File]::ReadAllBytes($exe)

# File offset = VA - 0x400000 for .text (VirtualAddress 0x1000 = PointerToRawData 0x1000)
$patches = @(
    @{ Offset = 0x28F81;  Old = [byte[]](0x74);                   New = [byte[]](0xEB) }                    # 428F81 je -> jmp: create the display with -host
    @{ Offset = 0x29226;  Old = [byte[]](0x74);                   New = [byte[]](0xEB) }                    # 429226 je -> jmp: create the sound with -host
    @{ Offset = 0x13AD6F; Old = [byte[]](0xFF, 0x44, 0x24, 0x24); New = [byte[]](0x90, 0x90, 0x90, 0x90) }  # 53AD6F inc [esp+24h] -> nop: no duplicate CD keys
)

foreach ($p in $patches) {
    $current = [byte[]]$bytes[$p.Offset..($p.Offset + $p.Old.Length - 1)]
    if ([Linq.Enumerable]::SequenceEqual($current, $p.New)) { continue }
    if (-not [Linq.Enumerable]::SequenceEqual($current, $p.Old)) { throw ("Unexpected bytes at Aqua.exe+0x{0:X}" -f $p.Offset) }
    [Array]::Copy($p.New, 0, $bytes, $p.Offset, $p.New.Length)
}

[System.IO.File]::WriteAllBytes($exe, $bytes)
chown "$($Env:UID):$($Env:GID)" $exe

$hash = (Get-FileHash -Path $exe -Algorithm SHA256).Hash
if ($hash -ne $patchedHash) { throw "Patched Aqua.exe has an unexpected sha256 $hash" }

Write-Log "Patched Aqua.exe for dedicated mode and shared CD keys"
