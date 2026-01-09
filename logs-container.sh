#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${USER:-$(whoami)}
NAME=${CONTAINER_NAME:-linuxserver-kde-${HOST_USER}}
LINES=${LINES:-100}
FOLLOW=${FOLLOW:-false}

usage() {
  cat <<EOF
Usage: $0 [-n name] [-l lines] [-f]
  -n  container name (default: ${NAME})
  -l  number of lines to show (default: ${LINES})
  -f  follow log output (like tail -f)

Environment variables:
  LINES   number of lines to show (default: 100)
  FOLLOW  set to 'true' to follow logs

Examples:
  $0                    # Show last 100 lines
  $0 -l 500             # Show last 500 lines
  $0 -f                 # Follow logs (Ctrl+C to stop)
  FOLLOW=true $0        # Follow logs using env var
EOF
}

while getopts ":n:l:fh" opt; do
  case "$opt" in
    n) NAME=$OPTARG ;;
    l) LINES=$OPTARG ;;
    f) FOLLOW=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if ! docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container ${NAME} not found." >&2
  exit 1
fi

DOCKER_ARGS=("--tail" "${LINES}")

if [[ "${FOLLOW}" == "true" ]]; then
  DOCKER_ARGS+=("-f")
  echo "Following logs for ${NAME} (Ctrl+C to stop)..."
else
  echo "Showing last ${LINES} lines of logs for ${NAME}..."
fi

docker logs "${DOCKER_ARGS[@]}" "$NAME"
