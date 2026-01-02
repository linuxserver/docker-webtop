#!/usr/bin/env bash

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

# Start DE with appropriate GPU acceleration
if [ "${GPU_AVAILABLE}" = "true" ] && which vglrun > /dev/null 2>&1; then
  echo "Starting desktop with VirtualGL acceleration"
  exec vglrun -d "${VGL_DISPLAY:-egl}" +wm dbus-launch --exit-with-session /usr/bin/openbox-session > /dev/null 2>&1
else
  echo "Starting desktop with software rendering"
  exec dbus-launch --exit-with-session /usr/bin/openbox-session > /dev/null 2>&1
fi
