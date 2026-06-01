#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Container launcher
# - Uses tmpfs for /dev/shm (Docker Desktop/macOS accepts size/mode/etc. but NOT "acl")
# - GPU/encoder selection logic for software/intel/amd/nvidia/nvidia-wsl
# - Supports dind (Docker-in-Docker) and dood (Docker-out-of-Docker)
# ==============================================================================

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
STREAM_SCALE=${STREAM_SCALE:-1.0}
TIMEZONE=${TIMEZONE:-UTC}

# ------------------------------------------------------------------------------
# Shared memory settings: tmpfs mounted at /dev/shm
# NOTE: Docker rejects "acl" as a tmpfs option (daemon-side validation).
#       We intentionally do NOT pass "acl" here.
# ------------------------------------------------------------------------------
SHM_SIZE=${SHM_SIZE:-4g}              # Example: 512m / 4g
SHM_MODE=${SHM_MODE:-1777}            # Standard /dev/shm permissions
SHM_NOEXEC=${SHM_NOEXEC:-true}        # true -> add "noexec"
SHM_EXTRA_OPTS=${SHM_EXTRA_OPTS:-}    # Optional extra tmpfs options (comma-separated)

PLATFORM=${PLATFORM:-}
ARCH_OVERRIDE=${ARCH_OVERRIDE:-}

SSL_DIR=${SSL_DIR:-}
ENCODER=${ENCODER:-}
GPU_VENDOR=${GPU_VENDOR:-}            # Deprecated (kept for compatibility; uses ENCODER)
FRAMERATE=${FRAMERATE:-30}

GPU_ALL=false
GPU_NUMS=""
DOCKER_GPUS=""
DRI_NODE=""

DOCKER_MODE=${DOCKER_MODE:-dind}      # dind|dood
IMAGE_TAG_SET=false
IMAGE_VERSION_DEFAULT=${IMAGE_VERSION:-1.1.0}

HOST_ARCH_RAW=$(uname -m)
case "${HOST_ARCH_RAW}" in
  x86_64|amd64) DETECTED_ARCH=amd64 ;;
  aarch64|arm64) DETECTED_ARCH=arm64 ;;
  *) DETECTED_ARCH="${HOST_ARCH_RAW}" ;;
esac

HOST_IS_MAC=false
if [[ "$(uname -s)" == "Darwin" ]]; then
  HOST_IS_MAC=true
fi
IS_MAC=${IS_MAC:-${HOST_IS_MAC}}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_INTERACTIVE_SCRIPT="${SCRIPT_DIR}/interactive-common.sh"
if [[ ! -f "${COMMON_INTERACTIVE_SCRIPT}" ]]; then
  echo "Error: ${COMMON_INTERACTIVE_SCRIPT} not found." >&2
  exit 1
fi
# shellcheck source=/dev/null
. "${COMMON_INTERACTIVE_SCRIPT}"

usage() {
  cat <<EOF
Usage: $0 [-n name] [-i image-base] [-t version] [-u ubuntu_version] [-r WIDTHxHEIGHT] [-d dpi] [-p platform] [-a arch] [-s ssl_dir]
Run without options to start an interactive configuration flow.
  -n  container name (default: ${NAME})
  -i  image base name; final image becomes <base>-<user>-<arch>-u<ubuntu_ver>:<version> (default base: ${IMAGE_BASE})
  -t  image version tag (default: ${IMAGE_VERSION_DEFAULT})
  -u, --ubuntu  Ubuntu version (22.04, 24.04, or 26.04). Default: ${UBUNTU_VERSION}
  -r  resolution (e.g. 1920x1080, default: ${RESOLUTION})
  -d  DPI (default: ${DPI})
  -S, --stream-scale <factor>  Stream resolution scale (0.25-1.0). Default: ${STREAM_SCALE}
                               Scales down the virtual desktop resolution for lower bandwidth streaming.
                               Example: 0.5 with 1920x1080 streams at 960x540. DPI scaling is unaffected.
      --timezone <tz>          Timezone (default: ${TIMEZONE}, example: Asia/Tokyo)
  -p  platform for docker run (e.g. linux/arm64). Default: host
  -a  image arch for tag (amd64/arm64). Overrides auto-detect
  -s  host directory containing cert.pem and cert.key to mount at ssl (recommended for WSS)
  -e, --encoder <type>  Encoder: software|nvidia|nvidia-wsl|intel|amd (required)
  -f, --framerate <fps> Framerate: single value (60) or range (30-60). Default: 30
  -g, --gpu <value>     Docker --gpus value (optional): all or device=0,1
      --all             shortcut for --gpu all
      --num <list>      shortcut for --gpu device=<list>
      --dri-node <path> DRI render node for VA-API (e.g. /dev/dri/renderD129)
  --docker-mode <mode>  Docker mode: dind (default) or dood
                        dind: start dockerd inside the container (requires --privileged)
                        dood: mount host /var/run/docker.sock into the container

Shared memory env vars:
  SHM_SIZE=4g
  SHM_MODE=1777
  SHM_NOEXEC=true|false
  SHM_EXTRA_OPTS="..."

Encoder examples:
  --encoder software
  --encoder intel
  --encoder amd
  --encoder nvidia
  --encoder nvidia-wsl

Docker GPU examples (optional):
  --gpu all
  --gpu device=0,1
  --all
  --num 0,1
EOF
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

get_socket_gid() {
  local socket_path="$1"
  local gid=""

  if [[ ! -S "${socket_path}" ]]; then
    return 1
  fi

  gid=$(stat -Lc '%g' "${socket_path}" 2>/dev/null || true)
  if [[ -z "${gid}" ]]; then
    gid=$(stat -Lf '%g' "${socket_path}" 2>/dev/null || true)
  fi
  if [[ "${gid}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${gid}"
    return 0
  fi
  return 1
}

prompt_text_default() {
  local __var_name="$1"
  local prompt="$2"
  local default_value="$3"
  local answer

  read -r -p "${prompt} (default: ${default_value}): " answer
  printf -v "${__var_name}" '%s' "${answer:-$default_value}"
}

prompt_optional_text() {
  local __var_name="$1"
  local prompt="$2"
  local answer

  read -r -p "${prompt}: " answer
  printf -v "${__var_name}" '%s' "${answer}"
}

prompt_yes_no_default() {
  local prompt="$1"
  local default_choice="$2"
  local suffix=""
  local default_answer=""
  local answer=""
  local normalized=""

  case "${default_choice}" in
    yes)
      suffix="Y/n"
      default_answer="y"
      ;;
    no)
      suffix="y/N"
      default_answer="n"
      ;;
    *)
      echo "Internal error: invalid yes/no default '${default_choice}'." >&2
      exit 1
      ;;
  esac

  while true; do
    read -r -p "${prompt} (${suffix}): " answer
    answer="${answer:-$default_answer}"
    normalized=$(to_lower "${answer}")
    case "${normalized}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *)
        echo "Please enter y or n, then press Enter."
        ;;
    esac
  done
}

prompt_choice_default() {
  local __var_name="$1"
  local prompt="$2"
  local default_value="$3"
  local pattern="$4"
  local answer

  while true; do
    read -r -p "${prompt} (default: ${default_value}): " answer
    answer="${answer:-$default_value}"
    if [[ "${answer}" =~ ${pattern} ]]; then
      printf -v "${__var_name}" '%s' "${answer}"
      return 0
    fi
    echo "Invalid selection: ${answer}"
  done
}

prompt_required_text() {
  local __var_name="$1"
  local prompt="$2"
  local answer

  while true; do
    read -r -p "${prompt}: " answer
    if [[ -n "${answer}" ]]; then
      printf -v "${__var_name}" '%s' "${answer}"
      return 0
    fi
    echo "A value is required."
  done
}

normalize_arch_or_die() {
  local input="$1"
  case "$(to_lower "${input}")" in
    amd64|x86_64)
      printf '%s' "amd64"
      ;;
    arm64|aarch64)
      printf '%s' "arm64"
      ;;
    *)
      echo "Unsupported architecture: ${input}" >&2
      exit 1
      ;;
  esac
}

handle_existing_container() {
  if ! docker ps -a --format '{{.Names}}' | grep -qx "${NAME}"; then
    return 0
  fi

  local status
  status=$(docker inspect -f '{{.State.Status}}' "${NAME}" 2>/dev/null || echo "unknown")

  case "${status}" in
    exited|created)
      echo "Container ${NAME} exists in status: ${status}. Starting with the previous configuration..."
      docker start "${NAME}" >/dev/null
      echo "Container ${NAME} started."
      exit 0
      ;;
    running)
      echo "Container ${NAME} is already running."
      exit 0
      ;;
    *)
      echo "Container ${NAME} exists in status: ${status}. Remove or fix it manually." >&2
      exit 1
      ;;
  esac
}

interactive_setup() {
  CONTAINER_NAME="${NAME}"
  TARGET_ARCH="${ARCH_OVERRIDE:-${DETECTED_ARCH}}"
  shared_apply_locale_from_timezone "${TIMEZONE}"
  shared_collect_interactive_settings
  NAME="${CONTAINER_NAME}"
  ARCH_OVERRIDE="${TARGET_ARCH}"
}

INTERACTIVE_MODE=false
if [[ $# -eq 0 ]]; then
  INTERACTIVE_MODE=true
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) NAME=$2; shift 2 ;;
    -i) IMAGE_BASE=$2; shift 2 ;;
    -t) IMAGE_TAG=$2; IMAGE_TAG_SET=true; shift 2 ;;
    -u|--ubuntu) UBUNTU_VERSION=$2; shift 2 ;;
    -r) RESOLUTION=$2; shift 2 ;;
    -d) DPI=$2; shift 2 ;;
    -S|--stream-scale) STREAM_SCALE=$2; shift 2 ;;
    --timezone) TIMEZONE=$2; shift 2 ;;
    -p) PLATFORM=$2; shift 2 ;;
    -a|--arch) ARCH_OVERRIDE=$2; shift 2 ;;
    -s) SSL_DIR=$2; shift 2 ;;
    -e|--encoder) ENCODER=$2; shift 2 ;;
    -f|--framerate) FRAMERATE=$2; shift 2 ;;
    -g|--gpu) DOCKER_GPUS=$2; shift 2 ;;
    --all) GPU_ALL=true; shift ;;
    --num) GPU_NUMS=$2; shift 2 ;;
    --dri-node) DRI_NODE=$2; shift 2 ;;
    --docker-mode) DOCKER_MODE=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *) break ;;
  esac
done

handle_existing_container

if [[ "${INTERACTIVE_MODE}" == "true" ]]; then
  interactive_setup
fi

shared_apply_locale_from_timezone "${TIMEZONE}"

if [[ ! $RESOLUTION =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "Resolution must be WIDTHxHEIGHT (e.g. 1920x1080)" >&2
  exit 1
fi

if ! awk "BEGIN { v=${STREAM_SCALE}+0; exit !(v >= 0.25 && v <= 1.0) }" 2>/dev/null; then
  echo "STREAM_SCALE must be between 0.25 and 1.0 (got: ${STREAM_SCALE})" >&2
  exit 1
fi

if [[ ! "${FRAMERATE}" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
  echo "FRAMERATE must be a single integer (e.g. 30) or a range (e.g. 30-60). Got: ${FRAMERATE}" >&2
  exit 1
fi

if [[ "${FRAMERATE}" == *-* ]]; then
  FRAMERATE_MIN=${FRAMERATE%-*}
  FRAMERATE_MAX=${FRAMERATE#*-}
  if (( FRAMERATE_MIN > FRAMERATE_MAX )); then
    echo "FRAMERATE range is invalid: ${FRAMERATE}. Minimum must be <= maximum." >&2
    exit 1
  fi
fi

if [[ -z "${ENCODER}" ]]; then
  echo "Error: --encoder is required." >&2
  usage
  exit 1
fi

if [[ -n "${ARCH_OVERRIDE}" ]]; then
  ARCH_OVERRIDE="$(normalize_arch_or_die "${ARCH_OVERRIDE}")"
fi

ENCODER=$(echo "${ENCODER}" | tr '[:upper:]' '[:lower:]')
case "${ENCODER}" in
  software|none|cpu) ENCODER="software" ;;
  nvidia|nvidia-wsl|intel|amd) ;;
  *)
    echo "Unsupported encoder: ${ENCODER}" >&2
    usage
    exit 1
    ;;
esac

GPU_VENDOR="${ENCODER}"

DOCKER_MODE=$(echo "${DOCKER_MODE}" | tr '[:upper:]' '[:lower:]')
case "${DOCKER_MODE}" in
  dind|dood) ;;
  *)
    echo "Unsupported docker mode: ${DOCKER_MODE}. Use 'dind' or 'dood'." >&2
    usage
    exit 1
    ;;
esac

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
  PLATFORM="linux/${IMAGE_ARCH}"
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
if [[ "${IS_MAC}" != "true" && -d "/mnt" ]]; then
  MNT_FLAGS=(-v "/mnt":"${HOST_MNT_MOUNT}":rw)
else
  echo "Info: Skipping /mnt mount in Mac / Docker Desktop mode." >&2
fi

if [[ -n "${IMAGE_OVERRIDE}" ]]; then
  IMAGE="${IMAGE_OVERRIDE}"
else
  IMAGE="${IMAGE_BASE}-${HOST_USER}-${IMAGE_ARCH}-u${UBUNTU_VERSION}:${IMAGE_TAG}"
fi
REPO_PREFIX="${IMAGE_BASE}-${HOST_USER}-${IMAGE_ARCH}-u${UBUNTU_VERSION}"

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
    echo "Image ${IMAGE} not found. Build the user image first (e.g. ./build-user-image.sh)." >&2
    exit 1
  fi
fi

GPU_FLAGS=()
GPU_ENV_VARS=()

# Detect GPU vendor for a DRM render node (Linux host only)
detect_gpu_vendor() {
  local render_node="$1"
  local node_name
  node_name=$(basename "$render_node")
  local vendor_file="/sys/class/drm/${node_name}/device/vendor"

  if [ -f "$vendor_file" ]; then
    local vendor_id
    vendor_id=$(cat "$vendor_file" 2>/dev/null || true)
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

# Find render nodes for a given vendor, sorted by node number
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

  printf '%s\n' "${nodes[@]}" | sort -t 'D' -k2 -n
}

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
    if [ -n "${DOCKER_GPUS}" ]; then
      GPU_FLAGS+=(--gpus "${DOCKER_GPUS}")
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=true)
      echo "NVIDIA GPUs enabled (--gpus ${DOCKER_GPUS}) even with software encoding."
    else
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=false)
    fi
    ;;
  intel)
    GPU_ENV_VARS+=(-e LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}")
    if [ -n "${DOCKER_GPUS}" ]; then
      GPU_FLAGS+=(--gpus "${DOCKER_GPUS}")
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=true)
      echo "NVIDIA GPUs enabled (--gpus ${DOCKER_GPUS}) for non-encoding purposes."
    else
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=false)
    fi

    if [ -d "/dev/dri" ]; then
      list_detected_gpus

      if [ -n "${DRI_NODE}" ]; then
        VAAPI_CHECK_NODE="${DRI_NODE}"
        echo "Using user-specified DRI node: ${DRI_NODE}"
      else
        INTEL_NODES=$(find_vendor_render_nodes "intel")
        if [ -n "$INTEL_NODES" ]; then
          VAAPI_CHECK_NODE=$(echo "$INTEL_NODES" | head -n1)
          echo "Auto-detected Intel GPU: ${VAAPI_CHECK_NODE}"
        else
          echo "Warning: No Intel GPU found in /dev/dri. Falling back to software encoding." >&2
          VAAPI_CHECK_NODE=""
        fi
      fi

      if [ -n "${VAAPI_CHECK_NODE}" ]; then
        GPU_FLAGS+=(--device=/dev/dri:/dev/dri:rwm)
        GPU_ENV_VARS+=(-e DRI_NODE="${VAAPI_CHECK_NODE}")
      fi
    else
      echo "Warning: /dev/dri not found, Intel VA-API not available. Falling back to software encoding." >&2
    fi
    ;;
  amd)
    GPU_ENV_VARS+=(-e LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}")
    if [ -n "${DOCKER_GPUS}" ]; then
      GPU_FLAGS+=(--gpus "${DOCKER_GPUS}")
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=true)
      echo "NVIDIA GPUs enabled (--gpus ${DOCKER_GPUS}) for non-encoding purposes."
    else
      GPU_ENV_VARS+=(-e ENABLE_NVIDIA=false)
    fi

    if [ -d "/dev/dri" ]; then
      list_detected_gpus

      if [ -n "${DRI_NODE}" ]; then
        VAAPI_CHECK_NODE="${DRI_NODE}"
        echo "Using user-specified DRI node: ${DRI_NODE}"
      else
        AMD_NODES=$(find_vendor_render_nodes "amd")
        if [ -n "$AMD_NODES" ]; then
          VAAPI_CHECK_NODE=$(echo "$AMD_NODES" | head -n1)
          echo "Auto-detected AMD GPU: ${VAAPI_CHECK_NODE}"
        else
          echo "Warning: No AMD GPU found in /dev/dri. Falling back to software encoding." >&2
          VAAPI_CHECK_NODE=""
        fi
      fi

      if [ -n "${VAAPI_CHECK_NODE}" ]; then
        GPU_FLAGS+=(--device=/dev/dri:/dev/dri:rwm)
        GPU_ENV_VARS+=(-e DRI_NODE="${VAAPI_CHECK_NODE}")
      fi
    else
      echo "Warning: /dev/dri not found, AMD VA-API not available. Falling back to software encoding." >&2
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
    if [ -n "${DOCKER_GPUS}" ]; then
      GPU_FLAGS+=(--gpus "${DOCKER_GPUS}")
    else
      echo "Warning: --encoder nvidia-wsl selected but no --gpu value provided; NVENC may be unavailable." >&2
    fi
    if [ -e "/dev/dxg" ]; then
      GPU_FLAGS+=(--device=/dev/dxg:/dev/dxg:rwm)
    else
      echo "Warning: /dev/dxg not found. Are you running on WSL2?" >&2
    fi
    if [ -d "/usr/lib/wsl/lib" ]; then
      GPU_FLAGS+=(-v /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro)
    fi
    if [ -d "/mnt/wslg" ]; then
      GPU_FLAGS+=(-v /mnt/wslg:/mnt/wslg:rw)
      GPU_FLAGS+=(-v /mnt/wslg/.X11-unix:/tmp/.X11-unix:rw)
      GPU_FLAGS+=(-v /usr/lib/wsl/drivers:/usr/lib/wsl/drivers:ro)
    fi
    GPU_ENV_VARS+=(
      -e ENABLE_NVIDIA=true
      -e WSL_ENVIRONMENT=true
      -e DISABLE_ZINK=true
      -e XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir
      -e LD_LIBRARY_PATH=/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}
    )
    ;;
  *)
    echo "Unsupported GPU vendor: ${GPU_VENDOR}" >&2
    exit 1
    ;;
esac

# Add video/render groups (Linux host only; may be empty on macOS)
GROUP_FLAGS=()
VIDEO_GID=$(getent group video 2>/dev/null | cut -d: -f3 || true)
RENDER_GID=$(getent group render 2>/dev/null | cut -d: -f3 || true)
if [ -n "${VIDEO_GID}" ]; then
  GROUP_FLAGS+=(--group-add="${VIDEO_GID}")
  echo "Adding video group (gid: ${VIDEO_GID})"
fi
if [ -n "${RENDER_GID}" ]; then
  GROUP_FLAGS+=(--group-add="${RENDER_GID}")
  echo "Adding render group (gid: ${RENDER_GID})"
fi

PLATFORM_FLAGS=()
if [[ -n "$PLATFORM" ]]; then
  PLATFORM_FLAGS=(--platform "$PLATFORM")
fi

WAYLAND_ENV_VARS=()
if [[ "${UBUNTU_VERSION}" == "26.04" ]]; then
  WAYLAND_ENV_VARS+=(
    -e PIXELFLUX_WAYLAND=true
    -e WAYLAND_DISPLAY=wayland-1
    -e SELKIES_WAYLAND_SOCKET_INDEX=0
  )
fi

DOCKER_MODE_FLAGS=()
if [[ "${DOCKER_MODE}" == "dood" ]]; then
  if [ ! -S /var/run/docker.sock ]; then
    echo "Error: /var/run/docker.sock not found on host. Cannot use dood mode." >&2
    exit 1
  fi
  DOCKER_MODE_FLAGS+=(-v /var/run/docker.sock:/var/run/docker.sock)
  DOCKER_MODE_FLAGS+=(-e START_DOCKER=false)

  # Pass the docker socket group id for permission compatibility on Linux and macOS.
  DOCKER_SOCK_GID=$(get_socket_gid /var/run/docker.sock 2>/dev/null || true)
  if [ -n "${DOCKER_SOCK_GID}" ]; then
    DOCKER_MODE_FLAGS+=(-e DOCKER_SOCK_GID="${DOCKER_SOCK_GID}")
  fi
  if [ -n "${DOCKER_SOCK_GID}" ] && [ "${DOCKER_SOCK_GID}" != "0" ]; then
    DOCKER_MODE_FLAGS+=(--group-add="${DOCKER_SOCK_GID}")
    echo "Docker mode: dood (mounting /var/run/docker.sock, gid: ${DOCKER_SOCK_GID})"
  else
    echo "Docker mode: dood (mounting /var/run/docker.sock)"
  fi
else
  # DinD mode: start dockerd inside container AND mount host socket for container management
  DOCKER_MODE_FLAGS+=(-e START_DOCKER=true)
  
  # Mount host docker socket as host-docker.sock for container stop/commit features
  if [ -S /var/run/docker.sock ]; then
    DOCKER_MODE_FLAGS+=(-v /var/run/docker.sock:/var/run/host-docker.sock:ro)
    DOCKER_SOCK_GID=$(get_socket_gid /var/run/docker.sock 2>/dev/null || true)
    if [ -n "${DOCKER_SOCK_GID}" ] && [ "${DOCKER_SOCK_GID}" != "0" ]; then
      DOCKER_MODE_FLAGS+=(--group-add="${DOCKER_SOCK_GID}")
      echo "Docker mode: dind (starting dockerd inside container, host socket mounted for management, gid: ${DOCKER_SOCK_GID})"
    else
      echo "Docker mode: dind (starting dockerd inside container, host socket mounted for management)"
    fi
  else
    echo "Docker mode: dind (starting dockerd inside container, host socket not available)"
    echo "Warning: Container stop/commit buttons will not work without host docker socket."
  fi
fi

SSL_FLAGS=()
if [[ -z "$SSL_DIR" ]]; then
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
  echo "Warning: No SSL dir mounted. Using image self-signed cert; browsers may reject WSS." >&2
fi

# Build tmpfs mount options for /dev/shm (no "acl")
SHM_EXEC_OPT="exec"
if [[ "${SHM_NOEXEC}" == "true" ]]; then
  SHM_EXEC_OPT="noexec"
fi

SHM_TMPFS_OPTS="rw,nosuid,nodev,${SHM_EXEC_OPT},mode=${SHM_MODE},size=${SHM_SIZE}"
if [[ -n "${SHM_EXTRA_OPTS}" ]]; then
  SHM_TMPFS_OPTS="${SHM_TMPFS_OPTS},${SHM_EXTRA_OPTS}"
fi
echo "Using tmpfs for /dev/shm: ${SHM_TMPFS_OPTS}"

echo "Starting: name=${NAME}, image=${IMAGE}, resolution=${RESOLUTION}, dpi=${DPI}, stream-scale=${STREAM_SCALE}, framerate=${FRAMERATE}, timezone=${TIMEZONE}, encoder=${ENCODER}, docker-gpus=${DOCKER_GPUS:-none}, docker-mode=${DOCKER_MODE}, ports https=${HOST_PORT_SSL}->3001 http=${HOST_PORT_HTTP}->3000"
echo "Chromium scale: ${SCALE_FACTOR} (CHROMIUM_FLAGS=${CHROMIUM_FLAGS_COMBINED})"

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
  -e TZ="${RUNTIME_TZ}" \
  -e LANG="${RUNTIME_LANG}" \
  -e LC_ALL="${RUNTIME_LC_ALL}" \
  -e LANGUAGE="${RUNTIME_LANGUAGE}" \
  -e DPI="$DPI" \
  -e SCALE_FACTOR="${SCALE_FACTOR}" \
  -e FORCE_DEVICE_SCALE_FACTOR="${SCALE_FACTOR}" \
  -e CHROMIUM_FLAGS="${CHROMIUM_FLAGS_COMBINED}" \
  -e DISPLAY_WIDTH="$WIDTH" \
  -e DISPLAY_HEIGHT="$HEIGHT" \
  -e CUSTOM_RESOLUTION="$RESOLUTION" \
  -e STREAM_SCALE="${STREAM_SCALE}" \
  -e USER_UID="${HOST_UID}" \
  -e USER_GID="${HOST_GID}" \
  -e USER_NAME="${HOST_USER}" \
  -e PUID="${HOST_UID}" \
  -e PGID="${HOST_GID}" \
  -e ENCODER="${ENCODER}" \
  -e GPU_VENDOR="${GPU_VENDOR}" \
  -e SELKIES_FRAMERATE="${FRAMERATE}" \
  ${WAYLAND_ENV_VARS[@]+"${WAYLAND_ENV_VARS[@]}"} \
  --tmpfs "/dev/shm:${SHM_TMPFS_OPTS}" \
  --privileged \
  -v "${HOME}":"${HOST_HOME_MOUNT}":rw \
  ${MNT_FLAGS[@]+"${MNT_FLAGS[@]}"} \
  -v "${HOME}/.ssh":"/home/${HOST_USER}/.ssh":rw \
  ${GPU_ENV_VARS[@]+"${GPU_ENV_VARS[@]}"} \
  ${SSL_FLAGS[@]+"${SSL_FLAGS[@]}"} \
  ${DOCKER_MODE_FLAGS[@]+"${DOCKER_MODE_FLAGS[@]}"} \
  "$IMAGE"
