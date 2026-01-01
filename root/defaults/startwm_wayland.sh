#!/bin/bash

# Disable compositing and screen locking
if [ ! -f $HOME/.config/kwinrc ]; then
  kwriteconfig6 --file $HOME/.config/kwinrc --group Compositing --key Enabled false
fi
if [ ! -f $HOME/.config/kscreenlockerrc ]; then
  kwriteconfig6 --file $HOME/.config/kscreenlockerrc --group Daemon --key Autolock false
fi
if [ ! -f $HOME/.config/kdeglobals ]; then
  kwriteconfig6 --file $HOME/.config/kdeglobals --group KDE --key LookAndFeelPackage org.fedoraproject.fedora.desktop
fi

# Power related
setterm blank 0
setterm powerdown 0

# Direcotries
sudo rm -f /usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service
mkdir -p "${HOME}/.config/autostart" "${HOME}/.XDG" "${HOME}/.local/share/"
chmod 700 "${HOME}/.XDG"
touch "${HOME}/.local/share/user-places.xbel"

# Background perm loop
if [ ! -d $HOME/.config/kde.org ]; then
  (
    loop_end_time=$((SECONDS + 30))
    while [ $SECONDS -lt $loop_end_time ]; do
        find "$HOME/.cache" "$HOME/.config" "$HOME/.local" -type f -perm 000 -exec chmod 644 {} + 2>/dev/null
        sleep .1
    done
  ) &
fi

# Create startup script if it does not exist (keep in sync with openbox)
STARTUP_FILE="${HOME}/.config/autostart/autostart.desktop"
if [ ! -f "${STARTUP_FILE}" ]; then
  echo "[Desktop Entry]" > $STARTUP_FILE
  echo "Exec=bash /config/.config/openbox/autostart" >> $STARTUP_FILE
  echo "Icon=dialog-scripts" >> $STARTUP_FILE
  echo "Name=autostart" >> $STARTUP_FILE
  echo "Path=" >> $STARTUP_FILE
  echo "Type=Application" >> $STARTUP_FILE
  echo "X-KDE-AutostartScript=true" >> $STARTUP_FILE
  chmod +x $STARTUP_FILE
fi

# Setup application DB
sudo mv \
  /etc/xdg/menus/plasma-applications.menu \
  /etc/xdg/menus/applications.menu
kbuildsycoca6

# Wayland Hacks
unset DISPLAY
sudo setcap -r /usr/sbin/kwin_wayland
sudo rm -f /usr/bin/wl-paste /usr/bin/wl-copy
echo "#! /bin/bash" > /tmp/wl-paste && chmod +x /tmp/wl-paste
echo "#! /bin/bash" > /tmp/wl-copy && chmod +x /tmp/wl-copy
sudo cp /tmp/wl-* /usr/bin/
if ! grep -q "ozone-platform" /usr/local/bin/wrapped-chromium > /dev/null 2>&1; then
  sudo sed -i 's/--password/--ozone-platform=wayland --password/g' /usr/local/bin/wrapped-chromium
fi
sudo rm -f /usr/share/applications/chromium-browser.desktop

# Start DE
WAYLAND_DISPLAY=wayland-1 dbus-run-session kwin_wayland &
sleep 2
WAYLAND_DISPLAY=wayland-0 exec dbus-run-session /usr/bin/plasmashell > /dev/null 2>&1
