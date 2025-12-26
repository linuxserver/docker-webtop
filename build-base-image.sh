#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"
DOCKERFILE_BASE="${FILES_DIR}/linuxserver-kde.base.dockerfile"

IMAGE_NAME=${IMAGE_NAME:-webtop-kde}
VERSION=${VERSION:-1.0.0}
ARCH_OVERRIDE=${ARCH_OVERRIDE:-}
PLATFORM_OVERRIDE=${PLATFORM_OVERRIDE:-}
NO_CACHE_FLAG=""

usage() {
  cat <<EOF
Usage: $0 [-a arch] [-i image] [-v version] [--no-cache]
  -a, --arch     Target arch (amd64 or arm64). Default: host arch
  -i, --image    Image name (default: ${IMAGE_NAME})
  -v, --version  Version tag (default: ${VERSION})
  -p, --platform Docker platform (e.g. linux/amd64 or linux/arm64). Default: derived from arch
  -n, --no-cache Build without using cache (passes --no-cache to docker buildx)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch) ARCH_OVERRIDE=$2; shift 2 ;;
    -i|--image) IMAGE_NAME=$2; shift 2 ;;
    -v|--version) VERSION=$2; shift 2 ;;
    -p|--platform) PLATFORM_OVERRIDE=$2; shift 2 ;;
    -n|--no-cache) NO_CACHE_FLAG="--no-cache"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

HOST_ARCH=$(uname -m)
PLATFORM_ARCH_HINT=""
if [[ -n "${PLATFORM_OVERRIDE}" ]]; then
  case "${PLATFORM_OVERRIDE}" in
    linux/amd64) PLATFORM_ARCH_HINT=amd64 ;;
    linux/arm64) PLATFORM_ARCH_HINT=arm64 ;;
    *) PLATFORM_ARCH_HINT="" ;;
  esac
fi

if [[ -n "${ARCH_OVERRIDE}" ]]; then
  ARCH_INPUT=${ARCH_OVERRIDE}
elif [[ -n "${PLATFORM_ARCH_HINT}" ]]; then
  ARCH_INPUT=${PLATFORM_ARCH_HINT}
else
  ARCH_INPUT=${HOST_ARCH}
fi

case "$ARCH_INPUT" in
  x86_64|amd64)
    TARGET_ARCH=amd64
    ALPINE_ARCH=x86_64
    UBUNTU_ARCH=amd64
    S6_OVERLAY_ARCH=x86_64
    SOURCES_LIST=sources.list
    LIBVA_DEB_URL="https://launchpad.net/ubuntu/+source/libva/2.22.0-3ubuntu2/+build/30591127/+files/libva2_2.22.0-3ubuntu2_amd64.deb"
    LIBVA_LIBDIR="/usr/lib/x86_64-linux-gnu"
    APT_EXTRA_PACKAGES="intel-media-va-driver xserver-xorg-video-intel"
    PLATFORM="linux/amd64"
    ;;
  aarch64|arm64)
    TARGET_ARCH=arm64
    ALPINE_ARCH=aarch64
    UBUNTU_ARCH=arm64
    S6_OVERLAY_ARCH=aarch64
    SOURCES_LIST=sources.list.arm
    LIBVA_DEB_URL="https://launchpad.net/ubuntu/+source/libva/2.22.0-3ubuntu2/+build/30591128/+files/libva2_2.22.0-3ubuntu2_arm64.deb"
    LIBVA_LIBDIR="/usr/lib/aarch64-linux-gnu"
    APT_EXTRA_PACKAGES=""
    PLATFORM="linux/arm64"
    ;;
  *)
  echo "Unsupported arch: $ARCH_INPUT" >&2
  exit 1
  ;;
esac

if [[ -n "${PLATFORM_OVERRIDE}" ]]; then
  PLATFORM=${PLATFORM_OVERRIDE}
  if [[ -n "${PLATFORM_ARCH_HINT}" && "${PLATFORM_ARCH_HINT}" != "${TARGET_ARCH}" ]]; then
    echo "Warning: platform (${PLATFORM_OVERRIDE}) and arch (${TARGET_ARCH}) differ; proceeding with platform override." >&2
  fi
fi

PROOT_ARCH=${PROOT_ARCH_OVERRIDE:-x86_64}

BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
LOG_FILE="${FILES_DIR}/build-${TARGET_ARCH}-${VERSION}.log"

echo "=========================================="
echo "Building ${IMAGE_NAME}:${TARGET_ARCH}-${VERSION}"
echo "Platform: ${PLATFORM}"
echo "Dockerfile: ${FILES_DIR}/linuxserver-kde.dockerfile"
echo "Build Date: ${BUILD_DATE}"
echo "=========================================="

REQUIRED_FILES=(
  "${DOCKERFILE_BASE}"
  "${FILES_DIR}/alpine-root"
  "${FILES_DIR}/ubuntu-root"
  "${FILES_DIR}/kde-root"
  "${FILES_DIR}/${SOURCES_LIST}"
  "${FILES_DIR}/patches/21-xvfb-dri3.patch"
)

for path in "${REQUIRED_FILES[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "Missing required file or directory: $path" >&2
    exit 1
  fi
done

set -o pipefail

docker buildx build \
  --platform "${PLATFORM}" \
  ${NO_CACHE_FLAG} \
  -f "${DOCKERFILE_BASE}" \
  --build-arg BUILD_DATE="${BUILD_DATE}" \
  --build-arg VERSION="${VERSION}" \
  --build-arg ALPINE_ARCH="${ALPINE_ARCH}" \
  --build-arg UBUNTU_ARCH="${UBUNTU_ARCH}" \
  --build-arg S6_OVERLAY_ARCH="${S6_OVERLAY_ARCH}" \
  --build-arg SOURCES_LIST="${SOURCES_LIST}" \
  --build-arg APT_EXTRA_PACKAGES="${APT_EXTRA_PACKAGES}" \
  --build-arg LIBVA_DEB_URL="${LIBVA_DEB_URL}" \
  --build-arg LIBVA_LIBDIR="${LIBVA_LIBDIR}" \
  --build-arg PROOT_ARCH="${PROOT_ARCH}" \
  --progress=plain \
  --load \
  -t ${IMAGE_NAME}:base-${TARGET_ARCH}-${VERSION} \
  -t ${IMAGE_NAME}:base-${TARGET_ARCH}-latest \
  -t ${IMAGE_NAME}:base-latest \
  "${FILES_DIR}" 2>&1 | tee "${LOG_FILE}"

BUILD_STATUS=${PIPESTATUS[0]}
if [ $BUILD_STATUS -eq 0 ]; then
  echo "Build successful."
else
  echo "Build failed. See ${LOG_FILE}"
  exit 1
fi
