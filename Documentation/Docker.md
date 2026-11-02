---
sidebar_label: Docker
---

# AquaNox Docker Container

This Docker container runs an AquaNox (2001) dedicated server. AquaNox has no separate server program, so the container runs the retail v1.18 game in its built-in dedicated mode, `Aqua.exe -host`, under Wine and Xvfb. It is built on the WINE image. The container doesn't download the game, so you provide the files.

## Quick Start

```yaml
services:
  aquanox:
    image: lancommander/aquanox:latest
    container_name: aquanox

    ports:
      - 30500:30500/udp
      - 30510:30510/udp

    volumes:
      - "/data/Servers/AquaNox/Deathmatch:/config"

    environment:
      AQUANOX_SERVER_NAME: "My AquaNox Server"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

Copy an AquaNox **v1.18** install (the GOG release: `Aqua.exe`, `dat/pak/aquanox0-6.pak`, `ini/`) into `Server/` before the first start. You can leave out `vfx/mov/` (the intro movies). Or set `AQUANOX_ARCHIVE_URL` to a zip of that folder.

## How It Starts

1. `PostInitialization/10-InitializeWinePrefix.ps1` (from the WINE image) creates the Wine prefix in `/config/wineprefix`.
2. `PostInitializeWinePrefix/20-InstallDirectPlay.ps1` runs `winetricks directplay` once, using the DirectX redist cached in the image. This installs Microsoft's `dpnet.dll` and related DLLs. AquaNox hosts with DirectPlay 8, and Wine's builtin `dpnet` can't host. A marker file, `wineprefix/.lancommander-directplay`, records that the install is done. Delete it to reinstall.
3. `PostInitialization/20-InstallAquaNox.ps1` checks for `Server/Aqua.exe`. If it's missing and `AQUANOX_ARCHIVE_URL` is set, the hook downloads the archive.
4. `PostInitialization/25-PatchAquaNox.ps1` writes a patched `Aqua.exe` to `Overlay/` (see below).
5. `PostInitialization/30-ConfigureAquaNox.ps1` writes `ini/<AQUANOX_CONFIG>_si.des` and `_gi.des` from the `AQUANOX_*` variables (they land in `Overlay/ini/`). It also writes the display mode and CD key into the game profile in the Wine prefix.
6. `START_EXE` (`/usr/local/bin/aquanox-server`) runs `wine-run Aqua.exe -host -si ini\<cfg>_si.des -gi ini\<cfg>_gi.des -nomessagebox -mp_log mp.log` from the game root. It follows `mp.log` and the profile's `log.txt` to stdout.

The game writes nothing to stdout. A successful start looks like:

```
Starting: Aqua.exe -host -si ini\lancommander_si.des -gi ini\lancommander_gi.des -nomessagebox -mp_log mp.log
Game port 30500/udp (DirectPlay), GameSpy queries on 30510/udp
Mon Nov 02 18:29:06 2026	server startup
Mon Nov 02 18:29:13 2026	game start: dm_narrow DM timelimit: 10 fraglimit: 20 capturelimit: 5
```

## The Aqua.exe patch

In dedicated mode the game deliberately creates neither its display nor its 2D sound system. The start-up code that follows uses both without checking. It writes through a null display pointer while creating the network (page fault at `0x0050D004`) and reads a null sound pointer while creating the movie player (`0x0041EAED`). On Windows NT and later, and under Wine, `Aqua.exe -host` therefore crashes at once.

The hook flips the two `if (-host) skip creation` branches (`Aqua.exe+0x28F81` and `+0x29226`, `je` to `jmp`), so dedicated mode creates both like a normal start.

It also removes the duplicate CD key check. When a player joins, the server counts the connected players with the same key and rejects the newcomer with "Error: Duplicate CD Key" when there is another one. Every GOG copy has the same key (`1cf2-18ee-109a-2592`), so only one GOG player could join. The hook turns the counter's `inc [esp+24h]` (`Aqua.exe+0x13AD6F`) into NOPs. The key checksum test ("Error: Invalid CD Key") stays.

It only patches the known v1.18 executable (sha256 `ee061c4f…1639`, patched `7c99d1b3…3713`) and leaves any other one alone with a warning. Set `AQUANOX_PATCH_EXE=false` to turn it off. Clients don't need the patch.

Because the display is real, it needs a Direct3D 8 device, which Wine creates on the Xvfb screen. The device is created fullscreen at the profile's `dsp_width` x `dsp_height` x `dsp_depth`. That mode must be the Xvfb screen size, or the game aborts with `CreateDisplay() - desired resolution not found` in `log.txt`. The configure hook sets it from `WINE_XVFB_SCREEN`. The default 640x480 idles at about 9% of a core; 1024x768 uses about 16%.

## Configuration Options

### Ports

- **30500/udp**: Game (DirectPlay host, `AQUANOX_PORT`). It also answers DirectPlay enumeration (`00 02 12 34 02` → reply with the server name).
- **30510/udp**: GameSpy status queries (`\status\` → `\gamename\aquanox\gamever\1.18\hostname\...\mapname\...`). The game takes the first free port from 30510, whatever the game port. It is open even with `AQUANOX_ADVERTISE=false`.

DirectPlay also opens a few dynamic UDP ports. Giving the container its own LAN address (macvlan/ipvlan) is the most reliable setup.

### Environment Variables

See the [README](../README.md#environment-variables) for the table and the map list.

### Settings files

The generated files use the same format as the stock `ini/mp_si.des` and `ini/mp_gi.des`:

```
// Generated by the LANCommander image from the AQUANOX_* settings.
// Change the AQUANOX_* variables, or delete this line to edit the file by hand.

[Server]
{
	Name = "AquaNox Server"
	Password = ""
	Location = "US"
	AdminName = ""
	AdminMail = ""
	IP = ""
	Port = 30500
	PingLimit = 0
	MaxPlayers = 16
	Advertise = 0
	Dedicated = 1
	NumOfMaps = 5
	Map0 = "map/mp_06_dm/script/dm_narrow"
	...
	StartMap = 0
}
```

```
[Game]
{
	GameType = "dm"
	TimeLimit = 10
	FragLimit = 20
	CaptureLimit = 5
	WeaponStay = 1
}
```

Strings are limited to 31 characters (Location to 5) and can't contain `\`. If the hook rejects a setting (an unknown map, a CTF map in a DM rotation, a bad number), it logs the reason and keeps the previous files; on a first start the server then doesn't start. Both files are regenerated on every start while their first line is the marker comment. Delete that line in `Overlay/ini/`, or point `AQUANOX_CONFIG` at files of your own, to manage them by hand.

### Profile

The game keeps its settings in `%APPDATA%\AquaNox\config_1_18.txt`. That is `wineprefix/drive_c/users/lancommander/AppData/Roaming/AquaNox/` here. On every start the configure hook sets `dsp_width`, `dsp_height`, `dsp_depth`, `dsp_fsaa` and `g_cdkey` (`AQUANOX_CDKEY`) in it. It creates the file with just those if it doesn't exist; the game uses its defaults for everything else. Without a valid `g_cdkey`, `-host` silently opens the main menu instead of hosting. It also deletes `touch.txt`, which the game leaves when it doesn't exit cleanly (always, after `docker stop`). With that file present, the next start asks whether to reset the audio/video settings. The `si_*`/`gi_*` values in the profile are the in-game "Start server" menu's. Dedicated mode ignores them.

### Hooks

| Hook | When |
|------|------|
| `PreInstallAquaNox` / `PostInstallAquaNox` | Around the game file check/download |
| `PreInitializeWinePrefix` / `PostInitializeWinePrefix` | Around Wine prefix creation (WINE image) |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

## Troubleshooting

- **The container exits at once with a page fault at `0050D004` or `0041EAED`.** `Aqua.exe` wasn't patched. Check the 25-PatchAquaNox log line. An unknown executable (not the GOG v1.18 one) is left alone.
- **The game exits silently or `log.txt` says "desired resolution not found".** The profile's display mode doesn't match the Xvfb screen. Keep `WINE_XVFB_SCREEN` at a plain `WIDTHxHEIGHTx24` and let the hook set the profile. Don't add `-window`; windowed mode exits silently on a screen the same size as the window.
- **Nothing on UDP 30500, but 30510 answers.** DirectPlay couldn't host. Make sure the native DirectPlay install ran (`wineprefix/.lancommander-directplay`).
- **Edits to `Overlay/` from the host while the container runs don't show up.** OverlayFS caches the upper directory. Restart the container, or edit through `Merged/` inside it (`docker exec`).
- **Clients can't join.** They need v1.18 and a CD key that passes the game's checksum test. Duplicate keys are allowed (see the patch above).
- **The server never binds UDP 30500 and uses a lot of CPU.** It's sitting in the main menu: the profile has no valid `g_cdkey`. Keep `AQUANOX_CDKEY` set.
- ALSA "cannot find card", `libEGL.so.1` and Vulkan messages in the log are harmless.
