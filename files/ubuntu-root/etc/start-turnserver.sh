#!/bin/bash
set -e
turnserver \
    --verbose \
    --listening-ip="0.0.0.0" \
    --listening-ip="::" \
    --listening-port="${TURN_LISTENING_PORT:-3478}" \
    --realm="${TURN_REALM:-example.com}" \
    --external-ip="${TURN_EXTERNAL_IP:-$(dig -4 TXT +short @ns1.google.com o-o.myaddr.l.google.com 2>/dev/null | { read output; if [ -z "$output" ] || echo "$output" | grep -q '^;;'; then exit 1; else echo "$(echo $output | sed 's,\",,g')"; fi } || dig -6 TXT +short @ns1.google.com o-o.myaddr.l.google.com 2>/dev/null | { read output; if [ -z "$output" ] || echo "$output" | grep -q '^;;'; then exit 1; else echo "[$(echo $output | sed 's,\",,g')]"; fi } || hostname -I 2>/dev/null | awk '{print $1; exit}' || echo '127.0.0.1')}" \
    --min-port="${TURN_MIN_PORT:-49152}" \
    --max-port="${TURN_MAX_PORT:-65535}" \
    --channel-lifetime="${TURN_CHANNEL_LIFETIME:--1}" \
    --lt-cred-mech \
    --user="selkies:${TURN_RANDOM_PASSWORD:-$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)}" \
    --no-cli \
    --cli-password="${TURN_RANDOM_PASSWORD:-$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)}" \
    --userdb="${XDG_RUNTIME_DIR:-/tmp}/turnserver-turndb" \
    --pidfile="${XDG_RUNTIME_DIR:-/tmp}/turnserver.pid" \
    --log-file="stdout" \
    --allow-loopback-peers \
    ${TURN_EXTRA_ARGS} $@
