#!/bin/bash
ulimit -c 0

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

# Power related
setterm blank 0
setterm powerdown 0

# Direcotries
sudo rm -f /usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service
mkdir -p "${HOME}/.config/autostart" "${HOME}/.XDG" "${HOME}/.local/share/"
chmod 700 "${HOME}/.XDG"
touch "${HOME}/.local/share/user-places.xbel"
sudo mkdir -p /tmp/.X11-unix
sudo chmod 1777 /tmp/.X11-unix

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

# Start user systemd services
if [ -d "$HOME/.config/systemd/user" ]; then
  for service_file in "$HOME/.config/systemd/user/"*.service; do
    if [ -f "$service_file" ]; then
      service_name=$(basename "$service_file")
      echo "Initializing $service_name..."
      /usr/bin/systemctl start "$service_name"
    fi
  done
fi

# Plasma session environment
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_TYPE=wayland
export XDG_MENU_PREFIX=plasma-
export KDE_FULL_SESSION=true
export KDE_SESSION_VERSION=6
KDE_SESSION_UID="$(id -u)"
export KDE_SESSION_UID
export QT_QPA_PLATFORM=wayland
unset DISPLAY
export DISPLAY=:0
export SHELL=/bin/bash
export MOZ_ENABLE_WAYLAND=0
export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
XCURSOR_THEME=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme --default breeze_cursors)
XCURSOR_SIZE=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorSize --default 24)
export XCURSOR_THEME XCURSOR_SIZE
if [ "${PELORUS,,}" == "true" ]; then
  export QT_ACCESSIBILITY=1
  export QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
  export GTK_MODULES=gail:atk-bridge
fi

# Plasma environment scripts
for ENV_SCRIPT in /etc/xdg/plasma-workspace/env/*.sh "${HOME}"/.config/plasma-workspace/env/*.sh; do
  if [ -r "${ENV_SCRIPT}" ]; then
    # shellcheck disable=SC1090
    . "${ENV_SCRIPT}"
  fi
done

# Global theme defaults layer
mkdir -p "${HOME}/.config/kdedefaults"
export XDG_CONFIG_DIRS="${HOME}/.config/kdedefaults:${XDG_CONFIG_DIRS:-/etc/xdg}"

# Setup application DB
kbuildsycoca6

# Plasma session init function
start_session() {
  # Compositor, nested in selkies on wayland-1, provides wayland-0 and :0
  WAYLAND_DISPLAY=wayland-1 kwin_wayland --no-lockscreen --xwayland &
  KWIN_PID=$!
  for _ in $(seq 1 100); do
    if [ -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
      break
    fi
    sleep 0.1
  done
  export WAYLAND_DISPLAY=wayland-0
  dbus-update-activation-environment --all
  pipewire &
  for _ in $(seq 1 100); do
    if [ -S "${XDG_RUNTIME_DIR}/pipewire-0" ]; then
      break
    fi
    sleep 0.1
  done
  LD_PRELOAD= wireplumber &
  kcminit_startup
  kded6 &
  if [ "${PELORUS,,}" == "true" ]; then
    dbus-send --session --dest=org.a11y.Bus --type=method_call \
      --print-reply /org/a11y/bus org.freedesktop.DBus.Properties.Set \
      string:org.a11y.Status string:IsEnabled variant:boolean:true 2>/dev/null || true
    pelorus &
  fi
  xembedsniproxy &
  plasmashell &
  PLASMA_PID=$!
  for _ in $(seq 1 300); do
    if dbus-send --session --print-reply --dest=org.freedesktop.DBus \
      /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
      string:org.kde.plasmashell 2>/dev/null | grep -q true; then
      break
    fi
    sleep 0.1
  done
  xdg-user-dirs-update
  gmenudbusmenuproxy &
  xhost +si:localuser:root
  for ENTRY in "${HOME}"/.config/autostart/*.desktop; do
    if [ ! -f "${ENTRY}" ] || grep -q "^Hidden=true" "${ENTRY}"; then
      continue
    fi
    ENTRY_CMD=$(grep -m1 "^Exec=" "${ENTRY}" | cut -d= -f2- | sed 's/ %[a-zA-Z]//g')
    if [ -n "${ENTRY_CMD}" ]; then
      bash -c "${ENTRY_CMD}" &
    fi
  done
  wait "${PLASMA_PID}"
  kill "${KWIN_PID}"
}
dbus-run-session bash -c "$(declare -f start_session); start_session" > /dev/null 2>&1
