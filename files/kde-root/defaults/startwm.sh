#!/bin/bash

# Set scaling for HiDPI displays
if [ -n "${DPI}" ] && [ "${DPI}" != "96" ]; then
  # Calculate scale factor from DPI (96 DPI = 1.0 scale)
  SCALE_FACTOR=$(echo "scale=2; ${DPI} / 96" | bc)
  export QT_SCALE_FACTOR=${SCALE_FACTOR}
  export GDK_SCALE=${SCALE_FACTOR%.*}  # Integer part for GTK
  export GDK_DPI_SCALE=$(echo "scale=2; 96 / ${DPI}" | bc)  # Inverse for text
  
  # Set KDE scaling
  kwriteconfig5 --file $HOME/.config/kcmfonts --group General --key forceFontDPI ${DPI}
  kwriteconfig5 --file $HOME/.config/kdeglobals --group KScreen --key ScaleFactor ${SCALE_FACTOR}
fi

# Disable compositing and screen lock
if [ ! -f $HOME/.config/kwinrc ]; then
  kwriteconfig5 --file $HOME/.config/kwinrc --group Compositing --key Enabled false
fi
if [ ! -f $HOME/.config/kscreenlockerrc ]; then
  kwriteconfig5 --file $HOME/.config/kscreenlockerrc --group Daemon --key Autolock false
fi

# Power related
setterm blank 0
setterm powerdown 0

# Directories / DBus noise control (run as session user; no sudo)
rm -f /usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service \
  /usr/share/dbus-1/system-services/org.freedesktop.PackageKit.service \
  /etc/xdg/autostart/packagekitd.desktop
mkdir -p "${HOME}/.config/autostart" "${HOME}/.XDG" "${HOME}/.local/share/"
# Fix perms in case persisted home left root-owned
chown -R "$(id -u)":"$(id -g)" "${HOME}/.config" "${HOME}/.XDG" "${HOME}/.local" 2>/dev/null || true
chown "$(id -u)":"$(id -g)" "${HOME}/.xsettingsd" "${HOME}/.Xauthority" "${HOME}/.ICEauthority" 2>/dev/null || true
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

# Ensure XDG_RUNTIME_DIR exists (required for dbus/Qt) with correct perms
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if ! mkdir -p "${XDG_RUNTIME_DIR}" 2>/dev/null; then
  export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
  mkdir -p "${XDG_RUNTIME_DIR}"
fi
chmod 700 "${XDG_RUNTIME_DIR}"

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

# Enable Nvidia GPU support if detected
NVIDIA_PRESENT=false
if which nvidia-smi > /dev/null 2>&1 && nvidia-smi --query-gpu=uuid --format=csv,noheader 2>/dev/null | head -n1 | grep -q .; then
  NVIDIA_PRESENT=true
  echo "NVIDIA GPU detected"
fi

if [ "${NVIDIA_PRESENT}" = "true" ] && [ "${DISABLE_ZINK}" == "false" ]; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

# Configure GPU acceleration
# If USE_XORG=true, use native OpenGL (no VirtualGL needed)
# If USE_XORG=false (Xvfb), use VirtualGL for GPU acceleration
USE_VGL=false
if [ "${USE_XORG}" = "true" ]; then
  # Xorg mode: direct GPU access, no VirtualGL needed
  if [ "${NVIDIA_PRESENT}" = "true" ]; then
    echo "Xorg mode with NVIDIA GPU - using native OpenGL"
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __NV_PRIME_RENDER_OFFLOAD=1
  fi
elif [ "${NVIDIA_PRESENT}" = "true" ] && which vglrun > /dev/null 2>&1; then
  # Xvfb mode with NVIDIA: use VirtualGL
  export VGL_DISPLAY="${VGL_DISPLAY:-egl}"
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export __NV_PRIME_RENDER_OFFLOAD=1
  USE_VGL=true
  echo "Xvfb mode with NVIDIA GPU - using VirtualGL"
fi

# Start DE (without exec to allow dbus-launch to work properly)
# Export XDG_RUNTIME_DIR for the session
export XDG_RUNTIME_DIR
eval "$(dbus-launch --sh-syntax)"
if [ "${USE_VGL}" = "true" ]; then
  echo "Starting KDE Plasma with VirtualGL (VGL_DISPLAY=${VGL_DISPLAY})"
  vglrun -d "${VGL_DISPLAY}" /usr/bin/startplasma-x11 > /dev/null 2>&1
else
  echo "Starting KDE Plasma (native rendering)"
  /usr/bin/startplasma-x11 > /dev/null 2>&1
fi
