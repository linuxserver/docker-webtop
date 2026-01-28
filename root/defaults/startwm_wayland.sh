#!/bin/bash
ulimit -c 0

# Disable compositing and screen locking
if [ ! -f $HOME/.config/kwinrc ]; then
  kwriteconfig6 --file $HOME/.config/kwinrc --group Compositing --key Enabled false
fi
if [ ! -f $HOME/.config/kscreenlockerrc ]; then
  kwriteconfig6 --file $HOME/.config/kscreenlockerrc --group Daemon --key Autolock false
fi

# Power related
setterm blank 0
setterm powerdown 0

# Setup permissive clipboard rules
KWIN_RULES_FILE="$HOME/.config/kwinrulesrc"
RULE_DESC="wl-clipboard support"
if ! grep -q "$RULE_DESC" "$KWIN_RULES_FILE" 2>/dev/null; then
  echo "Applying KWin clipboard rule..."
  if command -v uuidgen &> /dev/null; then
    RULE_ID=$(uuidgen)
  else
    RULE_ID=$(cat /proc/sys/kernel/random/uuid)
  fi
  count=$(kreadconfig6 --file "$KWIN_RULES_FILE" --group General --key count --default 0)
  new_count=$((count + 1))
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group General --key count "$new_count"
  existing_rules=$(kreadconfig6 --file "$KWIN_RULES_FILE" --group General --key rules)
  if [ -z "$existing_rules" ]; then
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group General --key rules "$RULE_ID"
  else
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group General --key rules "$existing_rules,$RULE_ID"
  fi
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key Description "$RULE_DESC"
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key wmclass "wl-(copy|paste)"
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key wmclassmatch 3
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skiptaskbar --type bool "true"
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skiptaskbarrule 2
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skipswitcher --type bool "true"
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skipswitcherrule 2
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key fsplevel 3
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key fsplevelrule 2
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key noborder --type bool "true"
  kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key noborderrule 2
fi

# Directories
sudo rm -f /usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service
mkdir -p "${HOME}/.config/autostart" "${HOME}/.XDG" "${HOME}/.local/share/"
chmod 700 "${HOME}/.XDG"
touch "${HOME}/.local/share/user-places.xbel"

# Background perm loop
if [ ! -d $HOME/.config/kde.org ]; then
  (
    loop_end_time=$((SECONDS + 60))
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
if [ ! -f "/etc/xdg/menus/applications.menu" ]; then
  sudo mv \
    /etc/xdg/menus/plasma-applications.menu \
    /etc/xdg/menus/applications.menu
fi
kbuildsycoca6

# Wayland Hacks
if ! grep -q "ozone-platform" /usr/local/bin/wrapped-chromium > /dev/null 2>&1; then
  sudo sed -i 's/--password/--ozone-platform=wayland --password/g' /usr/local/bin/wrapped-chromium
fi

# Export variables globally so all children inherit them
export QT_QPA_PLATFORM=wayland
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_TYPE=wayland
export KDE_SESSION_VERSION=6
unset DISPLAY
dbus-run-session bash -c '
    WAYLAND_DISPLAY=wayland-1 kwin_wayland --no-lockscreen &
    KWIN_PID=$!
    sleep 2
    if [ -f /usr/lib/libexec/polkit-kde-authentication-agent-1 ]; then
        /usr/lib/libexec/polkit-kde-authentication-agent-1 &
    elif [ -f /usr/libexec/polkit-kde-authentication-agent-1 ]; then
        /usr/libexec/polkit-kde-authentication-agent-1
    fi
    WAYLAND_DISPLAY=wayland-0 plasmashell
    kill $KWIN_PID
' > /dev/null 2>&1
