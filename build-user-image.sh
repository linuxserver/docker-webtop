#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"
DOCKERFILE_USER="${FILES_DIR}/linuxserver-kde.user.dockerfile"

HOST_ARCH=$(uname -m)
USER_NAME=${USER:-$(whoami)}
USER_UID=${USER_UID_OVERRIDE:-$(id -u "${USER_NAME}")}
USER_GID=${USER_GID_OVERRIDE:-$(id -g "${USER_NAME}")}
BASE_IMAGE=${BASE_IMAGE:-}
IMAGE_NAME_BASE=${IMAGE_NAME:-webtop-kde}
TARGET_ARCH=${ARCH_OVERRIDE:-}
PLATFORM_OVERRIDE=${PLATFORM_OVERRIDE:-}
USER_PASSWORD=${USER_PASSWORD:-}
USER_LANGUAGE=${USER_LANGUAGE:-en}
HOST_HOSTNAME_DEFAULT="Docker-$(hostname)"
PLATFORM_ARCH_HINT=""

usage() {
  cat <<EOF
Usage: $0 [-b base_image] [-i base_image_name] [-u user] [-U uid] [-G gid] [-a arch] [-p platform] [-l language]
  -b, --base       Base image tag (default: derived from arch, e.g. webtop-kde:base-amd64-latest)
  -i, --image      Base image name (default: ${IMAGE_NAME_BASE})
  -u, --user       Username to bake in (default: current user ${USER_NAME})
  -U, --uid        UID to use (default: host uid for user)
  -G, --gid        GID to use (default: host gid for user)
  -a, --arch       Arch hint (amd64/arm64) to pick base tag
  -p, --platform   Platform override for buildx (e.g. linux/arm64)
  -l, --language   Language pack to install (en or ja). Default: ${USER_LANGUAGE}
  (env) USER_PASSWORD  Password to set for the user (will prompt if empty)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--base) BASE_IMAGE=$2; shift 2 ;;
    -i|--image) IMAGE_NAME_BASE=$2; shift 2 ;;
    -u|--user) USER_NAME=$2; shift 2 ;;
    -U|--uid) USER_UID=$2; shift 2 ;;
    -G|--gid) USER_GID=$2; shift 2 ;;
    -a|--arch) TARGET_ARCH=$2; shift 2 ;;
    -p|--platform) PLATFORM_OVERRIDE=$2; shift 2 ;;
    -l|--language) USER_LANGUAGE=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -n "${PLATFORM_OVERRIDE}" ]]; then
  case "${PLATFORM_OVERRIDE}" in
    linux/amd64) PLATFORM_ARCH_HINT=amd64 ;;
    linux/arm64) PLATFORM_ARCH_HINT=arm64 ;;
    *) PLATFORM_ARCH_HINT="" ;;
  esac
fi

if [[ -z "${TARGET_ARCH}" ]]; then
  if [[ -n "${PLATFORM_ARCH_HINT}" ]]; then
    TARGET_ARCH="${PLATFORM_ARCH_HINT}"
  else
    case "${HOST_ARCH}" in
      x86_64|amd64) TARGET_ARCH=amd64 ;;
      aarch64|arm64) TARGET_ARCH=arm64 ;;
      *) echo "Unsupported host arch: ${HOST_ARCH}. Please pass -a." >&2; exit 1 ;;
    esac
  fi
fi

if [[ -z "${BASE_IMAGE}" ]]; then
  BASE_IMAGE="${IMAGE_NAME_BASE}:base-${TARGET_ARCH}-latest"
fi

PLATFORM="linux/${TARGET_ARCH}"
if [[ -n "${PLATFORM_OVERRIDE}" ]]; then
  PLATFORM="${PLATFORM_OVERRIDE}"
fi

if [[ -z "${USER_PASSWORD}" ]]; then
  read -s -p "Enter password for user ${USER_NAME}: " USER_PASSWORD; echo
  read -s -p "Confirm password: " USER_PASSWORD_CONFIRM; echo
  if [[ "${USER_PASSWORD}" != "${USER_PASSWORD_CONFIRM}" ]]; then
    echo "Password mismatch." >&2
    exit 1
  fi
fi

echo "Building user image from ${BASE_IMAGE}"
echo "User: ${USER_NAME} (${USER_UID}:${USER_GID})"
echo "Target arch: ${TARGET_ARCH}, platform: ${PLATFORM}"
echo "Language: ${USER_LANGUAGE}"

if [[ ! -f "${DOCKERFILE_USER}" ]]; then
  echo "User Dockerfile not found: ${DOCKERFILE_USER}" >&2
  exit 1
fi

docker buildx build \
  --platform "${PLATFORM}" \
  -f "${DOCKERFILE_USER}" \
  --build-arg BASE_IMAGE="${BASE_IMAGE}" \
  --build-arg USER_NAME="${USER_NAME}" \
  --build-arg USER_UID="${USER_UID}" \
  --build-arg USER_GID="${USER_GID}" \
  --build-arg USER_PASSWORD="${USER_PASSWORD}" \
  --build-arg USER_LANGUAGE="${USER_LANGUAGE}" \
  --build-arg HOST_HOSTNAME="${HOST_HOSTNAME_DEFAULT}" \
  --progress=plain \
  --load \
  -t "${IMAGE_NAME_BASE}-${USER_NAME}:${TARGET_ARCH}-latest" \
  -t "${IMAGE_NAME_BASE}-${USER_NAME}:latest" \
  "${FILES_DIR}"
