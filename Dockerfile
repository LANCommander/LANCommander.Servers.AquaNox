# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/wine:local
ARG BASE_IMAGE=lancommander/wine:latest
FROM ${BASE_IMAGE}

# Native DirectPlay comes from the DirectX February 2010 redist. Wine's builtin dpnet cannot host
# (IDirectPlay8Server::Host is a stub), so the redist is cached in the image and installed into the
# prefix with `winetricks directplay` on first start. Microsoft's own URL is gone; this is the mirror
# winetricks pins, checked against the same sha256.
ARG DIRECTX_REDIST_URL="https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_feb2010_redist.exe"
ARG DIRECTX_REDIST_SHA256="f6d191e89a963d7cca34f169d30f49eab99c1ed3bb92da73ec43617caaa1e93f"

# ----------------------------
# Server settings
#   - The game files are not downloadable; put an AquaNox v1.18 install in /config/Server, or set
#     AQUANOX_ARCHIVE_URL to a zip of one
#   - The server is the game itself in its dedicated mode (Aqua.exe -host). A hook patches a copy
#     of Aqua.exe so that mode doesn't crash (AQUANOX_PATCH_EXE)
#   - The AQUANOX_* settings are written to ini/<AQUANOX_CONFIG>_si.des / _gi.des on every start
#   - AQUANOX_GAME_TYPE: dm, tdm or ctf. AQUANOX_MAPS: comma-separated rotation; empty uses every
#     map of that type
#   - The game needs a D3D8 display, so it runs under Xvfb; its display mode follows
#     WINE_XVFB_SCREEN (640x480 keeps CPU use low)
# ----------------------------
ENV W_CACHE=/opt/winetricks-cache \
    AQUANOX_ARCHIVE_URL="" \
    AQUANOX_CONFIG="lancommander" \
    AQUANOX_SERVER_NAME="AquaNox Server" \
    AQUANOX_PASSWORD="" \
    AQUANOX_LOCATION="US" \
    AQUANOX_ADMIN_NAME="" \
    AQUANOX_ADMIN_MAIL="" \
    AQUANOX_PORT="30500" \
    AQUANOX_MAX_PLAYERS="16" \
    AQUANOX_PING_LIMIT="0" \
    AQUANOX_ADVERTISE="false" \
    AQUANOX_GAME_TYPE="dm" \
    AQUANOX_MAPS="" \
    AQUANOX_START_MAP="" \
    AQUANOX_TIME_LIMIT="10" \
    AQUANOX_FRAG_LIMIT="20" \
    AQUANOX_CAPTURE_LIMIT="5" \
    AQUANOX_WEAPON_STAY="true" \
    AQUANOX_CDKEY="" \
    AQUANOX_PATCH_EXE="true" \
    AQUANOX_MP_LOG="mp.log" \
    AQUANOX_EXTRA_ARGS="" \
    WINE_XVFB="true" \
    WINE_XVFB_SCREEN="640x480x24" \
    START_EXE="/usr/local/bin/aquanox-server" \
    START_ARGS=""

RUN set -eux; \
    mkdir -p "${W_CACHE}/directx9"; \
    curl -fsSL --retry 3 "${DIRECTX_REDIST_URL}" -o "${W_CACHE}/directx9/directx_feb2010_redist.exe"; \
    echo "${DIRECTX_REDIST_SHA256}  ${W_CACHE}/directx9/directx_feb2010_redist.exe" | sha256sum -c -

COPY Scripts/aquanox-server /usr/local/bin/aquanox-server
RUN chmod +x /usr/local/bin/aquanox-server

COPY Hooks/ "${BASE_HOOKS}/"

# 30500/udp: game (DirectPlay host, AQUANOX_PORT); it also answers DirectPlay enumeration
# 30510/udp: GameSpy status queries (the first free port from 30510)
EXPOSE 30500/udp 30510/udp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
