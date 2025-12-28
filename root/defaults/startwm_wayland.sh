#!/bin/bash

# Default settings
if [ ! -d "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml ]; then
  mkdir -p "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml
  cp /defaults/xfce/* "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/
fi

# Start DE
WAYLAND_DISPLAY=wayland-1 Xwayland :1 &
sleep 2
exec dbus-launch --exit-with-session /usr/bin/xfce4-session > /dev/null 2>&1
