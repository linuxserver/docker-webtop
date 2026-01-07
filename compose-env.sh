#!/bin/bash
# Generate environment variables for docker-compose (same settings as start-container.sh)
# Usage: source <(./compose-env.sh --gpu nvidia --all)
#        ./compose-env.sh --env-file .env --gpu intel

set -e

show_usage() {
    cat <<'EOF'
Usage: compose-env.sh [options]

Options (same as start-container.sh):
  -g, --gpu <type>       GPU vendor: none (default), nvidia, nvidia-wsl, intel, amd
                         Note: --gpu nvidia requires --all or --num
      --all              Use all GPUs (required for nvidia/nvidia-wsl, optional for intel/amd)
      --num <list>       Comma-separated NVIDIA GPU indices (only with --gpu nvidia)
  -u, --ubuntu <ver>     Ubuntu version: 22.04 or 24.04 (default: 24.04)
  -r, --resolution <res> Resolution in WIDTHxHEIGHT format (default: 1920x1080)
  -d, --dpi <dpi>        DPI setting (default: 96)
  -s, --ssl <dir>        SSL directory path for HTTPS (optional)
      --env-file <path>  Write KEY=VALUE pairs to the specified file instead of exports
  -h, --help             Show this help

Environment overrides:
  Resolution: RESOLUTION
  DPI: DPI
  Ports: PORT_SSL_OVERRIDE, PORT_HTTP_OVERRIDE, PORT_TURN_OVERRIDE
  SSL: SSL_DIR
  Container: CONTAINER_NAME, CONTAINER_HOSTNAME
  Image: IMAGE_BASE, IMAGE_TAG
EOF
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults (matching start-container.sh)
GPU_VENDOR="${GPU_VENDOR:-none}"
GPU_ALL="${GPU_ALL:-false}"
GPU_NUMS="${GPU_NUMS:-}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
RESOLUTION="${RESOLUTION:-1920x1080}"
DPI="${DPI:-96}"
SSL_DIR="${SSL_DIR:-}"
OUTPUT_MODE="export"
ENV_FILE=""

# Option parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--gpu)
            if [ -z "${2:-}" ]; then
                echo "Error: --gpu requires an argument" >&2
                exit 1
            fi
            case "${2}" in
                nvidia|nvidia-wsl|intel|amd|none)
                    GPU_VENDOR="${2}"
                    ;;
                *)
                    echo "Error: Unknown GPU vendor: ${2}" >&2
                    exit 1
                    ;;
            esac
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
        -s|--ssl)
            if [ -z "${2:-}" ]; then
                echo "Error: --ssl requires a directory path" >&2
                exit 1
            fi
            SSL_DIR="${2}"
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

if [[ "${GPU_VENDOR}" =~ ^nvidia ]]; then
    if [[ "${GPU_ALL}" != "true" ]] && [[ -z "${GPU_NUMS}" ]]; then
        echo "Error: --gpu nvidia requires --all or --num" >&2
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

if [ -z "${IMAGE_TAG}" ]; then
    IMAGE_TAG="${IMAGE_VERSION}"
fi

USER_IMAGE="${IMAGE_BASE}-${HOST_USER}-${IMAGE_ARCH}-u${UBUNTU_VERSION}:${IMAGE_TAG}"
CONTAINER_HOSTNAME="${CONTAINER_HOSTNAME:-Docker-$(hostname)}"

# Extract width and height from resolution
WIDTH=${RESOLUTION%x*}
HEIGHT=${RESOLUTION#*x}

# Ports (UID-based, but allow overrides)
HOST_PORT_SSL="${PORT_SSL_OVERRIDE:-$((HOST_UID + 10000))}"
HOST_PORT_HTTP="${PORT_HTTP_OVERRIDE:-$((HOST_UID + 20000))}"
HOST_PORT_TURN="${PORT_TURN_OVERRIDE:-$((HOST_UID + 3000))}"

# Get host IP for TURN server
HOST_IP="${HOST_IP:-$(hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1")}"
TURN_RANDOM_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24 || echo "defaultpassword12345678")

# Home mount path
HOST_HOME_MOUNT="/home/${HOST_USER}/host_home"

# GPU configuration
VIDEO_ENCODER="x264enc"
ENABLE_NVIDIA="false"
LIBVA_DRIVER_NAME=""
NVIDIA_VISIBLE_DEVICES=""
GPU_DEVICES=""

case "${GPU_VENDOR}" in
    nvidia|nvidia-wsl)
        VIDEO_ENCODER="nvh264enc"
        ENABLE_NVIDIA="true"
        if [ "${GPU_ALL}" = "true" ]; then
            NVIDIA_VISIBLE_DEVICES="all"
        else
            NVIDIA_VISIBLE_DEVICES="${GPU_NUMS}"
        fi
        ;;
    intel)
        VIDEO_ENCODER="vah264enc"
        LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}"
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        fi
        ;;
    amd)
        VIDEO_ENCODER="vah264enc"
        LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}"
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        fi
        if [ -e "/dev/kfd" ]; then
            GPU_DEVICES="${GPU_DEVICES:+${GPU_DEVICES},}/dev/kfd:/dev/kfd:rwm"
        fi
        ;;
    none|"")
        VIDEO_ENCODER="x264enc"
        ENABLE_NVIDIA="false"
        ;;
esac

SELKIES_ENCODER="${VIDEO_ENCODER}"
SELKIES_TURN_HOST="${HOST_IP}"
SELKIES_TURN_PORT="${HOST_PORT_TURN}"
SELKIES_TURN_USERNAME="selkies"
SELKIES_TURN_PASSWORD="${TURN_RANDOM_PASSWORD}"
SELKIES_TURN_PROTOCOL="tcp"
TURN_EXTERNAL_IP="${HOST_IP}"

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
ENV_VARS=(
    HOST_USER HOST_UID HOST_GID CONTAINER_NAME USER_IMAGE CONTAINER_HOSTNAME
    IMAGE_BASE IMAGE_TAG IMAGE_VERSION IMAGE_ARCH UBUNTU_VERSION
    HOST_PORT_SSL HOST_PORT_HTTP HOST_PORT_TURN HOST_IP
    WIDTH HEIGHT DPI SHM_SIZE RESOLUTION
    GPU_VENDOR GPU_ALL GPU_NUMS VIDEO_ENCODER
    SELKIES_ENCODER
    ENABLE_NVIDIA LIBVA_DRIVER_NAME NVIDIA_VISIBLE_DEVICES GPU_DEVICES
    SSL_DIR SSL_CERT_PATH SSL_KEY_PATH
    HOST_HOME_MOUNT TURN_RANDOM_PASSWORD
    SELKIES_TURN_HOST SELKIES_TURN_PORT SELKIES_TURN_USERNAME SELKIES_TURN_PASSWORD SELKIES_TURN_PROTOCOL TURN_EXTERNAL_IP
    USER_UID USER_GID USER_NAME
)

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
