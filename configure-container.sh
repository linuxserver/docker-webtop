#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Container configuration wizard
# Saves container settings to a YAML config file for use by start-container.sh
#
# Usage: ./configure-container.sh [-n name] [--config file]
#
# Config files are stored under configs/<name>.yml by default.
# Re-run this script at any time to update the configuration.
# ==============================================================================

HOST_USER=${USER:-$(whoami)}

NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
IMAGE_BASE=${IMAGE_BASE:-webtop-kde}
IMAGE_VERSION_DEFAULT=${IMAGE_VERSION:-1.1.0}
UBUNTU_VERSION=${UBUNTU_VERSION:-24.04}
RESOLUTION=${RESOLUTION:-1920x1080}
DPI=${DPI:-96}
STREAM_SCALE=${STREAM_SCALE:-1.0}
TIMEZONE=${TIMEZONE:-UTC}
SHM_SIZE=${SHM_SIZE:-4g}
SHM_MODE=${SHM_MODE:-1777}
SHM_NOEXEC=${SHM_NOEXEC:-true}
ENCODER=${ENCODER:-software}
FRAMERATE=${FRAMERATE:-30}
GPU_ALL=false
GPU_NUMS=""
DOCKER_GPUS=""
DRI_NODE=""
DOCKER_MODE=${DOCKER_MODE:-dind}
SSL_DIR=${SSL_DIR:-}

HOST_ARCH_RAW=$(uname -m)
case "${HOST_ARCH_RAW}" in
  x86_64|amd64) DETECTED_ARCH=amd64 ;;
  aarch64|arm64) DETECTED_ARCH=arm64 ;;
  *) DETECTED_ARCH="${HOST_ARCH_RAW}" ;;
esac
TARGET_ARCH="${DETECTED_ARCH}"

HOST_IS_MAC=false
if [[ "$(uname -s)" == "Darwin" ]]; then
  HOST_IS_MAC=true
fi
IS_MAC=${IS_MAC:-${HOST_IS_MAC}}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_INTERACTIVE_SCRIPT="${SCRIPT_DIR}/interactive-common.sh"
if [[ ! -f "${COMMON_INTERACTIVE_SCRIPT}" ]]; then
  echo "Error: ${COMMON_INTERACTIVE_SCRIPT} not found." >&2
  exit 1
fi
# shellcheck source=/dev/null
. "${COMMON_INTERACTIVE_SCRIPT}"

CONFIG_DIR="${SCRIPT_DIR}/configs"
CONFIG_FILE=""

usage() {
  cat <<EOF
Usage: $0 [-n name] [--config file]
Interactive configuration wizard. Saves settings to a YAML file for start-container.sh.
  -n       container name (default: ${NAME})
  --config path to config file (default: ${CONFIG_DIR}/<name>.yml)
EOF
}

# ------------------------------------------------------------------------------
# Simple flat-YAML helpers (no external dependencies)
# ------------------------------------------------------------------------------
yaml_get() {
  local file="$1" key="$2"
  grep -m1 "^${key}:" "${file}" 2>/dev/null \
    | sed 's/^[^:]*:[[:space:]]*//' \
    | sed 's/^"//; s/"$//' \
    || true
}

load_yaml_config() {
  local file="$1" val
  val=$(yaml_get "${file}" "container_name"); [[ -n "${val}" ]] && NAME="${val}"
  val=$(yaml_get "${file}" "image_base");     [[ -n "${val}" ]] && IMAGE_BASE="${val}"
  val=$(yaml_get "${file}" "image_version");  [[ -n "${val}" ]] && IMAGE_VERSION_DEFAULT="${val}"
  val=$(yaml_get "${file}" "ubuntu_version"); [[ -n "${val}" ]] && UBUNTU_VERSION="${val}"
  val=$(yaml_get "${file}" "arch");           [[ -n "${val}" ]] && TARGET_ARCH="${val}"
  val=$(yaml_get "${file}" "resolution");     [[ -n "${val}" ]] && RESOLUTION="${val}"
  val=$(yaml_get "${file}" "dpi");            [[ -n "${val}" ]] && DPI="${val}"
  val=$(yaml_get "${file}" "stream_scale");   [[ -n "${val}" ]] && STREAM_SCALE="${val}"
  val=$(yaml_get "${file}" "framerate");      [[ -n "${val}" ]] && FRAMERATE="${val}"
  val=$(yaml_get "${file}" "timezone");       [[ -n "${val}" ]] && TIMEZONE="${val}"
  val=$(yaml_get "${file}" "encoder");        [[ -n "${val}" ]] && ENCODER="${val}"
  val=$(yaml_get "${file}" "docker_gpus");    DOCKER_GPUS="${val}"
  val=$(yaml_get "${file}" "dri_node");       DRI_NODE="${val}"
  val=$(yaml_get "${file}" "docker_mode");    [[ -n "${val}" ]] && DOCKER_MODE="${val}"
  val=$(yaml_get "${file}" "ssl_dir");        SSL_DIR="${val}"
  val=$(yaml_get "${file}" "is_mac");         [[ -n "${val}" ]] && IS_MAC="${val}"
  val=$(yaml_get "${file}" "shm_size");       [[ -n "${val}" ]] && SHM_SIZE="${val}"
  val=$(yaml_get "${file}" "shm_mode");       [[ -n "${val}" ]] && SHM_MODE="${val}"
  val=$(yaml_get "${file}" "shm_noexec");     [[ -n "${val}" ]] && SHM_NOEXEC="${val}"
}

# ------------------------------------------------------------------------------
# Parse args
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) NAME=$2; shift 2 ;;
    --config) CONFIG_FILE=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "${CONFIG_FILE}" ]]; then
  CONFIG_FILE="${CONFIG_DIR}/${NAME}.yml"
fi

# Pre-load existing config values as defaults
if [[ -f "${CONFIG_FILE}" ]]; then
  echo "Loading existing configuration from: ${CONFIG_FILE}"
  load_yaml_config "${CONFIG_FILE}"
fi

# ------------------------------------------------------------------------------
# Interactive setup
# ------------------------------------------------------------------------------
CONTAINER_NAME="${NAME}"
shared_apply_locale_from_timezone "${TIMEZONE}"

echo ""
echo "========================================"
echo " Container Configuration Wizard"
echo "========================================"
echo ""

shared_collect_interactive_settings
NAME="${CONTAINER_NAME}"

# ------------------------------------------------------------------------------
# Save to YAML
# ------------------------------------------------------------------------------
mkdir -p "$(dirname "${CONFIG_FILE}")"
cat > "${CONFIG_FILE}" <<ENDOFYAML
# linuxserver-kde container configuration
# Generated: $(date)
container_name: "${NAME}"
image_base: "${IMAGE_BASE}"
image_version: "${IMAGE_VERSION_DEFAULT}"
ubuntu_version: "${UBUNTU_VERSION}"
arch: "${TARGET_ARCH}"
resolution: "${RESOLUTION}"
dpi: "${DPI}"
stream_scale: "${STREAM_SCALE}"
framerate: "${FRAMERATE}"
timezone: "${TIMEZONE}"
encoder: "${ENCODER}"
docker_gpus: "${DOCKER_GPUS:-}"
dri_node: "${DRI_NODE:-}"
docker_mode: "${DOCKER_MODE}"
ssl_dir: "${SSL_DIR:-}"
is_mac: "${IS_MAC}"
shm_size: "${SHM_SIZE}"
shm_mode: "${SHM_MODE}"
shm_noexec: "${SHM_NOEXEC}"
ENDOFYAML

echo ""
echo "Configuration saved to: ${CONFIG_FILE}"
echo ""
echo "To start the container:  ./start-container.sh"
echo "To reconfigure and start: ./start-container.sh --reconfigure"
