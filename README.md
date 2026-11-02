# AquaNox Server (Docker)

This repository provides a Dockerized **AquaNox** (2001) dedicated server. AquaNox has no separate server program and no Linux build. The image runs the game in its own dedicated mode, `Aqua.exe -host`, under Wine.
The image builds on [`lancommander/wine`](https://github.com/LANCommander/LANCommander.Servers.WINE). It supports file overlaying using OverlayFS.

---

## Features

- Runs the retail v1.18 `Aqua.exe` headless under Wine and Xvfb, in its built-in dedicated server mode
- Patches a copy of `Aqua.exe` so dedicated mode doesn't crash at start. The original stays untouched in `Server/`.
- Native Microsoft DirectPlay is installed into the Wine prefix automatically. Wine's builtin DirectPlay 8 can't host games.
- The server and game settings (`ini/*_si.des`, `ini/*_gi.des`) are generated from environment variables, and the map rotation is checked against the game type
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  aquanox:
    image: lancommander/aquanox:latest
    container_name: aquanox

    ports:
      - "30500:30500/udp"
      - "30510:30510/udp"

    volumes:
      - ./config:/config

    environment:
      AQUANOX_SERVER_NAME: "My AquaNox Server"
      AQUANOX_GAME_TYPE: "dm"
      AQUANOX_FRAG_LIMIT: "20"
      AQUANOX_TIME_LIMIT: "10"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

DirectPlay is LAN-oriented and also opens dynamic UDP ports. A network where the container gets its own LAN IP (macvlan/ipvlan, or `network_mode: host`) is more reliable than port mapping.

---

## Game Files

AquaNox is retail software with no public download. You must provide a **v1.18** install (the GOG release; the folder with `Aqua.exe`, `dat/pak/aquanox*.pak`, `ini/` and `ProfileTemplate/`):

- copy it to `config/Server/`, **or**
- set `AQUANOX_ARCHIVE_URL` to a zip of that folder. It is downloaded and extracted on first start, if `Server/Aqua.exe` doesn't exist yet. The intro movies (`vfx/mov/`, ~230 MB) are skipped.

Clients must run the same version (`gamever 1.18`). Multiplayer in 1.17 and later can't play with older versions.

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # AquaNox v1.18 install (Aqua.exe, dat/, ini/, ProfileTemplate/)
    ├── Overlay/           # Your files, layered on top of Server/ (patched Aqua.exe and ini/*.des land here)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    ├── wineprefix/        # Wine prefix with native DirectPlay and the game profile (auto-created)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [WINE image's variables](https://github.com/LANCommander/LANCommander.Servers.WINE#environment).
The `AQUANOX_*` settings are written to `ini/<AQUANOX_CONFIG>_si.des` (server) and `ini/<AQUANOX_CONFIG>_gi.des` (game rules) on every start.

| Variable | Setting | Default |
|----------|---------|---------|
| `AQUANOX_CONFIG` | file name prefix for the two `.des` files | `lancommander` |
| `AQUANOX_SERVER_NAME` | `Name` (max 31 characters) | `AquaNox Server` |
| `AQUANOX_PASSWORD` | `Password` (join password) | |
| `AQUANOX_LOCATION` | `Location`: a 5-digit US ZIP code or 2-letter country code | `US` |
| `AQUANOX_ADMIN_NAME` | `AdminName` | |
| `AQUANOX_ADMIN_MAIL` | `AdminMail` | |
| `AQUANOX_PORT` | `Port` (game port, UDP) | `30500` |
| `AQUANOX_MAX_PLAYERS` | `MaxPlayers` (1-16) | `16` |
| `AQUANOX_PING_LIMIT` | `PingLimit`: kick players whose 60 s average ping is higher (0 = off, max 250) | `0` |
| `AQUANOX_ADVERTISE` | `Advertise`: register with the GameSpy master server, which no longer exists | `false` |
| `AQUANOX_GAME_TYPE` | `GameType`: `dm`, `tdm` or `ctf` | `dm` |
| `AQUANOX_MAPS` | `Map0`..`Map15`, comma-separated, see below | every map of the game type |
| `AQUANOX_START_MAP` | `StartMap`: the map in the rotation to start on | first map |
| `AQUANOX_TIME_LIMIT` | `TimeLimit` in minutes (0 = off) | `10` |
| `AQUANOX_FRAG_LIMIT` | `FragLimit` (0 = off) | `20` |
| `AQUANOX_CAPTURE_LIMIT` | `CaptureLimit`, CTF only (0 = off) | `5` |
| `AQUANOX_WEAPON_STAY` | `WeaponStay` | `true` |
| `AQUANOX_CDKEY` | the server profile's CD key (`g_cdkey`) | the key in `ProfileTemplate/` |
| `AQUANOX_PATCH_EXE` | patch `Aqua.exe` for dedicated mode (see below) | `true` |
| `AQUANOX_EXTRA_ARGS` | raw arguments appended to the command line | |
| `AQUANOX_ARCHIVE_URL` | zip of the game folder, used if `Server/Aqua.exe` is missing | |
| `WINE_XVFB_SCREEN` | Xvfb screen; the game's display mode is set to match | `640x480x24` |

### Maps

`AQUANOX_MAPS` takes these names (or a custom `map/<folder>/script/<name>` path). Deathmatch and team deathmatch use the DM maps, CTF the CTF maps. Mixing them is rejected, because the game can't run a DM map in CTF mode.

| Game types | Maps |
|------------|------|
| `dm`, `tdm` | `dm_narrow`, `dm_vertical`, `dm_nightfall`, `dm_isolation`, `dm_sightless` |
| `ctf` | `ctf_liberty`, `ctf_stream`, `ctf_canyon` |

To manage the `.des` files yourself, edit the generated ones in `Overlay/ini/` and delete their first line, the `// Generated by the LANCommander image` marker. A file without the marker is never overwritten.

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Building

The image is built `FROM lancommander/wine:latest` by default. To build against a local base image:

```bash
docker build --build-arg BASE_IMAGE=lancommander/wine:local -t lancommander/aquanox:local .
```

The DirectX February 2010 redistributable (source of the DirectPlay DLLs) is downloaded at build time and verified by sha256. See `DIRECTX_REDIST_URL` / `DIRECTX_REDIST_SHA256` in the Dockerfile.

---

## License

AquaNox, Wine and the DirectX redistributable are distributed under their respective licenses.
This repository contains only Docker build logic and helper scripts licensed under MIT.
