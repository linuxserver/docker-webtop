#!/usr/bin/env bash

# Setup XDG runtime directory for KDE/Plasma
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$USER}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Load Xresources with dynamic DPI if available
if [ -f /defaults/Xresources ]; then
  # Update DPI in Xresources if DPI environment variable is set
  if [ -n "${DPI}" ]; then
    sed "s/Xft\.dpi:.*/Xft.dpi: ${DPI}/" /defaults/Xresources > /tmp/.Xresources
    xrdb -merge /tmp/.Xresources
    echo "Loaded Xresources with DPI: ${DPI}"
  else
    xrdb -merge /defaults/Xresources
    echo "Loaded Xresources with default DPI settings"
  fi
fi

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
if [ "${NVIDIA_PRESENT}" = "true" ]; then
  if [ "${DISABLE_ZINK}" != "true" ]; then
    # NVIDIA GPU with Zink (Mesa's Vulkan-based OpenGL implementation)
    echo "Configuring NVIDIA GPU with Zink driver"
    export LIBGL_KOPPER_DRI2=1
    export MESA_LOADER_DRIVER_OVERRIDE=zink
    export GALLIUM_DRIVER=zink
  else
    # NVIDIA GPU with native OpenGL (EGL backend)
    echo "Configuring NVIDIA GPU with native EGL/OpenGL"
  fi
  export VGL_DISPLAY="${VGL_DISPLAY:-egl}"
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export __NV_PRIME_RENDER_OFFLOAD=1
  export __VK_LAYER_NV_optimus=NVIDIA_only
elif [ "${GPU_AVAILABLE}" = "true" ]; then
  # Non-NVIDIA GPU (Intel/AMD) - use native drivers with Xvfb's DRI3 device
  echo "Configuring GPU with native drivers (Intel/AMD)"
  # For Intel/AMD GPUs, VirtualGL must use the Xvfb display (:1) not EGL
  # Xvfb is running with -vfbdevice /dev/dri/renderD128 which provides DRI3/GLX support
  export VGL_DISPLAY="${DISPLAY}"
  # Enable DRI3 and hardware acceleration for Intel/AMD
  export LIBGL_ALWAYS_SOFTWARE=0
  export MESA_GL_VERSION_OVERRIDE=4.5
  export MESA_GLSL_VERSION_OVERRIDE=450
  # Force DRI3 for better performance
  if [ "${DISABLE_DRI3}" != "true" ]; then
    export LIBGL_DRI3_ENABLE=1
  fi
fi

# Set VirtualGL frame rate to match display refresh
if [ -n "${DISPLAY_REFRESH}" ]; then
  export VGL_FPS="${DISPLAY_REFRESH}"
fi

# DPI and scaling configuration for applications
# Qt/KDE applications scaling
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough

# Calculate scale factor from DPI (96 DPI = 1.0 scale)
DPI=${DPI:-96}
SCALE_FACTOR=$(echo "scale=2; ${DPI} / 96" | bc)
export QT_SCALE_FACTOR="${SCALE_FACTOR}"
export QT_FONT_DPI="${DPI}"
echo "Qt scaling: QT_SCALE_FACTOR=${SCALE_FACTOR}, QT_FONT_DPI=${DPI}"

# GTK applications scaling (dynamic based on DPI)
# GTK works best with integer scale (2) for high DPI, then adjust with DPI_SCALE
if [ "${DPI}" -ge 120 ]; then
  export GDK_SCALE=2
  # DPI_SCALE should compensate: for 128 DPI (1.33x), we want 2 * 0.667 = 1.33
  GDK_DPI_SCALE_VALUE=$(echo "scale=3; ${SCALE_FACTOR} / 2" | bc)
  export GDK_DPI_SCALE="${GDK_DPI_SCALE_VALUE}"
else
  export GDK_SCALE=1
  export GDK_DPI_SCALE=1
fi
echo "GTK scaling: GDK_SCALE=${GDK_SCALE}, GDK_DPI_SCALE=${GDK_DPI_SCALE} (DPI=${DPI}, effective=${SCALE_FACTOR}x)"

# Electron applications (VSCode, etc.) - force high DPI scaling
export ELECTRON_FORCE_IS_PACKAGED=0
export ELECTRON_OZONE_PLATFORM_HINT=auto
# Force device scale factor for all Chromium/Electron apps
export FORCE_DEVICE_SCALE_FACTOR="${SCALE_FACTOR}"
echo "Electron/Chromium scaling: FORCE_DEVICE_SCALE_FACTOR=${SCALE_FACTOR}"

# Java/Eclipse applications scaling
export SWT_GTK3=1
# Convert DPI to percentage: 96=100%, 128=133%, 192=200%
SWT_AUTO_SCALE=$((${DPI} * 100 / 96))
export SWT_AUTOSCALE="${SWT_AUTO_SCALE}"
# Java 9+ UI scaling
export GDK_SCALE=2
export GDK_DPI_SCALE=$(echo "scale=3; ${SCALE_FACTOR} / 2" | bc)
# Set _JAVA_OPTIONS for all Java applications
export _JAVA_OPTIONS="-Dsun.java2d.uiScale=${SCALE_FACTOR} -Dswt.autoScale=${SWT_AUTO_SCALE} -Dswt.dpi.awareness=1 ${_JAVA_OPTIONS:-}"
echo "Java/Eclipse scaling: sun.java2d.uiScale=${SCALE_FACTOR}, swt.autoScale=${SWT_AUTO_SCALE}% (DPI=${DPI})"

# Set additional session variables for KDE
export XDG_SESSION_ID="${DISPLAY#*:}"
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-*.debug=false;qt.qpa.*=false}"

# Start KDE Plasma desktop with appropriate GPU acceleration
if which startplasma-x11 > /dev/null 2>&1; then
  echo "Starting KDE Plasma desktop"
  # Use VirtualGL for all GPU types (NVIDIA, Intel, AMD)
  # Only skip VirtualGL when no GPU is available (software rendering mode)
  if [ "${GPU_AVAILABLE}" = "true" ] && which vglrun > /dev/null 2>&1; then
    if [ "${NVIDIA_PRESENT}" = "true" ]; then
      echo "Starting with NVIDIA GPU acceleration via VirtualGL (EGL backend)"
      export VGL_FPS="${DISPLAY_REFRESH:-60}"
      /usr/bin/vglrun -d "${VGL_DISPLAY:-egl}" +wm /usr/bin/dbus-launch --exit-with-session /usr/bin/startplasma-x11 > /tmp/startwm.log 2>&1 &
    else
      echo "Starting with GPU acceleration (Intel/AMD) via VirtualGL (Xvfb DRI3 backend)"
      export VGL_FPS="${DISPLAY_REFRESH:-60}"
      # For Intel/AMD, VGL_DISPLAY must point to Xvfb display running with -vfbdevice
      /usr/bin/vglrun -d "${VGL_DISPLAY}" +wm /usr/bin/dbus-launch --exit-with-session /usr/bin/startplasma-x11 > /tmp/startwm.log 2>&1 &
    fi
  else
    echo "Starting with software rendering (no GPU acceleration)"
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
  # Use VirtualGL for all GPU types, skip only for software rendering
  if [ "${GPU_AVAILABLE}" = "true" ] && which vglrun > /dev/null 2>&1; then
    if [ "${NVIDIA_PRESENT}" = "true" ]; then
      echo "Starting with NVIDIA GPU acceleration via VirtualGL"
    else
      echo "Starting with GPU acceleration (Intel/AMD) via VirtualGL"
    fi
    export VGL_FPS="${DISPLAY_REFRESH:-60}"
    exec vglrun -d "${VGL_DISPLAY:-egl}" +wm dbus-launch --exit-with-session /usr/bin/openbox-session
  else
    echo "Starting with software rendering"
    exec dbus-launch --exit-with-session /usr/bin/openbox-session
  fi
else
  echo "ERROR: No desktop environment found"
  exit 1
fi
