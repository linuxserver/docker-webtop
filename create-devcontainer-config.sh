#!/bin/bash
# Create VS Code .devcontainer configuration
# This script creates a devcontainer.json that works with the webtop KDE desktop container

set -e

echo "========================================"
echo "VS Code Dev Container Configuration"
echo "========================================"
echo "This script will create a .devcontainer configuration"
echo "for using this container with VS Code."
echo ""

# Check if .devcontainer already exists
if [ -d ".devcontainer" ]; then
    echo "⚠️  .devcontainer directory already exists."
    read -p "Overwrite existing configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    rm -rf .devcontainer
fi

# Default values
GPU_VENDOR="none"
GPU_ALL="false"
GPU_NUMS=""
UBUNTU_VERSION="24.04"
RESOLUTION="1920x1080"
DPI="96"
SSL_DIR=""

# Interactive configuration
echo "========================================"
echo "Configuration Questions"
echo "========================================"
echo ""

# GPU configuration
echo "1. GPU Configuration"
echo "-------------------"
echo "Select GPU type:"
echo "  1) No GPU (software rendering)"
echo "  2) NVIDIA GPU"
echo "  3) NVIDIA WSL2"
echo "  4) Intel GPU"
echo "  5) AMD GPU"
read -p "Select [1-5] (default: 1): " gpu_choice

case "${gpu_choice}" in
    2)
        GPU_VENDOR="nvidia"
        echo ""
        echo "NVIDIA GPU selected."
        read -p "Use all NVIDIA GPUs? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            read -p "Enter GPU device numbers (comma-separated, e.g., 0,1): " GPU_NUMS
            GPU_ALL="false"
        else
            GPU_ALL="true"
            GPU_NUMS=""
        fi
        ;;
    3)
        GPU_VENDOR="nvidia-wsl"
        GPU_ALL="true"
        echo "NVIDIA WSL2 selected."
        ;;
    4)
        GPU_VENDOR="intel"
        echo "Intel GPU selected."
        ;;
    5)
        GPU_VENDOR="amd"
        echo "AMD GPU selected."
        ;;
    *)
        GPU_VENDOR="none"
        echo "No GPU selected (software rendering)."
        ;;
esac
echo ""

# Ubuntu version
echo "2. Ubuntu Version"
echo "----------------"
read -p "Ubuntu version (22.04 or 24.04, default: 24.04): " UBUNTU_VERSION
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
echo ""

# Display settings
echo "3. Display Settings"
echo "-------------------"
read -p "Display resolution (default: 1920x1080): " RESOLUTION
RESOLUTION="${RESOLUTION:-1920x1080}"
read -p "DPI (default: 96): " DPI
DPI="${DPI:-96}"
echo ""

# SSL directory (optional)
echo "4. SSL Configuration (Optional)"
echo "-------------------------------"
read -p "SSL directory path (leave empty to skip): " SSL_DIR
echo ""

CURRENT_USER=$(whoami)
COMPOSE_ENV_SCRIPT="./compose-env.sh"
if [ ! -x "${COMPOSE_ENV_SCRIPT}" ]; then
    echo "Error: ${COMPOSE_ENV_SCRIPT} not found. Run this script from the repository root." >&2
    exit 1
fi

# Create .devcontainer directory
mkdir -p .devcontainer

# Build compose-env arguments
COMPOSE_ARGS=(--gpu "${GPU_VENDOR}" --ubuntu "${UBUNTU_VERSION}" --resolution "${RESOLUTION}" --dpi "${DPI}")
if [ "${GPU_VENDOR}" = "nvidia" ]; then
    if [ "${GPU_ALL}" = "true" ]; then
        COMPOSE_ARGS+=(--all)
    else
        COMPOSE_ARGS+=(--num "${GPU_NUMS}")
    fi
fi
if [ -n "${SSL_DIR}" ]; then
    COMPOSE_ARGS+=(--ssl "${SSL_DIR}")
fi

# Generate environment variables
ENV_FILE=".devcontainer/.env"
"${COMPOSE_ENV_SCRIPT}" "${COMPOSE_ARGS[@]}" --env-file "${ENV_FILE}"

# Load generated environment values
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

DEVCONTAINER_CONTAINER_NAME="${CONTAINER_NAME}-devcontainer"
{
    echo ""
    echo "# Dev Container specific"
    echo "DEVCONTAINER_CONTAINER_NAME=${DEVCONTAINER_CONTAINER_NAME}"
} >> "${ENV_FILE}"
export DEVCONTAINER_CONTAINER_NAME

WORKSPACE_FOLDER="/home/${CURRENT_USER}/host_home"

# Build forward port list
FORWARD_PORTS=("${HOST_PORT_SSL}" "${HOST_PORT_HTTP}" "${HOST_PORT_TURN}")

FORWARD_PORTS_JSON=""
for PORT in "${FORWARD_PORTS[@]}"; do
    if [ -n "${FORWARD_PORTS_JSON}" ]; then
        FORWARD_PORTS_JSON="${FORWARD_PORTS_JSON},
"
    fi
    FORWARD_PORTS_JSON="${FORWARD_PORTS_JSON}    ${PORT}"
done

PORT_ATTRIBUTES_JSON="    \"${HOST_PORT_SSL}\": {
      \"label\": \"HTTPS Web UI\",
      \"onAutoForward\": \"notify\"
    },
    \"${HOST_PORT_HTTP}\": {
      \"label\": \"HTTP Web UI\",
      \"onAutoForward\": \"silent\"
    },
    \"${HOST_PORT_TURN}\": {
      \"label\": \"TURN Server\",
      \"onAutoForward\": \"silent\"
    }"

# devcontainer.json
cat > .devcontainer/devcontainer.json << EOF
{
  "name": "KDE Desktop (${GPU_VENDOR})",
  "dockerComposeFile": [
    "../docker-compose.user.yml",
    "docker-compose.override.yml"
  ],
  "service": "webtop",
  "workspaceFolder": "${WORKSPACE_FOLDER}",
  "runServices": ["webtop"],
  "initializeCommand": "bash .devcontainer/sync-env.sh",
  "overrideCommand": false,
  "shutdownAction": "stopCompose",
  "forwardPorts": [
${FORWARD_PORTS_JSON}
  ],
  "portsAttributes": {
${PORT_ATTRIBUTES_JSON}
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-vscode-remote.remote-containers",
        "ms-python.python",
        "ms-python.vscode-pylance"
      ],
      "settings": {
        "terminal.integrated.defaultProfile.linux": "bash"
      }
    }
  },
  "remoteUser": "${CURRENT_USER}",
  "containerUser": "${CURRENT_USER}",
  "postCreateCommand": "echo 'Dev container is ready!'"
}
EOF

# docker-compose override for devcontainer
cat > .devcontainer/docker-compose.override.yml << EOF
services:
  webtop:
    container_name: \${DEVCONTAINER_CONTAINER_NAME:-${DEVCONTAINER_CONTAINER_NAME}}
    volumes:
      - ..:${WORKSPACE_FOLDER}:cached
EOF

# sync-env helper
cat > .devcontainer/sync-env.sh << 'EOF'
#!/usr/bin/env bash
# Copy .devcontainer/.env to the workspace root for docker compose

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ENV="${ROOT_DIR}/.devcontainer/.env"
TARGET_ENV="${ROOT_DIR}/.env"

if [ ! -f "${SOURCE_ENV}" ]; then
    echo "[devcontainer] No .devcontainer/.env found, skipping env sync." >&2
    exit 0
fi

if [ ! -f "${TARGET_ENV}" ] || ! cmp -s "${SOURCE_ENV}" "${TARGET_ENV}"; then
    cp "${SOURCE_ENV}" "${TARGET_ENV}"
    echo "[devcontainer] Synced .devcontainer/.env to workspace .env for docker compose." >&2
fi
EOF
chmod +x .devcontainer/sync-env.sh

# README
cat > .devcontainer/README.md << EOF
# VS Code Dev Container Configuration

このディレクトリのファイルは \`./create-devcontainer-config.sh\` によって生成され、\`start-container.sh\` と同じ環境変数を \`.devcontainer/.env\` に書き出します。VS Code は起動前に \`.devcontainer/sync-env.sh\` を実行し、同じ値をリポジトリ直下の \`.env\` にコピーしてから \`docker compose\` を実行します。

## 生成された設定

- GPU: ${GPU_VENDOR}
EOF

if [ "${GPU_VENDOR}" = "nvidia" ]; then
    if [ "${GPU_ALL}" = "true" ]; then
        cat >> .devcontainer/README.md << 'EOF'
- NVIDIA GPUs: all
EOF
    else
        cat >> .devcontainer/README.md << EOF
- NVIDIA GPUs: ${GPU_NUMS}
EOF
    fi
fi

cat >> .devcontainer/README.md << EOF
- Ubuntu Version: ${UBUNTU_VERSION}
- Resolution: ${RESOLUTION}
- DPI: ${DPI}
- HTTPS Port: https://localhost:${HOST_PORT_SSL}
- HTTP Port: http://localhost:${HOST_PORT_HTTP}
- TURN Port: ${HOST_PORT_TURN}

## VS Code での利用手順
1. Dev Containers 拡張機能をインストールする
2. ワークスペースを開き、\`F1\` → \`Dev Containers: Reopen in Container\` を実行
3. VS Code が \`.devcontainer/.env\` を同期してから \`docker compose\` を起動

## 再設定
設定を変更したい場合はリポジトリルートで \`./create-devcontainer-config.sh\` を再実行し、案内に従ってください。スクリプト完了後に VS Code 側で「Rebuild Container」を選択すると新しい設定が反映されます。
EOF

# Copy .env to workspace root for docker-compose users
bash .devcontainer/sync-env.sh >/dev/null

echo ""
echo "========================================"
echo "Configuration Complete!"
echo "========================================"
echo ""
echo "Created files:"
echo "  - .devcontainer/devcontainer.json"
echo "  - .devcontainer/docker-compose.override.yml"
echo "  - .devcontainer/.env"
echo "  - .devcontainer/sync-env.sh"
echo "  - .devcontainer/README.md"
echo ""
echo "Configuration summary:"
echo "  - GPU: ${GPU_VENDOR}"
if [ "${GPU_VENDOR}" = "nvidia" ]; then
    if [ "${GPU_ALL}" = "true" ]; then
        echo "    NVIDIA GPUs: all"
    else
        echo "    NVIDIA GPUs: ${GPU_NUMS}"
    fi
fi
echo "  - Ubuntu: ${UBUNTU_VERSION}"
echo "  - Resolution: ${RESOLUTION}"
echo "  - DPI: ${DPI}"
echo "  - HTTPS Port: ${HOST_PORT_SSL}"
echo "  - HTTP Port: ${HOST_PORT_HTTP}"
echo "  - TURN Port: ${HOST_PORT_TURN}"
echo ""
echo "Access the desktop at: https://localhost:${HOST_PORT_SSL}"
echo "========================================"
