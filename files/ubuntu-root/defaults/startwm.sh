#!/usr/bin/env bash

# Setup XDG runtime directory for KDE/Plasma
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$USER}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# GPU detection and configuration for WebGL/Vulkan/OpenGL support
NVIDIA_PRESENT=false
GPU_AVAILABLE=false

# Check for NVIDIA GPU
if which nvidia-smi > /dev/null 2>&1 && nvidia-smi --query-gpu=uuid --format=csv,noheader 2>/dev/null | head -n1 | grep -q .; then
  NVIDIA_PRESENT=true
  GPU_AVAILABLE=true
  echo "NVIDIA GPU detected"
fi

# Check for other GPUs via /dev/dri
if ls -A /dev/dri 2>/dev/null | grep -q .; then
  GPU_AVAILABLE=true
  echo "GPU device detected at /dev/dri"
fi

# Configure GPU acceleration based on detected hardware
if [ "${NVIDIA_PRESENT}" = "true" ] && [ "${DISABLE_ZINK}" != "true" ]; then
  # NVIDIA GPU with Zink (Mesa's Vulkan-based OpenGL implementation)
  echo "Configuring NVIDIA GPU with Zink driver"
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
  export VGL_DISPLAY="${VGL_DISPLAY:-egl}"
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export __NV_PRIME_RENDER_OFFLOAD=1
  export __VK_LAYER_NV_optimus=NVIDIA_only
elif [ "${GPU_AVAILABLE}" = "true" ]; then
  # Non-NVIDIA GPU (Intel/AMD) - use native drivers
  echo "Configuring GPU with native drivers"
  export VGL_DISPLAY="${VGL_DISPLAY:-egl}"
fi

# Set VirtualGL frame rate to match display refresh
if [ -n "${DISPLAY_REFRESH}" ]; then
  export VGL_FPS="${DISPLAY_REFRESH}"
fi

# Set additional session variables for KDE
export XDG_SESSION_ID="${DISPLAY#*:}"
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-*.debug=false;qt.qpa.*=false}"

# Start KDE Plasma desktop with appropriate GPU acceleration
if which startplasma-x11 > /dev/null 2>&1; then
  echo "Starting KDE Plasma desktop"
  if [ "${GPU_AVAILABLE}" = "true" ] && which vglrun > /dev/null 2>&1; then
    echo "Starting with VirtualGL acceleration"
    /usr/bin/vglrun -d "${VGL_DISPLAY:-egl}" +wm /usr/bin/dbus-launch --exit-with-session /usr/bin/startplasma-x11 > /tmp/startwm.log 2>&1 &
  else
    echo "Starting with software rendering"
    /usr/bin/dbus-launch --exit-with-session /usr/bin/startplasma-x11 > /tmp/startwm.log 2>&1 &
  fi
  
  # Start fcitx if installed
  if which fcitx > /dev/null 2>&1; then
    /usr/bin/fcitx &
  fi
  
  # Keep the script running
  echo "Session running. Desktop environment started in background."
  wait
  
elif which openbox-session > /dev/null 2>&1; then
  echo "Starting Openbox desktop"
  if [ "${GPU_AVAILABLE}" = "true" ] && which vglrun > /dev/null 2>&1; then
    echo "Starting with VirtualGL acceleration"
    exec vglrun -d "${VGL_DISPLAY:-egl}" +wm dbus-launch --exit-with-session /usr/bin/openbox-session
  else
    echo "Starting with software rendering"
    exec dbus-launch --exit-with-session /usr/bin/openbox-session
  fi
else
  echo "ERROR: No desktop environment found"
  exit 1
fi
