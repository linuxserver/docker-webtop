#!/bin/bash
# Generate environment variables for docker-compose (same settings as start-container.sh)
# Usage: source <(./compose-env.sh --encoder nvidia --gpu all)
#        ./compose-env.sh --env-file .env --encoder intel

set -e

show_usage() {
    cat <<'EOF'
Usage: compose-env.sh [options]

Options (same as start-container.sh):
  -e, --encoder <type>   Encoder: software, nvidia, nvidia-wsl, intel, amd (required)
    -g, --gpu <value>      Docker --gpus value (optional): all or device=0,1
            --all              Shortcut for --gpu all
            --num <list>       Shortcut for --gpu device=<list>
        --dri-node <path>  DRI render node for VA-API (e.g. /dev/dri/renderD129)
  -u, --ubuntu <ver>     Ubuntu version: 22.04 or 24.04 (default: 24.04)
  -r, --resolution <res> Resolution in WIDTHxHEIGHT format (default: 1920x1080)
  -d, --dpi <dpi>        DPI setting (default: 96)
  -t, --timezone <tz>    Timezone (default: UTC, example: Asia/Tokyo)
  -s, --ssl <dir>        SSL directory path for HTTPS (optional)
  -a, --arch <arch>      Target architecture: amd64 or arm64 (default: host)
      --env-file <path>  Write KEY=VALUE pairs to the specified file instead of exports
  -h, --help             Show this help

Environment overrides:
  Resolution: RESOLUTION
  DPI: DPI
  Timezone: TIMEZONE
  Ports: PORT_SSL_OVERRIDE, PORT_HTTP_OVERRIDE
  SSL: SSL_DIR
  Container: CONTAINER_NAME, CONTAINER_HOSTNAME
  Image: IMAGE_BASE, IMAGE_TAG
EOF
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults (matching start-container.sh)
ENCODER="${ENCODER:-}"
GPU_VENDOR="${GPU_VENDOR:-}"
GPU_ALL="${GPU_ALL:-false}"
GPU_NUMS="${GPU_NUMS:-}"
DOCKER_GPUS="${DOCKER_GPUS:-}"
DRI_NODE="${DRI_NODE:-}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
RESOLUTION="${RESOLUTION:-1920x1080}"
DPI="${DPI:-96}"
TIMEZONE="${TIMEZONE:-UTC}"
SSL_DIR="${SSL_DIR:-}"
OUTPUT_MODE="export"
ENV_FILE=""
ARCH_OVERRIDE=""

# Option parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--encoder)
            if [ -z "${2:-}" ]; then
                echo "Error: --encoder requires an argument" >&2
                exit 1
            fi
            ENCODER="${2}"
            shift 2
            ;;
        -g|--gpu)
            if [ -z "${2:-}" ]; then
                echo "Error: --gpu requires an argument" >&2
                exit 1
            fi
            DOCKER_GPUS="${2}"
            shift 2
            ;;
        --all)
            GPU_ALL="true"
            shift
            ;;
        --num)
            if [ -z "${2:-}" ]; then
                echo "Error: --num requires a value (e.g. --num 0 or --num 0,1)" >&2
                exit 1
            fi
            GPU_NUMS="${2}"
            shift 2
            ;;
        --dri-node)
            if [ -z "${2:-}" ]; then
                echo "Error: --dri-node requires a path (e.g. /dev/dri/renderD129)" >&2
                exit 1
            fi
            DRI_NODE="${2}"
            shift 2
            ;;
        -u|--ubuntu)
            if [ -z "${2:-}" ]; then
                echo "Error: --ubuntu requires a version (22.04 or 24.04)" >&2
                exit 1
            fi
            UBUNTU_VERSION="${2}"
            shift 2
            ;;
        -r|--resolution)
            if [ -z "${2:-}" ]; then
                echo "Error: --resolution requires a value (e.g. 1920x1080)" >&2
                exit 1
            fi
            RESOLUTION="${2}"
            shift 2
            ;;
        -d|--dpi)
            if [ -z "${2:-}" ]; then
                echo "Error: --dpi requires a value" >&2
                exit 1
            fi
            DPI="${2}"
            shift 2
            ;;
        -t|--timezone)
            if [ -z "${2:-}" ]; then
                echo "Error: --timezone requires a value (e.g. Asia/Tokyo)" >&2
                exit 1
            fi
            TIMEZONE="${2}"
            shift 2
            ;;
        -s|--ssl)
            if [ -z "${2:-}" ]; then
                echo "Error: --ssl requires a directory path" >&2
                exit 1
            fi
            SSL_DIR="${2}"
            shift 2
            ;;
        -a|--arch)
            if [ -z "${2:-}" ]; then
                echo "Error: --arch requires a value (amd64 or arm64)" >&2
                exit 1
            fi
            ARCH_OVERRIDE="${2}"
            shift 2
            ;;
        --env-file)
            if [ -z "${2:-}" ]; then
                echo "Error: --env-file requires a path" >&2
                exit 1
            fi
            ENV_FILE="${2}"
            OUTPUT_MODE="envfile"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            show_usage
            exit 1
            ;;
    esac
done

# Validation (match start-container.sh behavior)
if [[ ! $RESOLUTION =~ ^[0-9]+x[0-9]+$ ]]; then
    echo "Error: Resolution must be WIDTHxHEIGHT (e.g. 1920x1080)" >&2
    exit 1
fi

if [ -z "${ENCODER}" ]; then
    echo "Error: --encoder is required" >&2
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
        echo "Error: Unknown encoder: ${ENCODER}" >&2
        exit 1
        ;;
esac

GPU_VENDOR="${ENCODER}"

if [ -z "${DOCKER_GPUS}" ]; then
    if [ "${GPU_ALL}" = "true" ]; then
        DOCKER_GPUS="all"
    elif [ -n "${GPU_NUMS}" ]; then
        DOCKER_GPUS="device=${GPU_NUMS}"
    fi
fi

if [ -n "${DOCKER_GPUS}" ]; then
    if [[ "${DOCKER_GPUS}" != "all" && ! "${DOCKER_GPUS}" =~ ^device=[0-9,]+$ ]]; then
        echo "Error: --gpu value must be 'all' or 'device=0,1'." >&2
        exit 1
    fi
fi

# Base configuration
HOST_USER=${USER:-$(whoami)}
HOST_UID=$(id -u "${HOST_USER}")
HOST_GID=$(id -g "${HOST_USER}")
CONTAINER_NAME="${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}"
IMAGE_BASE="${IMAGE_BASE:-webtop-kde}"
IMAGE_TAG="${IMAGE_TAG:-}"
IMAGE_VERSION="${IMAGE_VERSION:-1.0.0}"
SHM_SIZE="${SHM_SIZE:-4g}"

# Determine architecture
HOST_ARCH_RAW=$(uname -m)
case "${HOST_ARCH_RAW}" in
  x86_64|amd64) IMAGE_ARCH="amd64" ;;
  aarch64|arm64) IMAGE_ARCH="arm64" ;;
  *) IMAGE_ARCH="${HOST_ARCH_RAW}" ;;
esac
if [ -n "${ARCH_OVERRIDE}" ]; then
    case "${ARCH_OVERRIDE}" in
        amd64|x86_64) IMAGE_ARCH="amd64" ;;
        arm64|aarch64) IMAGE_ARCH="arm64" ;;
        *)
            echo "Error: Unsupported arch override: ${ARCH_OVERRIDE}" >&2
            exit 1
            ;;
    esac
fi

if [ -z "${IMAGE_TAG}" ]; then
    IMAGE_TAG="${IMAGE_VERSION}"
fi

USER_IMAGE="${IMAGE_BASE}-${HOST_USER}-${IMAGE_ARCH}-u${UBUNTU_VERSION}:${IMAGE_TAG}"
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
CONTAINER_HOSTNAME="${CONTAINER_HOSTNAME:-Docker-${HOSTNAME_RAW}}"

# Extract width and height from resolution
WIDTH=${RESOLUTION%x*}
HEIGHT=${RESOLUTION#*x}
SCALE_FACTOR=$(awk "BEGIN { printf \"%.2f\", ${DPI} / 96 }")
FORCE_DEVICE_SCALE_FACTOR="${SCALE_FACTOR}"
ORIG_CHROMIUM_FLAGS="${CHROMIUM_FLAGS:-}"
if [ -n "${ORIG_CHROMIUM_FLAGS}" ]; then
    CHROMIUM_FLAGS="--force-device-scale-factor=${SCALE_FACTOR} ${ORIG_CHROMIUM_FLAGS}"
else
    CHROMIUM_FLAGS="--force-device-scale-factor=${SCALE_FACTOR}"
fi

# Ports (UID-based, but allow overrides)
HOST_PORT_SSL="${PORT_SSL_OVERRIDE:-$((HOST_UID + 30000))}"
HOST_PORT_HTTP="${PORT_HTTP_OVERRIDE:-$((HOST_UID + 40000))}"

# Get host IP
HOST_IP="${HOST_IP:-$(hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1")}"
if [ -z "${HOST_IP}" ]; then
    if [ "$(uname -s)" = "Darwin" ]; then
        HOST_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")"
    else
        HOST_IP="127.0.0.1"
    fi
fi

# Home mount path
HOST_HOME_MOUNT="/home/${HOST_USER}/host_home"
HOST_MNT_MOUNT="/home/${HOST_USER}/host_mnt"

# GPU configuration
# Note: pixelflux handles hardware encoding automatically based on GPU_VENDOR
ENABLE_NVIDIA="false"
LIBVA_DRIVER_NAME=""
NVIDIA_VISIBLE_DEVICES=""
GPU_DEVICES=""
WSL_ENVIRONMENT="false"
DISABLE_ZINK="false"
XDG_RUNTIME_DIR=""
LD_LIBRARY_PATH=""

case "${GPU_VENDOR}" in
    nvidia)
        ENABLE_NVIDIA="true"
        DISABLE_ZINK="true"
        if [ "${DOCKER_GPUS}" = "all" ]; then
            NVIDIA_VISIBLE_DEVICES="all"
        elif [[ "${DOCKER_GPUS}" =~ ^device= ]]; then
            NVIDIA_VISIBLE_DEVICES="${DOCKER_GPUS#device=}"
        fi
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        fi
        ;;
    nvidia-wsl)
        ENABLE_NVIDIA="true"
        WSL_ENVIRONMENT="true"
        DISABLE_ZINK="true"
        XDG_RUNTIME_DIR="/mnt/wslg/runtime-dir"
        LD_LIBRARY_PATH="/usr/lib/wsl/lib"
        if [ "${DOCKER_GPUS}" = "all" ]; then
            NVIDIA_VISIBLE_DEVICES="all"
        elif [[ "${DOCKER_GPUS}" =~ ^device= ]]; then
            NVIDIA_VISIBLE_DEVICES="${DOCKER_GPUS#device=}"
        fi
        ;;
    intel)
        LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}"
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        else
            echo "Warning: /dev/dri not found, Intel VA-API not available." >&2
        fi
        # Pass DRI_NODE if specified
        if [ -n "${DRI_NODE}" ]; then
            echo "Using specified DRI node: ${DRI_NODE}" >&2
        fi
        ;;
    amd)
        LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}"
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        else
            echo "Warning: /dev/dri not found, AMD VA-API not available." >&2
        fi
        if [ -e "/dev/kfd" ]; then
            GPU_DEVICES="${GPU_DEVICES:+${GPU_DEVICES},}/dev/kfd:/dev/kfd:rwm"
        fi
        # Pass DRI_NODE if specified
        if [ -n "${DRI_NODE}" ]; then
            echo "Using specified DRI node: ${DRI_NODE}" >&2
        fi
        ;;
    software|"")
        ENABLE_NVIDIA="false"
        ;;
esac

USER_UID="${HOST_UID}"
USER_GID="${HOST_GID}"
USER_NAME="${HOST_USER}"

# SSL configuration
SSL_CERT_PATH=""
SSL_KEY_PATH=""
if [ -n "${SSL_DIR}" ] && [ -d "${SSL_DIR}" ]; then
    if [ -f "${SSL_DIR}/cert.pem" ] && [ -f "${SSL_DIR}/cert.key" ]; then
        SSL_CERT_PATH="${SSL_DIR}/cert.pem"
        SSL_KEY_PATH="${SSL_DIR}/cert.key"
    fi
fi

# Environment variables for docker-compose
# Note: VIDEO_ENCODER, SELKIES_ENCODER, TURN-related variables removed (pixelflux handles encoding)
ENV_VARS=(
    HOST_USER HOST_UID HOST_GID CONTAINER_NAME USER_IMAGE CONTAINER_HOSTNAME
    IMAGE_BASE IMAGE_TAG IMAGE_VERSION IMAGE_ARCH UBUNTU_VERSION
    HOST_PORT_SSL HOST_PORT_HTTP HOST_IP
    WIDTH HEIGHT DPI SCALE_FACTOR FORCE_DEVICE_SCALE_FACTOR CHROMIUM_FLAGS SHM_SIZE RESOLUTION TIMEZONE
    ENCODER GPU_VENDOR GPU_ALL GPU_NUMS DOCKER_GPUS DRI_NODE
    ENABLE_NVIDIA LIBVA_DRIVER_NAME NVIDIA_VISIBLE_DEVICES GPU_DEVICES
    WSL_ENVIRONMENT DISABLE_ZINK XDG_RUNTIME_DIR LD_LIBRARY_PATH
    SSL_DIR SSL_CERT_PATH SSL_KEY_PATH
    HOST_HOME_MOUNT HOST_MNT_MOUNT
    USER_UID USER_GID USER_NAME
)

if [ -n "${DISABLE_ZINK}" ]; then
    ENV_VARS+=(DISABLE_ZINK)
fi
if [ -n "${WSL_ENVIRONMENT}" ]; then
    ENV_VARS+=(WSL_ENVIRONMENT)
fi

emit_exports() {
    for var in "${ENV_VARS[@]}"; do
        printf 'export %s="%s"\n' "${var}" "${!var}"
    done
}

emit_envfile() {
    for var in "${ENV_VARS[@]}"; do
        printf '%s=%s\n' "${var}" "${!var}"
    done
}

if [ -n "${ENV_FILE}" ]; then
    mkdir -p "$(dirname "${ENV_FILE}")"
    emit_envfile > "${ENV_FILE}"
else
    emit_exports
fi
