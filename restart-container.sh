#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}

usage() {
  cat <<EOF
Usage: $0 [-n name]
  -n  container name (default: ${NAME})

Restarts the container. If the container is not running, it will be started.
EOF
}

while getopts ":n:h" opt; do
  case "$opt" in
    n) NAME=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if ! docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container ${NAME} not found." >&2
  echo "Use start-container.sh to create a new container." >&2
  exit 1
fi

# Check if container is running
if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Restarting container ${NAME}..."
  docker restart "$NAME" >/dev/null
  echo "Container ${NAME} restarted."
else
  echo "Container ${NAME} is stopped. Starting..."
  docker start "$NAME" >/dev/null
  echo "Container ${NAME} started."
fi
