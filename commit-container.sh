#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
TARGET_IMAGE=${TARGET_IMAGE:-webtop-kde}
TARGET_ARCH=${TARGET_ARCH:-}
TARGET_VERSION=${TARGET_VERSION:-1.0.0}
UBUNTU_VERSION=${UBUNTU_VERSION:-}
RESTART=${RESTART:-false}

usage() {
  cat <<EOF
Usage: $0 [-n container_name] [-t target_image_base] [-v version] [-u ubuntu_version] [-r]
  -n  container name to commit (default: ${NAME})
  -t  target image base (no arch/tag), e.g. webtop-kde (default: ${TARGET_IMAGE})
  -v  version tag to use (default: ${TARGET_VERSION})
  -u, --ubuntu  Ubuntu version (22.04 or 24.04). Auto-detected if not specified
  -r  restart container after commit

Environment variables:
  RESTART  set to 'true' to restart container after commit

Examples:
  $0                    # Commit container (auto-detect Ubuntu version)
  $0 -r                 # Commit and restart container
  $0 -v 2.0.0           # Commit with specific version tag
  $0 -u 22.04           # Commit with specific Ubuntu version
EOF
}

while getopts ":n:t:v:u:rh-:" opt; do
  case "$opt" in
    n) NAME=$OPTARG ;;
    t) TARGET_IMAGE=$OPTARG ;;
    v) TARGET_VERSION=$OPTARG ;;
    u) UBUNTU_VERSION=$OPTARG ;;
    r) RESTART=true ;;
    h) usage; exit 0 ;;
    -)
      case "${OPTARG}" in
        ubuntu) UBUNTU_VERSION="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
        *) echo "Unknown option: --${OPTARG}" >&2; usage; exit 1 ;;
      esac
      ;;
    *) usage; exit 1 ;;
  esac
done

if ! docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container ${NAME} not found." >&2
  exit 1
fi

ARCH_FROM_LABEL=$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.architecture" }}' "$NAME" 2>/dev/null || true)
IMAGE_FROM_CONFIG=$(docker inspect --format '{{ .Config.Image }}' "$NAME" 2>/dev/null || true)
IMAGE_ID_FROM_CONTAINER=$(docker inspect --format '{{ .Image }}' "$NAME" 2>/dev/null || true)

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
  if [[ -n "${IMAGE_ID_FROM_CONTAINER}" ]]; then
    TARGET_ARCH=$(docker image inspect --format '{{ .Architecture }}' "${IMAGE_ID_FROM_CONTAINER}" 2>/dev/null || true)
  fi
  if [[ -z "${TARGET_ARCH}" && -n "${ARCH_FROM_LABEL}" ]]; then
    TARGET_ARCH="${ARCH_FROM_LABEL}"
  elif [[ -z "${TARGET_ARCH}" && -n "${IMAGE_FROM_CONFIG}" ]]; then
    TARGET_ARCH="$(detect_arch_from_image_name "${IMAGE_FROM_CONFIG}")"
  elif [[ -z "${TARGET_ARCH}" ]]; then
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

# Auto-detect Ubuntu version from image name if not specified
if [[ -z "${UBUNTU_VERSION}" && -n "${IMAGE_FROM_CONFIG}" ]]; then
  # Try to extract Ubuntu version from image name pattern: ...-u22.04:... or ...-u24.04:...
  if [[ "${IMAGE_FROM_CONFIG}" =~ -u([0-9]+\.[0-9]+) ]]; then
    UBUNTU_VERSION="${BASH_REMATCH[1]}"
    echo "Auto-detected Ubuntu version: ${UBUNTU_VERSION}"
  fi
fi

# Default to 24.04 if still not set
if [[ -z "${UBUNTU_VERSION}" ]]; then
  UBUNTU_VERSION="24.04"
  echo "Ubuntu version not detected, defaulting to ${UBUNTU_VERSION}"
fi

# Final naming: <base>-<user>-<arch>-u<ubuntu_ver>:<version>
FINAL_IMAGE="${TARGET_IMAGE}-${HOST_USER}-${TARGET_ARCH}-u${UBUNTU_VERSION}:${TARGET_VERSION}"

echo "Committing container ${NAME} -> ${FINAL_IMAGE}"
docker commit "$NAME" "$FINAL_IMAGE"

if [[ "${RESTART}" == "true" ]]; then
  echo "Restarting container ${NAME}..."
  docker restart "$NAME" >/dev/null
  echo "Container ${NAME} restarted."
fi

echo "Done."
