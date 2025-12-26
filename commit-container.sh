#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
TARGET_IMAGE=${TARGET_IMAGE:-webtop-kde:custom}

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

echo "Committing container ${NAME} -> ${TARGET_IMAGE}"
docker commit "$NAME" "$TARGET_IMAGE"
