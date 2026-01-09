#!/usr/bin/with-contenv bash

TARGET_USER="${CUSTOM_USER:-${USER_NAME:-root}}"
PORT="${SELKIES_PORT:-8082}"

# Use selkies-gstreamer when GPU is available (nvidia/intel/amd), fallback to legacy selkies
# GPU_VENDOR is passed from start-container.sh: none|nvidia|intel|amd
GPU_VENDOR="${GPU_VENDOR:-none}"

# Check if running in WSL environment
WSL_ENVIRONMENT="${WSL_ENVIRONMENT:-false}"

# Use SELKIES_ENCODER from environment (set by start-container.sh based on GPU_VENDOR)
# This is more reliable than --encoder command line argument
export SELKIES_ENCODER="${SELKIES_ENCODER:-x264enc}"

# Export GStreamer debug level
export GST_DEBUG="${GST_DEBUG:-*:2}"

# Export LIBVA_DRIVER_NAME for Intel/AMD VA-API (set by start-container.sh)
if [ -n "${LIBVA_DRIVER_NAME}" ]; then
  export LIBVA_DRIVER_NAME
  echo "[svc-selkies] Using VA-API driver: ${LIBVA_DRIVER_NAME}"
fi

# Load GStreamer env if present (for selkies-gstreamer) and export all variables
if [ -f /opt/gstreamer/gst-env ]; then
  # shellcheck source=/opt/gstreamer/gst-env
  . /opt/gstreamer/gst-env
  export PATH LD_LIBRARY_PATH GST_PLUGIN_PATH GST_PLUGIN_SYSTEM_PATH GI_TYPELIB_PATH PYTHONPATH GSTREAMER_PATH
fi

# WSL2 specific setup for NVIDIA - add WSL libs to paths AFTER gst-env
# Must be after gst-env because it prepends /opt/gstreamer to LD_LIBRARY_PATH
# We need /usr/lib/wsl/lib at the FRONT for CUDA runtime libraries
if [ "${WSL_ENVIRONMENT}" = "true" ]; then
  echo "[svc-selkies] Running in WSL2 environment"
  if [ -d "/usr/lib/wsl/lib" ]; then
    # Remove /usr/lib/wsl/lib if already present, then add to front
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH//\/usr\/lib\/wsl\/lib:/}"
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH//\/usr\/lib\/wsl\/lib/}"
    export LD_LIBRARY_PATH="/usr/lib/wsl/lib:${LD_LIBRARY_PATH}"
    export PATH="/usr/lib/wsl/lib:${PATH}"
    echo "[svc-selkies] Added WSL library path at front: /usr/lib/wsl/lib"
    echo "[svc-selkies] Final LD_LIBRARY_PATH: ${LD_LIBRARY_PATH}"
  fi
fi

# Clear GStreamer cache to ensure encoder changes take effect
rm -rf "${HOME}/.cache/gstreamer-1.0" 2>/dev/null || true

# Function to find nvidia-smi (handles WSL2 where it's in /usr/lib/wsl/lib)
find_nvidia_smi() {
  if command -v nvidia-smi &> /dev/null; then
    echo "nvidia-smi"
  elif [ -x "/usr/lib/wsl/lib/nvidia-smi" ]; then
    echo "/usr/lib/wsl/lib/nvidia-smi"
  else
    return 1
  fi
}

# Check if NVIDIA GPU is available (works on both native Linux and WSL2)
nvidia_available() {
  local nvidia_smi_cmd
  nvidia_smi_cmd=$(find_nvidia_smi) || return 1
  "${nvidia_smi_cmd}" >/dev/null 2>&1
}

# Extract NVRTC dependency for NVIDIA (required for nvh264enc)
# https://developer.download.nvidia.com/compute/cuda/redist/cuda_nvrtc/LICENSE.txt
if [ "${GPU_VENDOR}" = "nvidia" ] && nvidia_available; then
  NVIDIA_SMI_CMD=$(find_nvidia_smi)
  echo "[svc-selkies] NVIDIA GPU detected via: ${NVIDIA_SMI_CMD}"
  
  NVRTC_DEST_PREFIX="${NVRTC_DEST_PREFIX:-/opt/gstreamer}"
  # Check if we can write to destination, otherwise use user home
  if [ ! -w "${NVRTC_DEST_PREFIX}/lib" ]; then
    NVRTC_DEST_PREFIX="${HOME}/.local/gstreamer"
    mkdir -p "${NVRTC_DEST_PREFIX}/lib" 2>/dev/null
    export LD_LIBRARY_PATH="${NVRTC_DEST_PREFIX}/lib:${LD_LIBRARY_PATH}"
    echo "[svc-selkies] Using user-local NVRTC location: ${NVRTC_DEST_PREFIX}"
  fi
  
  CUDA_DRIVER_SYSTEM="$("${NVIDIA_SMI_CMD}" --version | grep 'CUDA Version' | cut -d: -f2 | tr -d ' ')"
  NVRTC_ARCH="${NVRTC_ARCH:-$(dpkg --print-architecture | sed -e 's/arm64/sbsa/' -e 's/ppc64el/ppc64le/' -e 's/i.*86/x86/' -e 's/amd64/x86_64/' -e 's/unknown/x86_64/')}"
  # TEMPORARY: Cap CUDA version to 12.9 if the detected version is 13.0 or higher for NVRTC compatibility
  # https://gitlab.freedesktop.org/gstreamer/gstreamer/-/issues/4655
  if [ -n "${CUDA_DRIVER_SYSTEM}" ]; then
    CUDA_MAJOR_VERSION=$(echo "${CUDA_DRIVER_SYSTEM}" | cut -d. -f1)
    if [ "${CUDA_MAJOR_VERSION}" -ge 13 ]; then
      CUDA_DRIVER_SYSTEM="12.9"
    fi
  fi
  
  # Download NVRTC if not already present
  NVRTC_LIB_ARCH="$(dpkg --print-architecture | sed -e 's/arm64/aarch64-linux-gnu/' -e 's/armhf/arm-linux-gnueabihf/' -e 's/riscv64/riscv64-linux-gnu/' -e 's/ppc64el/powerpc64le-linux-gnu/' -e 's/s390x/s390x-linux-gnu/' -e 's/i.*86/i386-linux-gnu/' -e 's/amd64/x86_64-linux-gnu/' -e 's/unknown/x86_64-linux-gnu/')"
  NVRTC_LIB_DIR="${NVRTC_DEST_PREFIX}/lib/${NVRTC_LIB_ARCH}"
  
  if [ ! -f "${NVRTC_LIB_DIR}/libnvrtc.so" ]; then
    echo "[svc-selkies] Downloading NVRTC for CUDA ${CUDA_DRIVER_SYSTEM}..."
    NVRTC_URL="https://developer.download.nvidia.com/compute/cuda/redist/cuda_nvrtc/linux-${NVRTC_ARCH}/"
    NVRTC_ARCHIVE="$(curl -fsSL "${NVRTC_URL}" 2>/dev/null | grep -oP "(?<=href=')cuda_nvrtc-linux-${NVRTC_ARCH}-${CUDA_DRIVER_SYSTEM}\.[0-9]+-archive\.tar\.xz" | sort -V | tail -n 1)"
    if [ -z "${NVRTC_ARCHIVE}" ]; then
      FALLBACK_VERSION="${CUDA_DRIVER_SYSTEM}.0"
      NVRTC_ARCHIVE=$((curl -fsSL "${NVRTC_URL}" 2>/dev/null | grep -oP "(?<=href=')cuda_nvrtc-linux-${NVRTC_ARCH}-.*?\.tar\.xz" ; \
      echo "cuda_nvrtc-linux-${NVRTC_ARCH}-${FALLBACK_VERSION}-archive.tar.xz") | \
      sort -V | grep -B 1 --fixed-strings "${FALLBACK_VERSION}" | head -n 1)
    fi
    if [ -n "${NVRTC_ARCHIVE}" ]; then
      echo "[svc-selkies] Selected NVRTC archive: ${NVRTC_ARCHIVE}"
      mkdir -p "${NVRTC_LIB_DIR}" 2>/dev/null
      cd /tmp && curl -fsSL "${NVRTC_URL}${NVRTC_ARCHIVE}" | tar -xJf - -C /tmp && \
        mv -f cuda_nvrtc* cuda_nvrtc && cd cuda_nvrtc/lib && \
        chmod -f 755 libnvrtc* 2>/dev/null && \
        rm -f "${NVRTC_LIB_DIR}/"libnvrtc* 2>/dev/null && \
        mv -f libnvrtc* "${NVRTC_LIB_DIR}/" 2>/dev/null && \
        cd /tmp && rm -rf /tmp/cuda_nvrtc && cd "${HOME}"
      echo "[svc-selkies] NVRTC installed to ${NVRTC_LIB_DIR}"
    else
      echo "[svc-selkies] WARNING: Could not find a compatible NVRTC archive for CUDA ${CUDA_DRIVER_SYSTEM}" >&2
    fi
  fi
fi

if [ "${GPU_VENDOR}" != "none" ] && command -v selkies-gstreamer >/dev/null 2>&1; then
  SELKIES_CMD="selkies-gstreamer"
  # Build command options for selkies-gstreamer
  # Note: Resolution and DPI are controlled by Xorg settings (DISPLAY_WIDTH, DISPLAY_HEIGHT, DPI environment variables)
  # selkies-gstreamer will automatically detect and use the X display configuration
  CMD_OPTS=(--addr="localhost" --port="${PORT}" --enable_basic_auth="false" --enable_resize="true" --enable_metrics_http="true" --metrics_http_port="${SELKIES_METRICS_HTTP_PORT:-9081}" --enable_clipboard="true")
  
  # Add TURN/STUN configuration if provided
  if [ -n "${SELKIES_TURN_HOST}" ]; then
    CMD_OPTS+=(--turn_host="${SELKIES_TURN_HOST}")
  fi
  if [ -n "${SELKIES_TURN_PORT}" ]; then
    CMD_OPTS+=(--turn_port="${SELKIES_TURN_PORT}")
  fi
  if [ -n "${SELKIES_TURN_USERNAME}" ]; then
    CMD_OPTS+=(--turn_username="${SELKIES_TURN_USERNAME}")
  fi
  if [ -n "${SELKIES_TURN_PASSWORD}" ]; then
    CMD_OPTS+=(--turn_password="${SELKIES_TURN_PASSWORD}")
  fi
  if [ -n "${SELKIES_TURN_PROTOCOL}" ]; then
    CMD_OPTS+=(--turn_protocol="${SELKIES_TURN_PROTOCOL}")
  fi
  if [ -n "${SELKIES_ENCODER}" ]; then
    CMD_OPTS+=(--encoder="${SELKIES_ENCODER}")
  fi
  
  if [ -n "${DISPLAY_WIDTH}" ] && [ -n "${DISPLAY_HEIGHT}" ]; then
    echo "[svc-selkies] X Display resolution: ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}"
  fi
  
  if [ -n "${DPI}" ]; then
    echo "[svc-selkies] X Display DPI: ${DPI}"
  fi
  
  echo "[svc-selkies] GPU_VENDOR=${GPU_VENDOR}, using selkies-gstreamer with SELKIES_ENCODER=${SELKIES_ENCODER}"
else
  SELKIES_CMD="selkies"
  CMD_OPTS=(--addr="localhost" --mode="websockets" --port="${PORT}")
  echo "[svc-selkies] GPU_VENDOR=${GPU_VENDOR}, using legacy selkies (WebSocket mode)"
fi

# Start local TURN server for selkies-gstreamer if TURN settings are provided via environment
if [ "${SELKIES_CMD}" = "selkies-gstreamer" ] && [ -n "${SELKIES_TURN_HOST}" ] && [ -n "${SELKIES_TURN_PASSWORD}" ]; then
  echo "[svc-selkies] Starting local TURN server on port 3478 (external: ${SELKIES_TURN_HOST}:${SELKIES_TURN_PORT})"
  /etc/start-turnserver.sh &
fi

# Default sink setup (wait until pulseaudio is ready, then create virtual sinks)
if [ ! -f '/dev/shm/audio.lock' ]; then
  # ensure pulseaudio is up
  for i in $(seq 1 30); do
    if s6-setuidgid "$TARGET_USER" with-contenv pactl info >/dev/null 2>&1; then
      READY=1
      break
    fi
    sleep 0.5
  done
  if [ "${READY:-0}" -eq 1 ]; then
    s6-setuidgid "$TARGET_USER" with-contenv pactl \
      load-module module-null-sink \
      sink_name="output" \
      sink_properties=device.description="output"
    s6-setuidgid "$TARGET_USER" with-contenv pactl \
      load-module module-null-sink \
      sink_name="input" \
      sink_properties=device.description="input"
    touch /dev/shm/audio.lock
  else
    echo "[svc-selkies] pulseaudio not ready; skipped null-sink setup (audio may be missing)." >&2
  fi
fi

# Setup dev mode if defined
if [ ! -z ${DEV_MODE+x} ]; then
  # Dev deps
  apt-get update
  apt-get install -y \
    nodejs
  npm install -g nodemon
  rm -Rf $HOME/.npm
  # Frontend setup
  if [[ "${DEV_MODE}" == "core" ]]; then
    # Core just runs from directory
    cd $HOME/src/addons/gst-web-core
    s6-setuidgid "$TARGET_USER" npm install
    s6-setuidgid "$TARGET_USER" npm run serve &
  else
    # Build core
    cd $HOME/src/addons/gst-web-core
    s6-setuidgid "$TARGET_USER" npm install
    s6-setuidgid "$TARGET_USER" npm run build
    s6-setuidgid "$TARGET_USER" cp dist/selkies-core.js ../${DEV_MODE}/src/
    s6-setuidgid "$TARGET_USER" nodemon --watch selkies-core.js --exec "npm run build && cp dist/selkies-core.js ../${DEV_MODE}/src/" & 
    # Copy touch gamepad
    s6-setuidgid "$TARGET_USER" cp ../universal-touch-gamepad/universalTouchGamepad.js ../${DEV_MODE}/src/
    s6-setuidgid "$TARGET_USER" nodemon --watch ../universal-touch-gamepad/universalTouchGamepad.js --exec "cp ../universal-touch-gamepad/universalTouchGamepad.js ../${DEV_MODE}/src/" &  
    # Copy themes
    s6-setuidgid "$TARGET_USER" cp -a nginx ../${DEV_MODE}/
    # Run passed frontend
    cd $HOME/src/addons/${DEV_MODE}
    s6-setuidgid "$TARGET_USER" npm install
    s6-setuidgid "$TARGET_USER" npm run serve &
  fi
  # Run backend
  cd $HOME/src/src
  s6-setuidgid "$TARGET_USER" \
    nodemon -V --ext py --exec \
      "python3" -m selkies \
      --addr="localhost" \
      --mode="websockets" \
      --debug="true"
fi

# Start Selkies
echo "[svc-selkies] Starting ${SELKIES_CMD} on port ${PORT}"
exec s6-setuidgid "$TARGET_USER" "${SELKIES_CMD}" "${CMD_OPTS[@]}"
