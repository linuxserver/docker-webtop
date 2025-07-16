#!/bin/bash

# Enable Nvidia GPU support if detected
if which nvidia-smi; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

# Disable compositing
setterm blank 0
setterm powerdown 0
gsettings set org.mate.Marco.general compositing-manager false

# Dbus defaults
export XDG_RUNTIME_DIR="/tmp/xdg-runtime-${PUID}"
mkdir -p -m700 "${XDG_RUNTIME_DIR}"
chown -R "${PUID}:${PGID}" "${XDG_RUNTIME_DIR}"

# Start DE
exec dbus-launch --exit-with-session /usr/bin/mate-session > /dev/null 2>&1
