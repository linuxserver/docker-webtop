#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
HOST_UID=$(id -u "${HOST_USER}")
HOST_GID=$(id -g "${HOST_USER}")
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
IMAGE_BASE=${IMAGE_BASE:-webtop-kde}
IMAGE_TAG=${IMAGE_TAG:-}
IMAGE_OVERRIDE=${IMAGE_NAME:-}
RESOLUTION=${RESOLUTION:-1920x1080}
DPI=${DPI:-96}
PLATFORM=${PLATFORM:-}
SSL_DIR=${SSL_DIR:-}
IMAGE_TAG_SET=false
HOST_ARCH_RAW=$(uname -m)
case "${HOST_ARCH_RAW}" in
  x86_64|amd64) DETECTED_ARCH=amd64 ;;
  aarch64|arm64) DETECTED_ARCH=arm64 ;;
  *) DETECTED_ARCH="${HOST_ARCH_RAW}" ;;
esac

usage() {
  cat <<EOF
Usage: $0 [-n name] [-i image-base] [-t tag] [-r WIDTHxHEIGHT] [-d dpi] [-p platform] [-s ssl_dir]
  -n  container name (default: ${NAME})
  -i  image base name; final image becomes <base>-<user>:<tag> (default base: ${IMAGE_BASE})
  -t  image tag (default: ${IMAGE_TAG})
  -r  resolution (e.g. 1920x1080, default: ${RESOLUTION})
  -d  DPI (default: ${DPI})
  -p  platform for docker run (e.g. linux/arm64). Default: host
  -s  host directory containing cert.pem and cert.key to mount at ssl (recommended for WSS)
EOF
}

while getopts ":n:i:t:r:d:p:s:h" opt; do
  case "$opt" in
    n) NAME=$OPTARG ;;
    i) IMAGE_BASE=$OPTARG ;;
    t) IMAGE_TAG=$OPTARG; IMAGE_TAG_SET=true ;;
    r) RESOLUTION=$OPTARG ;;
    d) DPI=$OPTARG ;;
    p) PLATFORM=$OPTARG ;;
    s) SSL_DIR=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ ! $RESOLUTION =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "Resolution must be WIDTHxHEIGHT (e.g. 1920x1080)" >&2
  exit 1
fi

if [[ "${IMAGE_TAG_SET}" = false ]]; then
  # If platform is provided, derive arch from it; otherwise use detected arch.
  if [[ -n "${PLATFORM}" ]]; then
    PLATFORM_ARCH="${PLATFORM#*/}"
    case "${PLATFORM_ARCH}" in
      amd64|x86_64) IMAGE_TAG="amd64-latest" ;;
      arm64|aarch64) IMAGE_TAG="arm64-latest" ;;
      *) IMAGE_TAG="${DETECTED_ARCH}-latest" ;;
    esac
  else
    IMAGE_TAG="${DETECTED_ARCH}-latest"
  fi
fi

WIDTH=${RESOLUTION%x*}
HEIGHT=${RESOLUTION#*x}
HOST_PORT_SSL=${PORT_SSL_OVERRIDE:-$((HOST_UID + 10000))}
HOST_PORT_HTTP=${PORT_HTTP_OVERRIDE:-$((HOST_UID + 20000))}
HOSTNAME_VAL=${CONTAINER_HOSTNAME:-Docker-$(hostname)}
HOST_HOME_MOUNT="/home/${HOST_USER}/host_home"

if [[ -n "${IMAGE_OVERRIDE}" ]]; then
  IMAGE="${IMAGE_OVERRIDE}"
else
  IMAGE="${IMAGE_BASE}-${HOST_USER}:${IMAGE_TAG}"
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container ${NAME} already exists. Stop/remove it before starting a new one." >&2
  exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Image ${IMAGE} not found. Build user image first (e.g. ./build-user-image.sh)." >&2
  exit 1
fi

echo "Starting: name=${NAME}, image=${IMAGE}, resolution=${RESOLUTION}, DPI=${DPI}, host ports https=${HOST_PORT_SSL}->3001, http=${HOST_PORT_HTTP}->3000"

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
  --name "$NAME" \
  --hostname "${HOSTNAME_VAL}" \
  -e HOSTNAME="${HOSTNAME_VAL}" \
  -e HOST_HOSTNAME="${HOSTNAME_VAL}" \
  -e SHELL=/bin/bash \
  -p ${HOST_PORT_HTTP}:3000 \
  -p ${HOST_PORT_SSL}:3001 \
  -e DISPLAY=:1 \
  -e DPI="$DPI" \
  -e DISPLAY_WIDTH="$WIDTH" \
  -e DISPLAY_HEIGHT="$HEIGHT" \
  -e CUSTOM_RESOLUTION="$RESOLUTION" \
  -e USER_UID="${HOST_UID}" \
  -e USER_GID="${HOST_GID}" \
  -e USER_NAME="${HOST_USER}" \
  -e PUID="${HOST_UID}" \
  -e PGID="${HOST_GID}" \
  -v "${HOME}":"${HOST_HOME_MOUNT}":rw \
  ${SSL_FLAGS[@]+"${SSL_FLAGS[@]}"} \
  "$IMAGE"
