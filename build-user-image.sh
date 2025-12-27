#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"
DOCKERFILE_USER="${FILES_DIR}/linuxserver-kde.user.dockerfile"

HOST_ARCH=$(uname -m)
VERSION=${VERSION:-1.0.0}
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
LANG_ARG="en_US.UTF-8"
LANGUAGE_ARG="en_US:en"
NO_CACHE_FLAG=""

usage() {
  cat <<EOF
Usage: $0 [-b base_image] [-i base_image_name] [-u user] [-U uid] [-G gid] [-a arch] [-p platform] [-l language] [-v version]
  -b, --base       Base image tag (required; expected: <name>-base-<arch>:<version>)
  -i, --image      Base image name (default: ${IMAGE_NAME_BASE})
  -u, --user       Username to bake in (default: current user ${USER_NAME})
  -U, --uid        UID to use (default: host uid for user)
  -G, --gid        GID to use (default: host gid for user)
  -a, --arch       Arch hint (amd64/arm64) to pick base tag
  -p, --platform   Platform override for buildx (e.g. linux/arm64)
  -l, --language   Language pack to install (en or ja). Default: ${USER_LANGUAGE}
  -v, --version    Version tag to use (default: ${VERSION})
  -n, --no-cache   Build without cache (passes --no-cache to buildx)
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
    -v|--version) VERSION=$2; shift 2 ;;
    -n|--no-cache) NO_CACHE_FLAG="--no-cache"; shift ;;
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
  # macOS bash (3.x) lacks mapfile; use a portable read loop
  BASE_CANDIDATES=()
  while IFS= read -r line; do
    BASE_CANDIDATES+=("$line")
  done < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep "^${IMAGE_NAME_BASE}-base-${TARGET_ARCH}:" || true)

  if [[ ${#BASE_CANDIDATES[@]} -eq 0 ]]; then
    echo "BASE_IMAGE not provided and no local base found matching ${IMAGE_NAME_BASE}-base-${TARGET_ARCH}:<tag>. Pass -b/--base." >&2
    exit 1
  fi
  for candidate in "${BASE_CANDIDATES[@]}"; do
    if [[ "${candidate}" != *":latest" ]]; then
      BASE_IMAGE="${candidate}"
      break
    fi
  done
  if [[ -z "${BASE_IMAGE}" ]]; then
    BASE_IMAGE="${BASE_CANDIDATES[0]}"
  fi
  echo "Using detected base image: ${BASE_IMAGE}"
fi

if [[ "${BASE_IMAGE}" == *":latest" ]]; then
  echo "Warning: BASE_IMAGE uses ':latest' (${BASE_IMAGE}); consider pinning a version." >&2
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
echo "Version tag: ${VERSION}"

if ! docker image inspect "${BASE_IMAGE}" >/dev/null 2>&1; then
  echo "Base image ${BASE_IMAGE} not found locally. Build it first (e.g. ./build-base-image.sh -a ${TARGET_ARCH} -v ${VERSION})." >&2
  exit 1
fi

if [[ "${USER_LANGUAGE}" == "ja" ]]; then
  LANG_ARG="ja_JP.UTF-8"
  LANGUAGE_ARG="ja_JP:ja"
fi

if [[ ! -f "${DOCKERFILE_USER}" ]]; then
  echo "User Dockerfile not found: ${DOCKERFILE_USER}" >&2
  exit 1
fi

docker buildx build \
  --platform "${PLATFORM}" \
  ${NO_CACHE_FLAG} \
  -f "${DOCKERFILE_USER}" \
  --build-arg BASE_IMAGE="${BASE_IMAGE}" \
  --build-arg USER_NAME="${USER_NAME}" \
  --build-arg USER_UID="${USER_UID}" \
  --build-arg USER_GID="${USER_GID}" \
  --build-arg USER_PASSWORD="${USER_PASSWORD}" \
  --build-arg USER_LANGUAGE="${USER_LANGUAGE}" \
  --build-arg USER_LANG_ENV="${LANG_ARG}" \
  --build-arg USER_LANGUAGE_ENV="${LANGUAGE_ARG}" \
  --build-arg HOST_HOSTNAME="${HOST_HOSTNAME_DEFAULT}" \
  --progress=plain \
  --load \
  -t "${IMAGE_NAME_BASE}-${USER_NAME}-${TARGET_ARCH}:${VERSION}" \
  "${FILES_DIR}"
