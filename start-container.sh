#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
HOST_UID=$(id -u "${HOST_USER}")
HOST_GID=$(id -g "${HOST_USER}")
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
IMAGE_BASE=${IMAGE_BASE:-webtop-kde}
IMAGE_TAG=${IMAGE_TAG:-}
IMAGE_OVERRIDE=${IMAGE_NAME:-}
UBUNTU_VERSION=${UBUNTU_VERSION:-24.04}
RESOLUTION=${RESOLUTION:-1920x1080}
DPI=${DPI:-96}
SHM_SIZE=${SHM_SIZE:-4g}
PLATFORM=${PLATFORM:-}
SSL_DIR=${SSL_DIR:-}
GPU_VENDOR=${GPU_VENDOR:-none} # none|nvidia|nvidia-wsl|intel|amd
GPU_ALL=false
GPU_NUMS=""
VIDEO_ENCODER="x264enc"
IMAGE_TAG_SET=false
IMAGE_VERSION_DEFAULT=${IMAGE_VERSION:-1.0.0}
HOST_ARCH_RAW=$(uname -m)
case "${HOST_ARCH_RAW}" in
  x86_64|amd64) DETECTED_ARCH=amd64 ;;
  aarch64|arm64) DETECTED_ARCH=arm64 ;;
  *) DETECTED_ARCH="${HOST_ARCH_RAW}" ;;
esac

usage() {
  cat <<EOF
Usage: $0 [-n name] [-i image-base] [-t version] [-u ubuntu_version] [-r WIDTHxHEIGHT] [-d dpi] [-p platform] [-s ssl_dir]
  -n  container name (default: ${NAME})
  -i  image base name; final image becomes <base>-<user>-<arch>-u<ubuntu_ver>:<version> (default base: ${IMAGE_BASE})
  -t  image version tag (default: ${IMAGE_VERSION_DEFAULT})
  -u, --ubuntu  Ubuntu version (22.04 or 24.04). Default: ${UBUNTU_VERSION}
  -r  resolution (e.g. 1920x1080, default: ${RESOLUTION})
  -d  DPI (default: ${DPI})
  -p  platform for docker run (e.g. linux/arm64). Default: host
  -s  host directory containing cert.pem and cert.key to mount at ssl (recommended for WSS)
  -g  GPU vendor: none|nvidia|nvidia-wsl|intel|amd (default: ${GPU_VENDOR})
      --gpu <vendor>   same as -g
      --all            use all GPUs (required for nvidia/nvidia-wsl, optional for intel/amd)
      --num <list>     comma-separated NVIDIA GPU list (requires -g nvidia, not supported on WSL)

  GPU Examples:
    --gpu nvidia --all          # NVIDIA GPU(s) - all available
    --gpu nvidia --num 0,1      # NVIDIA GPU(s) - specific GPUs
    --gpu nvidia-wsl --all      # NVIDIA on WSL2
    --gpu intel                 # Intel integrated/discrete GPU (VA-API)
    --gpu amd                   # AMD GPU (VA-API + ROCm if available)
    --gpu none                  # Software rendering only
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) NAME=$2; shift 2 ;;
    -i) IMAGE_BASE=$2; shift 2 ;;
    -t) IMAGE_TAG=$2; IMAGE_TAG_SET=true; shift 2 ;;
    -u|--ubuntu) UBUNTU_VERSION=$2; shift 2 ;;
    -r) RESOLUTION=$2; shift 2 ;;
    -d) DPI=$2; shift 2 ;;
    -p) PLATFORM=$2; shift 2 ;;
    -s) SSL_DIR=$2; shift 2 ;;
    -g|--gpu) GPU_VENDOR=$2; shift 2 ;;
    --all) GPU_ALL=true; shift ;;
    --num) GPU_NUMS=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *) break ;;
  esac
done

if [[ ! $RESOLUTION =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "Resolution must be WIDTHxHEIGHT (e.g. 1920x1080)" >&2
  exit 1
fi

if [[ -n "${PLATFORM}" ]]; then
  PLATFORM_ARCH="${PLATFORM#*/}"
  case "${PLATFORM_ARCH}" in
    amd64|x86_64) IMAGE_ARCH="amd64" ;;
    arm64|aarch64) IMAGE_ARCH="arm64" ;;
    *) IMAGE_ARCH="${DETECTED_ARCH}" ;;
  esac
else
  IMAGE_ARCH="${DETECTED_ARCH}"
fi

if [[ "${IMAGE_TAG_SET}" = false || -z "${IMAGE_TAG}" ]]; then
  IMAGE_TAG="${IMAGE_VERSION_DEFAULT}"
fi

WIDTH=${RESOLUTION%x*}
HEIGHT=${RESOLUTION#*x}
SCALE_FACTOR=$(awk "BEGIN { printf \"%.2f\", ${DPI} / 96 }")
CHROMIUM_FLAGS_COMBINED="--force-device-scale-factor=${SCALE_FACTOR} ${CHROMIUM_FLAGS:-}"
HOST_PORT_SSL=${PORT_SSL_OVERRIDE:-$((HOST_UID + 10000))}
HOST_PORT_HTTP=${PORT_HTTP_OVERRIDE:-$((HOST_UID + 20000))}
HOST_PORT_TURN=${PORT_TURN_OVERRIDE:-$((HOST_UID + 3000))}
HOSTNAME_RAW="$(hostname)"
if [[ "$(uname -s)" == "Darwin" ]]; then
  HOSTNAME_RAW="$(scutil --get HostName 2>/dev/null || true)"
  if [[ -z "${HOSTNAME_RAW}" ]]; then
    HOSTNAME_RAW="$(scutil --get LocalHostName 2>/dev/null || true)"
  fi
  if [[ -z "${HOSTNAME_RAW}" ]]; then
    HOSTNAME_RAW="$(scutil --get ComputerName 2>/dev/null || hostname)"
  fi
fi
HOSTNAME_RAW="$(printf '%s' "${HOSTNAME_RAW}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
HOSTNAME_RAW="${HOSTNAME_RAW:-host}"
HOSTNAME_VAL=${CONTAINER_HOSTNAME:-Docker-${HOSTNAME_RAW}}
echo "Using container hostname: ${HOSTNAME_VAL}"
HOST_HOME_MOUNT="/home/${HOST_USER}/host_home"

# Get host IP for TURN server (try multiple methods)
HOST_IP=${HOST_IP:-$(hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1")}
TURN_RANDOM_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24 || echo "defaultpassword12345678")

if [[ -n "${IMAGE_OVERRIDE}" ]]; then
  IMAGE="${IMAGE_OVERRIDE}"
else
  IMAGE="${IMAGE_BASE}-${HOST_USER}-${IMAGE_ARCH}-u${UBUNTU_VERSION}:${IMAGE_TAG}"
fi
REPO_PREFIX="${IMAGE_BASE}-${HOST_USER}-${IMAGE_ARCH}-u${UBUNTU_VERSION}"

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container ${NAME} already exists. Stop/remove it before starting a new one." >&2
  exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Image ${IMAGE} not found. Searching for fallback tags under ${REPO_PREFIX}:*" >&2
  REPO_IMAGES=()
  while IFS= read -r line; do
    REPO_IMAGES+=("$line")
  done < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep "^${REPO_PREFIX}:" || true)
  while IFS= read -r line; do
    REPO_IMAGES+=("$line")
  done < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep "/${REPO_PREFIX}:" || true)
  if [[ ${#REPO_IMAGES[@]} -gt 0 ]]; then
    FALLBACK_IMAGE="${REPO_IMAGES[0]}"
    echo "Using fallback image: ${FALLBACK_IMAGE}" >&2
    IMAGE="${FALLBACK_IMAGE}"
  else
    echo "Image ${IMAGE} not found. Build user image first (e.g. ./build-user-image.sh)." >&2
    exit 1
  fi
fi

GPU_VENDOR=$(echo "${GPU_VENDOR:-none}" | tr '[:upper:]' '[:lower:]')
GPU_FLAGS=()
GPU_ENV_VARS=()

case "${GPU_VENDOR}" in
  none|"")
    GPU_VENDOR="none"
    VIDEO_ENCODER="x264enc"
    GPU_ENV_VARS+=(-e ENABLE_NVIDIA=false)
    ;;
  intel)
    VIDEO_ENCODER="vah264enc"
    GPU_ENV_VARS+=(-e ENABLE_NVIDIA=false -e LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}")
    if [ -d "/dev/dri" ]; then
      # Check if VA-API is actually available (not just /dev/dri existence)
      if command -v vainfo >/dev/null 2>&1; then
        if vainfo --display drm --device /dev/dri/renderD128 >/dev/null 2>&1; then
          GPU_FLAGS+=(--device=/dev/dri:/dev/dri:rwm)
          echo "Intel VA-API available, using hardware acceleration"
        else
          echo "Warning: /dev/dri found but VA-API initialization failed." >&2
          echo "This is normal on NVIDIA-only systems. Use '--gpu nvidia' instead of '--gpu intel'." >&2
          echo "Falling back to software encoding (x264enc)..." >&2
          VIDEO_ENCODER="x264enc"
        fi
      else
        GPU_FLAGS+=(--device=/dev/dri:/dev/dri:rwm)
        echo "Warning: vainfo not found, cannot verify VA-API availability" >&2
      fi
    else
      echo "Warning: /dev/dri not found, Intel VA-API not available." >&2
      echo "Falling back to software encoding (x264enc)..." >&2
      VIDEO_ENCODER="x264enc"
    fi
    ;;
  amd)
    VIDEO_ENCODER="vah264enc"
    GPU_ENV_VARS+=(-e ENABLE_NVIDIA=false -e LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}")
    if [ -d "/dev/dri" ]; then
      # Check if VA-API is actually available
      if command -v vainfo >/dev/null 2>&1; then
        if vainfo --display drm --device /dev/dri/renderD128 >/dev/null 2>&1; then
          GPU_FLAGS+=(--device=/dev/dri:/dev/dri:rwm)
          echo "AMD VA-API available, using hardware acceleration"
        else
          echo "Warning: /dev/dri found but VA-API initialization failed." >&2
          echo "This is normal on NVIDIA-only systems. Use '--gpu nvidia' instead of '--gpu amd'." >&2
          echo "Falling back to software encoding (x264enc)..." >&2
          VIDEO_ENCODER="x264enc"
        fi
      else
        GPU_FLAGS+=(--device=/dev/dri:/dev/dri:rwm)
        echo "Warning: vainfo not found, cannot verify VA-API availability" >&2
      fi
    else
      echo "Warning: /dev/dri not found, AMD VA-API not available." >&2
      echo "Falling back to software encoding (x264enc)..." >&2
      VIDEO_ENCODER="x264enc"
    fi
    if [ -e "/dev/kfd" ]; then
      GPU_FLAGS+=(--device=/dev/kfd:/dev/kfd:rwm)
    fi
    ;;
  nvidia)
    VIDEO_ENCODER="nvh264enc"
    if [ "${GPU_ALL}" = true ]; then
      GPU_FLAGS+=(--gpus all)
    elif [ -n "${GPU_NUMS}" ]; then
      GPU_FLAGS+=(--gpus "device=${GPU_NUMS}")
    else
      echo "Error: --gpu nvidia requires --all or --num." >&2
      exit 1
    fi
    if [ -d "/dev/dri" ]; then
      GPU_FLAGS+=(--device=/dev/dri:/dev/dri:rwm)
    fi
    GPU_ENV_VARS+=(-e ENABLE_NVIDIA=true -e DISABLE_ZINK=true)
    ;;
  nvidia-wsl)
    # WSL2 with NVIDIA GPU support
    VIDEO_ENCODER="nvh264enc"
    # WSL2 only supports --gpus all (no individual GPU selection)
    GPU_FLAGS+=(--gpus all)
    # Mount WSL-specific devices and libraries
    if [ -e "/dev/dxg" ]; then
      GPU_FLAGS+=(--device=/dev/dxg:/dev/dxg:rwm)
    else
      echo "Warning: /dev/dxg not found. Are you running on WSL2?" >&2
    fi
    if [ -d "/usr/lib/wsl/lib" ]; then
      GPU_FLAGS+=(-v /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro)
    fi
    # WSLg support
    if [ -d "/mnt/wslg" ]; then
      GPU_FLAGS+=(-v /mnt/wslg:/mnt/wslg:ro)
    fi
    GPU_ENV_VARS+=(-e ENABLE_NVIDIA=true -e WSL_ENVIRONMENT=true -e DISABLE_ZINK=true)
    ;;
  *)
    echo "Unsupported GPU vendor: ${GPU_VENDOR}" >&2
    exit 1
    ;;
esac

echo "Starting: name=${NAME}, image=${IMAGE}, resolution=${RESOLUTION}, DPI=${DPI}, gpu=${GPU_VENDOR}, host ports https=${HOST_PORT_SSL}->3001, http=${HOST_PORT_HTTP}->3000, turn=${HOST_PORT_TURN}->3478"
echo "Chromium scale: ${SCALE_FACTOR} (CHROMIUM_FLAGS=${CHROMIUM_FLAGS_COMBINED})"

# Add video and render groups for GPU access (use host GIDs)
GROUP_FLAGS=()
VIDEO_GID=$(getent group video 2>/dev/null | cut -d: -f3 || true)
RENDER_GID=$(getent group render 2>/dev/null | cut -d: -f3 || true)
if [ -n "${VIDEO_GID}" ]; then
  GROUP_FLAGS+=(--group-add="${VIDEO_GID}")
  echo "Adding video group (GID: ${VIDEO_GID})"
fi
if [ -n "${RENDER_GID}" ]; then
  GROUP_FLAGS+=(--group-add="${RENDER_GID}")
  echo "Adding render group (GID: ${RENDER_GID})"
fi

PLATFORM_FLAGS=()
if [[ -n "$PLATFORM" ]]; then
  PLATFORM_FLAGS=(--platform "$PLATFORM")
fi
SSL_FLAGS=()
# default SSL dir fallback if not specified
if [[ -z "$SSL_DIR" ]]; then
  # prefer ./ssl next to repo
  DEFAULT_SSL_DIR="$(pwd)/ssl"
  if [[ -d "$DEFAULT_SSL_DIR" ]]; then
    SSL_DIR="$DEFAULT_SSL_DIR"
    echo "Using SSL dir: $SSL_DIR"
  fi
fi

if [[ -n "$SSL_DIR" ]]; then
  if [[ -f "$SSL_DIR/cert.pem" && -f "$SSL_DIR/cert.key" ]]; then
    SSL_FLAGS=(-v "$SSL_DIR":/config/ssl:ro)
  else
    echo "Warning: SSL_DIR set but cert.pem or cert.key missing in $SSL_DIR. Skipping mount." >&2
  fi
else
  echo "Warning: No SSL dir mounted. Using image self-signed cert (CN=*), browsers may reject WSS." >&2
fi

docker run -d \
  ${PLATFORM_FLAGS[@]+"${PLATFORM_FLAGS[@]}"} \
  ${GPU_FLAGS[@]+"${GPU_FLAGS[@]}"} \
  ${GROUP_FLAGS[@]+"${GROUP_FLAGS[@]}"} \
  --name "$NAME" \
  --hostname "${HOSTNAME_VAL}" \
  -e HOSTNAME="${HOSTNAME_VAL}" \
  -e HOST_HOSTNAME="${HOSTNAME_VAL}" \
  -e SHELL=/bin/bash \
  -p ${HOST_PORT_HTTP}:3000 \
  -p ${HOST_PORT_SSL}:3001 \
  -p ${HOST_PORT_TURN}:3478/tcp \
  -p ${HOST_PORT_TURN}:3478/udp \
  -e DISPLAY=:1 \
  -e DPI="$DPI" \
  -e SCALE_FACTOR="${SCALE_FACTOR}" \
  -e FORCE_DEVICE_SCALE_FACTOR="${SCALE_FACTOR}" \
  -e CHROMIUM_FLAGS="${CHROMIUM_FLAGS_COMBINED}" \
  -e DISPLAY_WIDTH="$WIDTH" \
  -e DISPLAY_HEIGHT="$HEIGHT" \
  -e CUSTOM_RESOLUTION="$RESOLUTION" \
  -e USER_UID="${HOST_UID}" \
  -e USER_GID="${HOST_GID}" \
  -e USER_NAME="${HOST_USER}" \
  -e PUID="${HOST_UID}" \
  -e PGID="${HOST_GID}" \
  -e SELKIES_ENCODER="${VIDEO_ENCODER}" \
  -e GPU_VENDOR="${GPU_VENDOR}" \
  -e SELKIES_TURN_HOST="$([ "${GPU_VENDOR}" = "nvidia-wsl" ] && echo "localhost" || echo "${HOST_IP}")" \
  -e SELKIES_TURN_PORT="${HOST_PORT_TURN}" \
  -e SELKIES_TURN_USERNAME="selkies" \
  -e SELKIES_TURN_PASSWORD="${TURN_RANDOM_PASSWORD}" \
  -e SELKIES_TURN_PROTOCOL="tcp" \
  -e TURN_RANDOM_PASSWORD="${TURN_RANDOM_PASSWORD}" \
  -e TURN_EXTERNAL_IP="${HOST_IP}" \
  --shm-size "${SHM_SIZE}" \
  --privileged \
  -v "${HOME}":"${HOST_HOME_MOUNT}":rw \
  -v "${HOME}/.ssh":"/home/${HOST_USER}/.ssh":rw \
  ${GPU_ENV_VARS[@]+"${GPU_ENV_VARS[@]}"} \
  ${SSL_FLAGS[@]+"${SSL_FLAGS[@]}"} \
  "$IMAGE"
