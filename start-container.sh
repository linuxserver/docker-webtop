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
ARCH_OVERRIDE=${ARCH_OVERRIDE:-}
SSL_DIR=${SSL_DIR:-}
ENCODER=${ENCODER:-}
GPU_VENDOR=${GPU_VENDOR:-} # deprecated (use ENCODER)
GPU_ALL=false
GPU_NUMS=""
DOCKER_GPUS=""
DRI_NODE=""
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
Usage: $0 [-n name] [-i image-base] [-t version] [-u ubuntu_version] [-r WIDTHxHEIGHT] [-d dpi] [-p platform] [-a arch] [-s ssl_dir]
  -n  container name (default: ${NAME})
  -i  image base name; final image becomes <base>-<user>-<arch>-u<ubuntu_ver>:<version> (default base: ${IMAGE_BASE})
  -t  image version tag (default: ${IMAGE_VERSION_DEFAULT})
  -u, --ubuntu  Ubuntu version (22.04 or 24.04). Default: ${UBUNTU_VERSION}
  -r  resolution (e.g. 1920x1080, default: ${RESOLUTION})
  -d  DPI (default: ${DPI})
  -p  platform for docker run (e.g. linux/arm64). Default: host
  -a  image arch for tag (amd64/arm64). Overrides auto-detect
  -s  host directory containing cert.pem and cert.key to mount at ssl (recommended for WSS)
  -e, --encoder <type>  Encoder: software|nvidia|nvidia-wsl|intel|amd (required)
  -g, --gpu <value>     Docker --gpus value (optional): all or device=0,1
      --all             shortcut for --gpu all
      --num <list>      shortcut for --gpu device=<list>
      --dri-node <path> DRI render node for VA-API (e.g. /dev/dri/renderD129)

  Encoder Examples:
    --encoder software                      # Software encoding
    --encoder intel                         # Intel VA-API
    --encoder amd                           # AMD VA-API
    --encoder nvidia                        # NVIDIA NVENC
    --encoder nvidia-wsl                    # NVIDIA NVENC on WSL2

  Docker GPU Examples (optional):
    --gpu all                               # Use all GPUs (NVIDIA)
    --gpu device=0,1                        # Use GPU 0 and 1 (NVIDIA)
    --all                                   # Same as --gpu all
    --num 0,1                               # Same as --gpu device=0,1
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
    -a|--arch) ARCH_OVERRIDE=$2; shift 2 ;;
    -s) SSL_DIR=$2; shift 2 ;;
    -e|--encoder) ENCODER=$2; shift 2 ;;
    -g|--gpu) DOCKER_GPUS=$2; shift 2 ;;
    --all) GPU_ALL=true; shift ;;
    --num) GPU_NUMS=$2; shift 2 ;;
    --dri-node) DRI_NODE=$2; shift 2 ;;
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

if [[ -z "${ENCODER}" ]]; then
  echo "Error: --encoder is required." >&2
  usage
  exit 1
fi

ENCODER=$(echo "${ENCODER}" | tr '[:upper:]' '[:lower:]')
case "${ENCODER}" in
  software|none|cpu)
    ENCODER="software"
    ;;
  nvidia|nvidia-wsl|intel|amd)
    ;;
  *)
    echo "Unsupported encoder: ${ENCODER}" >&2
    usage
    exit 1
    ;;
esac

GPU_VENDOR="${ENCODER}"

if [[ -z "${DOCKER_GPUS}" ]]; then
  if [[ "${GPU_ALL}" = true ]]; then
    DOCKER_GPUS="all"
  elif [[ -n "${GPU_NUMS}" ]]; then
    DOCKER_GPUS="device=${GPU_NUMS}"
  fi
fi

if [[ -n "${DOCKER_GPUS}" ]]; then
  if [[ "${DOCKER_GPUS}" != "all" && ! "${DOCKER_GPUS}" =~ ^device=[0-9,]+$ ]]; then
    echo "Error: --gpu value must be 'all' or 'device=0,1'." >&2
    exit 1
  fi
fi

if [[ -n "${PLATFORM}" ]]; then
  PLATFORM_ARCH="${PLATFORM#*/}"
  case "${PLATFORM_ARCH}" in
    amd64|x86_64) IMAGE_ARCH="amd64" ;;
    arm64|aarch64) IMAGE_ARCH="arm64" ;;
    *) IMAGE_ARCH="${DETECTED_ARCH}" ;;
  esac
elif [[ -n "${ARCH_OVERRIDE}" ]]; then
  IMAGE_ARCH="${ARCH_OVERRIDE}"
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
HOST_PORT_SSL=${PORT_SSL_OVERRIDE:-$((HOST_UID + 30000))}
HOST_PORT_HTTP=${PORT_HTTP_OVERRIDE:-$((HOST_UID + 40000))}
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
HOSTNAME_RAW="$(printf '%s' "${HOSTNAME_RAW}" | tr ' ' '-' | sed 's/[^A-Za-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
HOSTNAME_RAW="${HOSTNAME_RAW:-Host}"
HOSTNAME_VAL=${CONTAINER_HOSTNAME:-Docker-${HOSTNAME_RAW}}
echo "Using container hostname: ${HOSTNAME_VAL}"
HOST_HOME_MOUNT="/home/${HOST_USER}/host_home"
HOST_MNT_MOUNT="/home/${HOST_USER}/host_mnt"
MNT_FLAGS=()
if [[ "$(uname -s)" != "Darwin" ]]; then
  MNT_FLAGS=(-v "/mnt":"${HOST_MNT_MOUNT}":rw)
else
  echo "Info: Skipping /mnt mount on macOS (Docker Desktop file sharing restriction)." >&2
fi

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

GPU_VENDOR="${ENCODER}"
GPU_FLAGS=()
GPU_ENV_VARS=()

# Function to detect GPU vendor from render node
# Returns: intel, amd, nvidia, or unknown
detect_gpu_vendor() {
  local render_node="$1"
  local node_name
  node_name=$(basename "$render_node")
  local vendor_file="/sys/class/drm/${node_name}/device/vendor"
  
  if [ -f "$vendor_file" ]; then
    local vendor_id
    vendor_id=$(cat "$vendor_file" 2>/dev/null)
    case "$vendor_id" in
      0x8086) echo "intel" ;;
      0x10de) echo "nvidia" ;;
      0x1002) echo "amd" ;;
      *) echo "unknown" ;;
    esac
  else
    echo "unknown"
  fi
}

# Function to find all render nodes for a specific vendor
# Outputs nodes sorted by number (smallest first)
find_vendor_render_nodes() {
  local target_vendor="$1"
  local nodes=()
  
  for node in /dev/dri/renderD*; do
    if [ -e "$node" ]; then
      local vendor
      vendor=$(detect_gpu_vendor "$node")
      if [ "$vendor" = "$target_vendor" ]; then
        nodes+=("$node")
      fi
    fi
  done
  
  # Sort by render node number (renderD128 < renderD129)
  printf '%s\n' "${nodes[@]}" | sort -t 'D' -k2 -n
}

# Function to list all detected GPUs
list_detected_gpus() {
  echo "Detected GPUs:"
  for node in /dev/dri/renderD*; do
    if [ -e "$node" ]; then
      local vendor
      vendor=$(detect_gpu_vendor "$node")
      echo "  $node: $vendor"
    fi
  done
}

case "${GPU_VENDOR}" in
  software|"")
    GPU_VENDOR="software"
    # Support --gpu option to still pass NVIDIA GPUs for other purposes (CUDA, ML, etc.)
    if [ -n "${DOCKER_GPUS}" ]; then
      GPU_FLAGS+=(--gpus "${DOCKER_GPUS}")
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=true)
      echo "NVIDIA GPUs enabled (--gpus ${DOCKER_GPUS}) even with software encoding"
    else
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=false)
    fi
    ;;
  intel)
    GPU_ENV_VARS+=(-e LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}")
    # Support --gpu option to also pass NVIDIA GPUs for other purposes (CUDA, ML, etc.)
    if [ -n "${DOCKER_GPUS}" ]; then
      GPU_FLAGS+=(--gpus "${DOCKER_GPUS}")
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=true)
      echo "NVIDIA GPUs enabled (--gpus ${DOCKER_GPUS}) for non-encoding purposes"
    else
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=false)
    fi
    if [ -d "/dev/dri" ]; then
      # List detected GPUs for debugging
      list_detected_gpus
      
      # Determine which render node to use
      if [ -n "${DRI_NODE}" ]; then
        # User specified a node
        VAAPI_CHECK_NODE="${DRI_NODE}"
        echo "Using user-specified DRI node: ${DRI_NODE}"
      else
        # Auto-detect Intel GPU render node
        INTEL_NODES=$(find_vendor_render_nodes "intel")
        if [ -n "$INTEL_NODES" ]; then
          # Use the first (smallest numbered) Intel GPU
          VAAPI_CHECK_NODE=$(echo "$INTEL_NODES" | head -n1)
          echo "Auto-detected Intel GPU: ${VAAPI_CHECK_NODE}"
        else
          echo "Warning: No Intel GPU found in /dev/dri." >&2
          echo "Available GPUs:" >&2
          list_detected_gpus >&2
          echo "Falling back to software encoding..." >&2
          VAAPI_CHECK_NODE=""
        fi
      fi
      
      if [ -n "${VAAPI_CHECK_NODE}" ]; then
        # Always mount /dev/dri and set DRI_NODE if we detected an Intel GPU
        GPU_FLAGS+=(--device=/dev/dri:/dev/dri:rwm)
        GPU_ENV_VARS+=(-e DRI_NODE="${VAAPI_CHECK_NODE}")
        
        # Optionally verify VA-API on host (may fail due to permissions)
        if command -v vainfo >/dev/null 2>&1; then
          if LIBVA_DRIVER_NAME=iHD vainfo --display drm --device "${VAAPI_CHECK_NODE}" >/dev/null 2>&1; then
            echo "Intel VA-API verified on ${VAAPI_CHECK_NODE}, using hardware acceleration"
          else
            echo "Note: VA-API verification failed on host (may work in container with proper permissions)" >&2
            echo "Using ${VAAPI_CHECK_NODE} for Intel VA-API encoding" >&2
          fi
        else
          echo "Note: vainfo not found on host, VA-API will be verified in container" >&2
          echo "Using ${VAAPI_CHECK_NODE} for Intel VA-API encoding" >&2
        fi
      fi
    else
      echo "Warning: /dev/dri not found, Intel VA-API not available." >&2
      echo "Falling back to software encoding..." >&2
    fi
    ;;
  amd)
    GPU_ENV_VARS+=(-e LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}")
    # Support --gpu option to also pass NVIDIA GPUs for other purposes (CUDA, ML, etc.)
    if [ -n "${DOCKER_GPUS}" ]; then
      GPU_FLAGS+=(--gpus "${DOCKER_GPUS}")
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=true)
      echo "NVIDIA GPUs enabled (--gpus ${DOCKER_GPUS}) for non-encoding purposes"
    else
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=false)
    fi
    if [ -d "/dev/dri" ]; then
      # List detected GPUs for debugging
      list_detected_gpus
      
      # Determine which render node to use
      if [ -n "${DRI_NODE}" ]; then
        # User specified a node
        VAAPI_CHECK_NODE="${DRI_NODE}"
        echo "Using user-specified DRI node: ${DRI_NODE}"
      else
        # Auto-detect AMD GPU render node
        AMD_NODES=$(find_vendor_render_nodes "amd")
        if [ -n "$AMD_NODES" ]; then
          # Use the first (smallest numbered) AMD GPU
          VAAPI_CHECK_NODE=$(echo "$AMD_NODES" | head -n1)
          echo "Auto-detected AMD GPU: ${VAAPI_CHECK_NODE}"
        else
          echo "Warning: No AMD GPU found in /dev/dri." >&2
          echo "Available GPUs:" >&2
          list_detected_gpus >&2
          echo "Falling back to software encoding..." >&2
          VAAPI_CHECK_NODE=""
        fi
      fi
      
      if [ -n "${VAAPI_CHECK_NODE}" ]; then
        # Always mount /dev/dri and set DRI_NODE if we detected an AMD GPU
        GPU_FLAGS+=(--device=/dev/dri:/dev/dri:rwm)
        GPU_ENV_VARS+=(-e DRI_NODE="${VAAPI_CHECK_NODE}")
        
        # Optionally verify VA-API on host (may fail due to permissions)
        if command -v vainfo >/dev/null 2>&1; then
          if LIBVA_DRIVER_NAME=radeonsi vainfo --display drm --device "${VAAPI_CHECK_NODE}" >/dev/null 2>&1; then
            echo "AMD VA-API verified on ${VAAPI_CHECK_NODE}, using hardware acceleration"
          else
            echo "Note: VA-API verification failed on host (may work in container with proper permissions)" >&2
            echo "Using ${VAAPI_CHECK_NODE} for AMD VA-API encoding" >&2
          fi
        else
          echo "Note: vainfo not found on host, VA-API will be verified in container" >&2
          echo "Using ${VAAPI_CHECK_NODE} for AMD VA-API encoding" >&2
        fi
      fi
    else
      echo "Warning: /dev/dri not found, AMD VA-API not available." >&2
      echo "Falling back to software encoding..." >&2
    fi
    if [ -e "/dev/kfd" ]; then
      GPU_FLAGS+=(--device=/dev/kfd:/dev/kfd:rwm)
    fi
    ;;
  nvidia)
    if [ -n "${DOCKER_GPUS}" ]; then
      GPU_FLAGS+=(--gpus "${DOCKER_GPUS}")
    else
      echo "Warning: --encoder nvidia selected but no --gpu value provided; NVENC may be unavailable." >&2
    fi
    if [ -d "/dev/dri" ]; then
      GPU_FLAGS+=(--device=/dev/dri:/dev/dri:rwm)
    fi
    GPU_ENV_VARS+=(-e ENABLE_NVIDIA=true -e DISABLE_ZINK=true)
    ;;
  nvidia-wsl)
    # WSL2 with NVIDIA GPU support
    # WSL2 only supports --gpus all (no individual GPU selection)
    if [ -n "${DOCKER_GPUS}" ]; then
      GPU_FLAGS+=(--gpus "${DOCKER_GPUS}")
    else
      echo "Warning: --encoder nvidia-wsl selected but no --gpu value provided; NVENC may be unavailable." >&2
    fi
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

echo "Starting: name=${NAME}, image=${IMAGE}, resolution=${RESOLUTION}, DPI=${DPI}, encoder=${ENCODER}, docker-gpus=${DOCKER_GPUS:-none}, host ports https=${HOST_PORT_SSL}->3001, http=${HOST_PORT_HTTP}->3000"
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
  -e ENCODER="${ENCODER}" \
  -e GPU_VENDOR="${GPU_VENDOR}" \
  --shm-size "${SHM_SIZE}" \
  --privileged \
  -v "${HOME}":"${HOST_HOME_MOUNT}":rw \
  ${MNT_FLAGS[@]+"${MNT_FLAGS[@]}"} \
  -v "${HOME}/.ssh":"/home/${HOST_USER}/.ssh":rw \
  ${GPU_ENV_VARS[@]+"${GPU_ENV_VARS[@]}"} \
  ${SSL_FLAGS[@]+"${SSL_FLAGS[@]}"} \
  "$IMAGE"
