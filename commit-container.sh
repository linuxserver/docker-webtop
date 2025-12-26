#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
TARGET_IMAGE=${TARGET_IMAGE:-webtop-kde:latest}
TARGET_ARCH=${TARGET_ARCH:-}

usage() {
  echo "Usage: $0 [-n container_name] [-t target_image]"
  echo "  -n  container name to commit (default: ${NAME})"
  echo "  -t  target image:tag to create (default: ${TARGET_IMAGE})"
}

while getopts ":n:t:h" opt; do
  case "$opt" in
    n) NAME=$OPTARG ;;
    t) TARGET_IMAGE=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if ! docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container ${NAME} not found." >&2
  exit 1
fi

ARCH_FROM_LABEL=$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.architecture" }}' "$NAME" 2>/dev/null || true)
if [[ -z "${TARGET_ARCH}" ]]; then
  if [[ -n "${ARCH_FROM_LABEL}" ]]; then
    TARGET_ARCH="${ARCH_FROM_LABEL}"
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

if [[ "${TARGET_IMAGE}" == *:* ]]; then
  BASE="${TARGET_IMAGE%%:*}"
  TAG="${TARGET_IMAGE##*:}"
else
  BASE="${TARGET_IMAGE}"
  TAG="latest"
fi

# Default naming: <base>-<user>:<arch>-<tag>
FINAL_IMAGE="${BASE}-${HOST_USER}:${TARGET_ARCH}-${TAG}"

echo "Committing container ${NAME} -> ${FINAL_IMAGE}"
docker commit "$NAME" "$FINAL_IMAGE"
