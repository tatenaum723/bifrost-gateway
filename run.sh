#!/usr/bin/env bash
# Start the Bifrost gateway container (idempotent: replaces an existing one).
# Image pinned by digest: maximhq/bifrost v2.5.0 (published 2026-11-06).
# Host networking so the container can reach SGLang on 127.0.0.1:30000.
# BIND decides who can reach the gateway: 127.0.0.1 = this box only.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="maximhq/bifrost@sha256:b5258c5f11c79064fc8280e49513f54c0b1da81c78bd11d3b4c1f62f8926d1ab"
BIND="${BIND:-0.0.0.0}"   # LAN (Tate, 2026-11-08). 127.0.0.1 = this box only
PORT="${PORT:-8080}"

docker rm -f bifrost >/dev/null 2>&1 || true
docker run -d --name bifrost \
  --restart unless-stopped \
  --network host \
  --user "$(id -u):$(id -g)" \
  --env-file .env \
  -e APP_HOST="$BIND" -e APP_PORT="$PORT" \
  -v "$PWD/data:/app/data" \
  -v "$PWD/config.json:/app/data/config.json:ro" \
  --read-only --tmpfs /tmp \
  --cap-drop ALL --security-opt no-new-privileges \
  "$IMAGE"
echo "bifrost on http://$BIND:$PORT"
