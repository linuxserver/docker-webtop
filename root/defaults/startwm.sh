#!/bin/bash

# Enable Nvidia GPU support if detected
if which nvidia-smi; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

# Default settings
if [ ! -d "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml ]; then
  mkdir -p "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml
  cp /defaults/xfce/* "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/
fi

# Dbus defaults
export XDG_RUNTIME_DIR="/tmp/xdg-runtime-abc"
mkdir -p -m700 "${XDG_RUNTIME_DIR}"

# Start DE
exec dbus-launch --exit-with-session /usr/bin/xfce4-session > /dev/null 2>&1
