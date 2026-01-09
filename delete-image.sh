#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
IMAGE_BASE=${IMAGE_BASE:-webtop-kde}
IMAGE_VERSION=${IMAGE_VERSION:-1.0.0}
UBUNTU_VERSION=${UBUNTU_VERSION:-24.04}
IMAGE_NAME=${IMAGE_NAME:-}
FORCE=${FORCE:-false}
DELETE_BASE=${DELETE_BASE:-false}

# Detect architecture
HOST_ARCH_RAW=$(uname -m)
case "${HOST_ARCH_RAW}" in
  x86_64|amd64) DETECTED_ARCH=amd64 ;;
  aarch64|arm64) DETECTED_ARCH=arm64 ;;
  *) DETECTED_ARCH="${HOST_ARCH_RAW}" ;;
esac
TARGET_ARCH=${TARGET_ARCH:-${DETECTED_ARCH}}

usage() {
  cat <<EOF
Usage: $0 [-i image_name] [-u ubuntu_version] [-b] [-f] [-h]
  -i  full image name to delete (overrides auto-detection)
  -u, --ubuntu  Ubuntu version (22.04 or 24.04). Default: ${UBUNTU_VERSION}
  -b  also delete base image
  -f  force delete (remove dependent containers first)
  -h  show this help

Default image: ${IMAGE_BASE}-${HOST_USER}-${TARGET_ARCH}-u${UBUNTU_VERSION}:${IMAGE_VERSION}

Environment variables:
  IMAGE_BASE      image base name (default: webtop-kde)
  IMAGE_VERSION   image version (default: 1.0.0)
  UBUNTU_VERSION  Ubuntu version (default: 24.04)
  IMAGE_NAME      full image name (overrides auto-detection)
  TARGET_ARCH     architecture (default: auto-detect)
  FORCE           set to 'true' to force delete
  DELETE_BASE     set to 'true' to also delete base image

Examples:
  $0                    # Delete user image
  $0 -u 22.04           # Delete Ubuntu 22.04 user image
  $0 -b                 # Delete user and base images
  $0 -f                 # Force delete (remove containers first)
  $0 -i myimage:1.0     # Delete specific image
EOF
}

while getopts ":i:u:bfh-:" opt; do
  case "$opt" in
    i) IMAGE_NAME=$OPTARG ;;
    u) UBUNTU_VERSION=$OPTARG ;;
    b) DELETE_BASE=true ;;
    f) FORCE=true ;;
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

# Determine image name
if [[ -z "${IMAGE_NAME}" ]]; then
  IMAGE_NAME="${IMAGE_BASE}-${HOST_USER}-${TARGET_ARCH}-u${UBUNTU_VERSION}:${IMAGE_VERSION}"
fi

delete_image() {
  local img="$1"
  local force_flag="$2"
  
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    echo "Image ${img} not found."
    return 0
  fi
  
  # Check for dependent containers
  local containers
  containers=$(docker ps -a --filter "ancestor=${img}" --format '{{.Names}}' 2>/dev/null || true)
  
  if [[ -n "${containers}" ]]; then
    echo "Found containers using ${img}:"
    echo "${containers}" | sed 's/^/  - /'
    
    if [[ "${force_flag}" == "true" ]]; then
      echo "Force mode: Removing dependent containers..."
      echo "${containers}" | xargs -r docker rm -f
    else
      echo "Error: Cannot delete image with dependent containers."
      echo "Either remove containers first, or use -f to force delete."
      return 1
    fi
  fi
  
  echo "Deleting image ${img}..."
  docker rmi "$img"
  echo "Image ${img} deleted."
}

# Delete user image
echo "=== Deleting User Image ==="
delete_image "${IMAGE_NAME}" "${FORCE}"

# Delete base image if requested
if [[ "${DELETE_BASE}" == "true" ]]; then
  BASE_IMAGE="${IMAGE_BASE}-base-${TARGET_ARCH}-u${UBUNTU_VERSION}:${IMAGE_VERSION}"
  echo ""
  echo "=== Deleting Base Image ==="
  delete_image "${BASE_IMAGE}" "${FORCE}"
fi

echo ""
echo "Done."
