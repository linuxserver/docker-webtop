#!/bin/bash

# Default settings
if [ ! -d "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml ]; then
  mkdir -p "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml
  cp /defaults/xfce/* "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/
fi

# Start DE
WAYLAND_DISPLAY=wayland-1 startxfce4 --wayland > /dev/null 2>&1
