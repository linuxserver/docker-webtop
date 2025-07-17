#!/bin/bash

# Disable blanking
setterm blank 0
setterm powerdown 0

# Dbus defaults
export XDG_RUNTIME_DIR="/tmp/xdg-runtime-abc"
mkdir -p -m700 "${XDG_RUNTIME_DIR}"

# Start DE
exec dbus-launch --exit-with-session /usr/bin/i3 > /dev/null 2>&1
