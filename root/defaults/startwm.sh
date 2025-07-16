#!/bin/bash

# Disable blanking
setterm blank 0
setterm powerdown 0

# Dbus defaults
export XDG_RUNTIME_DIR="/tmp/xdg-runtime-${PUID}"
mkdir -p -m700 "${XDG_RUNTIME_DIR}"
chown -R "${PUID}:${PGID}" "${XDG_RUNTIME_DIR}"

# Start DE
exec dbus-launch --exit-with-session /usr/bin/i3 > /dev/null 2>&1
