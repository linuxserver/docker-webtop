#!/usr/bin/env bash

# Start DE
export XDG_CURRENT_DESKTOP=LXQt
exec dbus-launch --exit-with-session lxqt-session -w /usr/bin/openbox-session > /dev/null 2>&1
