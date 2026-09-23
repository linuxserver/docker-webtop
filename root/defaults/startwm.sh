#!/bin/bash

# Disable compositing and screen locking
if [ ! -f $HOME/.config/kwinrc ]; then
  kwriteconfig6 --file $HOME/.config/kwinrc --group Compositing --key Enabled false
fi
if [ ! -f $HOME/.config/kscreenlockerrc ]; then
  kwriteconfig6 --file $HOME/.config/kscreenlockerrc --group Daemon --key Autolock false
fi

# Direcotries
touch "${HOME}/.local/share/user-places.xbel"

# Start DE
exec dbus-launch --exit-with-session /usr/bin/startplasma-x11 > /dev/null 2>&1
