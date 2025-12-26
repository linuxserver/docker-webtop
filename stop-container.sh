#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
REMOVE=0

usage() {
  echo "Usage: $0 [-n name] [--rm|-r]"
  echo "  -n  container name (default: ${NAME})"
  echo "  -r, --rm  remove container after stopping"
}

# parse short options
while getopts ":n:rh" opt; do
  case "$opt" in
    n) NAME=$OPTARG ;;
    r) REMOVE=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# parse long option --rm
shift $((OPTIND - 1))
for arg in "$@"; do
  case "$arg" in
    --rm) REMOVE=1 ;;
    *) echo "Unknown argument: $arg"; usage; exit 1 ;;
  esac
done

if ! docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container ${NAME} not found." >&2
  exit 1
fi

echo "Stopping container ${NAME}..."
docker stop "$NAME" >/dev/null
echo "Container ${NAME} stopped."

if [[ $REMOVE -eq 1 ]]; then
  echo "Removing container ${NAME}..."
  docker rm "$NAME" >/dev/null
  echo "Container ${NAME} removed."
fi
