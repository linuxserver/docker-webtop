#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
WORKDIR="/home/${HOST_USER}"

usage() {
  echo "Usage: $0 [-n name]"
  echo "  -n  container name (default: ${NAME})"
}

while getopts ":n:h" opt; do
  case "$opt" in
    n) NAME=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container ${NAME} is not running." >&2
  exit 1
fi

HOST_UID=$(id -u "${HOST_USER}")
HOST_GID=$(id -g "${HOST_USER}")

# Use username so container supplemental groups (sudo, docker, etc.) are preserved
if ! docker exec "$NAME" id "${HOST_USER}" >/dev/null 2>&1; then
  echo "User ${HOST_USER} not found in container. Falling back to uid:gid." >&2
  exec docker exec -it \
    -u "${HOST_UID}:${HOST_GID}" \
    -e USER="${HOST_USER}" \
    -e HOME="/home/${HOST_USER}" \
    -w "${WORKDIR}" \
    "$NAME" bash -l
fi

exec docker exec -it \
  --user "${HOST_USER}" \
  -e USER="${HOST_USER}" \
  -e HOME="/home/${HOST_USER}" \
  -w "${WORKDIR}" \
  "$NAME" bash -l
