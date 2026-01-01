#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
TARGET_IMAGE=${TARGET_IMAGE:-webtop-kde}
TARGET_ARCH=${TARGET_ARCH:-}
TARGET_VERSION=${TARGET_VERSION:-1.0.0}

usage() {
  echo "Usage: $0 [-n container_name] [-t target_image_base] [-v version]"
  echo "  -n  container name to commit (default: ${NAME})"
  echo "  -t  target image base (no arch/tag), e.g. webtop-kde (default: ${TARGET_IMAGE})"
  echo "  -v  version tag to use (default: ${TARGET_VERSION})"
}

while getopts ":n:t:v:h" opt; do
  case "$opt" in
    n) NAME=$OPTARG ;;
    t) TARGET_IMAGE=$OPTARG ;;
    v) TARGET_VERSION=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if ! docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container ${NAME} not found." >&2
  exit 1
fi

ARCH_FROM_LABEL=$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.architecture" }}' "$NAME" 2>/dev/null || true)
IMAGE_FROM_CONFIG=$(docker inspect --format '{{ .Config.Image }}' "$NAME" 2>/dev/null || true)

detect_arch_from_image_name() {
  # Expect patterns like webtop-kde-<user>-amd64:1.0.0 or webtop-kde-<user>-arm64:tag
  local img="$1"
  local repo="${img%%:*}"
  local suffix="${repo##*-}"
  case "${suffix}" in
    amd64|x86_64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) echo "" ;;
  esac
}

if [[ -z "${TARGET_ARCH}" ]]; then
  if [[ -n "${ARCH_FROM_LABEL}" ]]; then
    TARGET_ARCH="${ARCH_FROM_LABEL}"
  elif [[ -n "${IMAGE_FROM_CONFIG}" ]]; then
    TARGET_ARCH="$(detect_arch_from_image_name "${IMAGE_FROM_CONFIG}")"
  else
    TARGET_ARCH=$(docker inspect "$NAME" 2>/dev/null \
      | python3 -c 'import sys,json; data=json.load(sys.stdin); print(data[0].get("Architecture",""))' || true)
  fi
fi
if [[ -z "${TARGET_ARCH}" ]]; then
  HOST_ARCH=$(uname -m)
  case "${HOST_ARCH}" in
    x86_64|amd64) TARGET_ARCH=amd64 ;;
    aarch64|arm64) TARGET_ARCH=arm64 ;;
    *) echo "Unable to detect container architecture; set TARGET_ARCH env." >&2; exit 1 ;;
  esac
fi

# Default naming: <base>-<user>-<arch>:<version>
FINAL_IMAGE="${TARGET_IMAGE}-${HOST_USER}-${TARGET_ARCH}:${TARGET_VERSION}"

echo "Committing container ${NAME} -> ${FINAL_IMAGE}"
docker commit "$NAME" "$FINAL_IMAGE"
