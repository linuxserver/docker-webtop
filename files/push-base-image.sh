#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME=${IMAGE_NAME:-ghcr.io/tatsuyai713/webtop-kde}
VERSION=${VERSION:-1.0.0}
UBUNTU_VERSION=${UBUNTU_VERSION:-24.04}
ARCH_OVERRIDE=${ARCH_OVERRIDE:-}
PLATFORM_OVERRIDE=${PLATFORM_OVERRIDE:-}

usage() {
  cat <<EOF
Usage: $0 [-a arch] [-i image] [-v version] [-u ubuntu_version] [-p platform]
  -a, --arch     Target arch (amd64 or arm64). Default: host arch
  -i, --image    Image name (default: ${IMAGE_NAME})
  -v, --version  Version tag (default: ${VERSION})
  -u, --ubuntu   Ubuntu version (22.04 or 24.04). Default: ${UBUNTU_VERSION}
  -p, --platform Docker platform (e.g. linux/amd64 or linux/arm64). Default: derived from arch
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch) ARCH_OVERRIDE=$2; shift 2 ;;
    -i|--image) IMAGE_NAME=$2; shift 2 ;;
    -v|--version) VERSION=$2; shift 2 ;;
    -u|--ubuntu) UBUNTU_VERSION=$2; shift 2 ;;
    -p|--platform) PLATFORM_OVERRIDE=$2; shift 2 ;;
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
  TARGET_ARCH=${ARCH_OVERRIDE}
elif [[ -n "${PLATFORM_ARCH_HINT}" ]]; then
  TARGET_ARCH=${PLATFORM_ARCH_HINT}
else
  TARGET_ARCH=${HOST_ARCH}
fi

case "${TARGET_ARCH}" in
  x86_64|amd64) TARGET_ARCH=amd64 ;;
  aarch64|arm64) TARGET_ARCH=arm64 ;;
  *) echo "Unsupported arch: ${TARGET_ARCH}. Use amd64 or arm64." >&2; exit 1 ;;
esac

IMAGE_TAG="${IMAGE_NAME}-base-${TARGET_ARCH}-u${UBUNTU_VERSION}:${VERSION}"

if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_TAG}$"; then
  echo "Local image not found: ${IMAGE_TAG}" >&2
  echo "Build it first (e.g. ./files/build-base-image.sh -a ${TARGET_ARCH} --ubuntu ${UBUNTU_VERSION} -v ${VERSION})." >&2
  exit 1
fi

echo "Pushing ${IMAGE_TAG}"
echo "If you haven't logged in, run: docker login ghcr.io"
docker push "${IMAGE_TAG}"
