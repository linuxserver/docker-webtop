#!/usr/bin/env bash

# Start DE
ulimit -c 0
export XCURSOR_THEME=breeze
export XCURSOR_SIZE=24
export XKB_DEFAULT_LAYOUT=us
export XKB_DEFAULT_RULES=evdev
export WAYLAND_DISPLAY=wayland-1
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=LXQt:labwc:wlroots

if [ "${PELORUS,,}" == "true" ]; then
  export QT_ACCESSIBILITY=1
  export QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
  export GTK_MODULES=gail:atk-bridge
  export MOZ_ENABLE_WAYLAND=0
  dbus-run-session bash -c '
    /usr/libexec/at-spi2-registryd &
    ATSPI_PID=$!
    pelorus &
    PELORUS_PID=$!
    labwc &
    LABWC_PID=$!
    sleep 1
    export WAYLAND_DISPLAY=wayland-0
    export DISPLAY=:0
    lxqt-session -w /bin/true
    kill $ATSPI_PID
    kill $LABWC_PID
    kill $PELORUS_PID
  ' > /dev/null 2>&1
else
  dbus-run-session bash -c '
    labwc &
    LABWC_PID=$!
    sleep 1
    export WAYLAND_DISPLAY=wayland-0
    export DISPLAY=:0
    lxqt-session -w /bin/true
    kill $LABWC_PID
  ' > /dev/null 2>&1
fi
