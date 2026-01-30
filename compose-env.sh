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
  -t, --timezone <tz>    Timezone (default: UTC, example: Asia/Tokyo)
  -s, --ssl <dir>        SSL directory path for HTTPS (optional)
  -a, --arch <arch>      Target architecture: amd64 or arm64 (default: host)
      --env-file <path>  Write KEY=VALUE pairs to the specified file instead of exports
  -h, --help             Show this help

Environment overrides:
  Resolution: RESOLUTION
  DPI: DPI
  Timezone: TIMEZONE
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
TIMEZONE="${TIMEZONE:-UTC}"
SSL_DIR="${SSL_DIR:-}"
OUTPUT_MODE="export"
ENV_FILE=""
ARCH_OVERRIDE=""

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

if [[ "${GPU_VENDOR}" == "nvidia" ]]; then
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
HOST_PORT_TURN="${PORT_TURN_OVERRIDE:-$((HOST_UID + 45000))}"

# Get host IP for TURN server
HOST_IP="${HOST_IP:-$(hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1")}"
if [ -z "${HOST_IP}" ]; then
    if [ "$(uname -s)" = "Darwin" ]; then
        HOST_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")"
    else
        HOST_IP="127.0.0.1"
    fi
fi
TURN_RANDOM_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24 || echo "defaultpassword12345678")

# Home mount path
HOST_HOME_MOUNT="/home/${HOST_USER}/host_home"
HOST_MNT_MOUNT="/home/${HOST_USER}/host_mnt"

# GPU configuration
VIDEO_ENCODER="x264enc"
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
        VIDEO_ENCODER="nvh264enc"
        ENABLE_NVIDIA="true"
        DISABLE_ZINK="true"
        if [ "${GPU_ALL}" = "true" ]; then
            NVIDIA_VISIBLE_DEVICES="all"
        else
            NVIDIA_VISIBLE_DEVICES="${GPU_NUMS}"
        fi
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        fi
        ;;
    nvidia-wsl)
        VIDEO_ENCODER="nvh264enc"
        ENABLE_NVIDIA="true"
        WSL_ENVIRONMENT="true"
        DISABLE_ZINK="true"
        XDG_RUNTIME_DIR="/mnt/wslg/runtime-dir"
        LD_LIBRARY_PATH="/usr/lib/wsl/lib"
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
            if command -v vainfo >/dev/null 2>&1; then
                if vainfo --display drm --device /dev/dri/renderD128 >/dev/null 2>&1; then
                    GPU_DEVICES="/dev/dri:/dev/dri:rwm"
                else
                    echo "Warning: /dev/dri found but VA-API initialization failed." >&2
                    echo "Falling back to software encoding (x264enc)..." >&2
                    VIDEO_ENCODER="x264enc"
                fi
            else
                GPU_DEVICES="/dev/dri:/dev/dri:rwm"
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
        LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}"
        if [ -d "/dev/dri" ]; then
            if command -v vainfo >/dev/null 2>&1; then
                if vainfo --display drm --device /dev/dri/renderD128 >/dev/null 2>&1; then
                    GPU_DEVICES="/dev/dri:/dev/dri:rwm"
                else
                    echo "Warning: /dev/dri found but VA-API initialization failed." >&2
                    echo "Falling back to software encoding (x264enc)..." >&2
                    VIDEO_ENCODER="x264enc"
                fi
            else
                GPU_DEVICES="/dev/dri:/dev/dri:rwm"
                echo "Warning: vainfo not found, cannot verify VA-API availability" >&2
            fi
        else
            echo "Warning: /dev/dri not found, AMD VA-API not available." >&2
            echo "Falling back to software encoding (x264enc)..." >&2
            VIDEO_ENCODER="x264enc"
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
if [ "${GPU_VENDOR}" = "nvidia-wsl" ]; then
    SELKIES_TURN_HOST="localhost"
else
    SELKIES_TURN_HOST="${HOST_IP}"
fi
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
    WIDTH HEIGHT DPI SCALE_FACTOR FORCE_DEVICE_SCALE_FACTOR CHROMIUM_FLAGS SHM_SIZE RESOLUTION TIMEZONE
    GPU_VENDOR GPU_ALL GPU_NUMS VIDEO_ENCODER
    SELKIES_ENCODER
    ENABLE_NVIDIA LIBVA_DRIVER_NAME NVIDIA_VISIBLE_DEVICES GPU_DEVICES
    WSL_ENVIRONMENT DISABLE_ZINK XDG_RUNTIME_DIR LD_LIBRARY_PATH
    SSL_DIR SSL_CERT_PATH SSL_KEY_PATH
    HOST_HOME_MOUNT HOST_MNT_MOUNT TURN_RANDOM_PASSWORD
    SELKIES_TURN_HOST SELKIES_TURN_PORT SELKIES_TURN_USERNAME SELKIES_TURN_PASSWORD SELKIES_TURN_PROTOCOL TURN_EXTERNAL_IP
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
