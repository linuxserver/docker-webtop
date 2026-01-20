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
HOST_ARCH_RAW=$(uname -m)
case "${HOST_ARCH_RAW}" in
    x86_64|amd64) DETECTED_ARCH="amd64" ;;
    aarch64|arm64) DETECTED_ARCH="arm64" ;;
    *) DETECTED_ARCH="${HOST_ARCH_RAW}" ;;
esac
TARGET_ARCH="${DETECTED_ARCH}"

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

# Architecture
echo "3. Architecture"
echo "---------------"
read -p "Target architecture (amd64 or arm64, default: ${DETECTED_ARCH}): " TARGET_ARCH_INPUT
TARGET_ARCH_INPUT="${TARGET_ARCH_INPUT:-${DETECTED_ARCH}}"
case "${TARGET_ARCH_INPUT}" in
    amd64|x86_64) TARGET_ARCH="amd64" ;;
    arm64|aarch64) TARGET_ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: ${TARGET_ARCH_INPUT}" >&2
        exit 1
        ;;
esac
echo ""

# Display settings
echo "4. Display Settings"
echo "-------------------"
read -p "Display resolution (default: 1920x1080): " RESOLUTION
RESOLUTION="${RESOLUTION:-1920x1080}"
read -p "DPI (default: 96): " DPI
DPI="${DPI:-96}"
echo ""

# Language/Timezone settings
echo "5. Language/Timezone Settings"
echo "-----------------------------"
echo "Select language (affects timezone):"
echo "  ja) Japanese (Asia/Tokyo)"
echo "  en) English (UTC)"
read -p "Select language [ja/en] (default: en): " lang_choice
case "${lang_choice}" in
    ja|JA|jp|JP)
        TIMEZONE="Asia/Tokyo"
        echo "Japanese selected. Timezone: Asia/Tokyo"
        ;;
    *)
        TIMEZONE="UTC"
        echo "English selected. Timezone: UTC"
        ;;
esac
echo ""

# SSL directory (optional)
echo "5. SSL Configuration (Optional)"
echo "-------------------------------"
read -p "SSL directory path (leave empty to skip): " SSL_DIR
echo ""

# Default SSL dir fallback (same as start-container.sh)
if [ -z "${SSL_DIR}" ]; then
    DEFAULT_SSL_DIR="$(pwd)/ssl"
    if [ -d "${DEFAULT_SSL_DIR}" ]; then
        SSL_DIR="${DEFAULT_SSL_DIR}"
        echo "Using SSL dir: ${SSL_DIR}"
    fi
fi

CURRENT_USER=$(whoami)
COMPOSE_ENV_SCRIPT="./compose-env.sh"
if [ ! -x "${COMPOSE_ENV_SCRIPT}" ]; then
    echo "Error: ${COMPOSE_ENV_SCRIPT} not found. Run this script from the repository root." >&2
    exit 1
fi

# Create .devcontainer directory
mkdir -p .devcontainer

# Build compose-env arguments
COMPOSE_ARGS=(--gpu "${GPU_VENDOR}" --ubuntu "${UBUNTU_VERSION}" --resolution "${RESOLUTION}" --dpi "${DPI}" --arch "${TARGET_ARCH}" --timezone "${TIMEZONE}")
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

DEVCONTAINER_CONTAINER_NAME="${CONTAINER_NAME}"
{
    echo ""
    echo "# Dev Container specific"
    echo "DEVCONTAINER_CONTAINER_NAME=${DEVCONTAINER_CONTAINER_NAME}"
} >> "${ENV_FILE}"
export DEVCONTAINER_CONTAINER_NAME

WORKSPACE_FOLDER="/home/${CURRENT_USER}/host_home"

GPU_DEVICES=""
case "${GPU_VENDOR}" in
    intel)
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        fi
        ;;
    amd)
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
                    fi
        if [ -e "/dev/kfd" ]; then
            GPU_DEVICES="${GPU_DEVICES:+${GPU_DEVICES},}/dev/kfd:/dev/kfd:rwm"
        fi
        ;;
    nvidia)
        if [ -d "/dev/dri" ]; then
            GPU_DEVICES="/dev/dri:/dev/dri:rwm"
        fi
        ;;
    nvidia-wsl)
        if [ -e "/dev/dxg" ]; then
            GPU_DEVICES="/dev/dxg:/dev/dxg:rwm"
        fi
        ;;
esac

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
    "docker-compose.base.yml",
    "docker-compose.override.yml"
  ],
  "service": "webtop",
  "workspaceFolder": "${WORKSPACE_FOLDER}",
  "runServices": ["webtop"],
  "overrideCommand": false,
  "shutdownAction": "none",
  "initializeCommand": "cd \${localWorkspaceFolder:-${PWD}} && if [ -f .devcontainer/.env ]; then CN=\$(sed -n 's/^CONTAINER_NAME=//p' .devcontainer/.env | head -n1); fi; if [ -n \"\$CN\" ]; then docker rm -f \"\$CN\" >/dev/null 2>&1 || true; fi",
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
        "ms-vscode.cpptools-extension-pack",
        "ms-vscode.cmake-tools",
        "ms-vscode.makefile-tools",
        "redhat.vscode-yaml",
        "redhat.vscode-xml",
        "ms-vscode.hexeditor",
        "ms-python.python",
        "ms-python.vscode-pylance",
        "vscode-icons-team.vscode-icons",
        "donjayamanne.git-extension-pack"
      ],
      "settings": {
        "terminal.integrated.defaultProfile.linux": "bash"
      }
    }
  },
  "remoteUser": "${CURRENT_USER}",
  "containerUser": "root",
  "updateRemoteUserUID": false,
  "remoteEnv": {
    "USER": "${CURRENT_USER}",
    "HOME": "/home/${CURRENT_USER}"
  },
EOF
    # Add GPU hostRequirements if applicable
    if [ "${GPU_VENDOR}" = "nvidia" ] || [ "${GPU_VENDOR}" = "nvidia-wsl" ]; then
        cat >> .devcontainer/devcontainer.json << 'EOF'
  "hostRequirements": {
    "gpu": "optional"
  },
EOF
    fi
    
    cat >> .devcontainer/devcontainer.json << EOF
  "postCreateCommand": "echo '===== Dev Container Ready =====' && echo 'Desktop access' && echo '  HTTPS: https://localhost:${HOST_PORT_SSL}' && echo '  HTTP : http://localhost:${HOST_PORT_HTTP}' && echo 'If HTTPS fails, confirm your SSL certs or use HTTP.' && echo '==============================='"
}
EOF

# docker-compose base (match start-container.sh)
cat > .devcontainer/docker-compose.base.yml << EOF
services:
  webtop:
    image: \${USER_IMAGE}
    container_name: \${CONTAINER_NAME}
    hostname: \${CONTAINER_HOSTNAME}
    shm_size: \${SHM_SIZE:-4g}
    privileged: true
    security_opt:
      - seccomp:unconfined
    environment:
      - HOSTNAME=\${CONTAINER_HOSTNAME}
      - HOST_HOSTNAME=\${CONTAINER_HOSTNAME}
      - SHELL=/bin/bash
      - DISPLAY=:1
      - DPI=\${DPI}
      - SCALE_FACTOR=\${SCALE_FACTOR}
      - FORCE_DEVICE_SCALE_FACTOR=\${FORCE_DEVICE_SCALE_FACTOR}
      - CHROMIUM_FLAGS=\${CHROMIUM_FLAGS}
      - DISPLAY_WIDTH=\${WIDTH}
      - DISPLAY_HEIGHT=\${HEIGHT}
      - CUSTOM_RESOLUTION=\${RESOLUTION}
      - USER_UID=\${USER_UID}
      - USER_GID=\${USER_GID}
      - USER_NAME=\${USER_NAME}
      - PUID=\${HOST_UID}
      - PGID=\${HOST_GID}
      - SELKIES_ENCODER=\${SELKIES_ENCODER}
      - GPU_VENDOR=\${GPU_VENDOR}
      - ENABLE_NVIDIA=\${ENABLE_NVIDIA}
      - LIBVA_DRIVER_NAME=\${LIBVA_DRIVER_NAME}
      - WSL_ENVIRONMENT=\${WSL_ENVIRONMENT}
      - DISABLE_ZINK=\${DISABLE_ZINK}
      - SELKIES_TURN_HOST=\${SELKIES_TURN_HOST}
      - SELKIES_TURN_PORT=\${SELKIES_TURN_PORT}
      - SELKIES_TURN_USERNAME=\${SELKIES_TURN_USERNAME}
      - SELKIES_TURN_PASSWORD=\${SELKIES_TURN_PASSWORD}
      - SELKIES_TURN_PROTOCOL=\${SELKIES_TURN_PROTOCOL}
      - TURN_RANDOM_PASSWORD=\${TURN_RANDOM_PASSWORD}
      - TURN_EXTERNAL_IP=\${TURN_EXTERNAL_IP}
    volumes:
      - \${HOME}:\${HOST_HOME_MOUNT}:rw
    ports:
      - \${HOST_PORT_HTTP}:3000
      - \${HOST_PORT_SSL}:3001
      - \${HOST_PORT_TURN}:3478/tcp
      - \${HOST_PORT_TURN}:3478/udp
    restart: unless-stopped
EOF

# docker-compose override for devcontainer
cat > .devcontainer/docker-compose.override.yml << EOF
services:
  webtop:
    network_mode: bridge
EOF

DEVICE_ENTRIES=()
VOLUME_ENTRIES=()
GROUPS_TO_ADD=()

# Add host group mappings (match start-container.sh)
VIDEO_GID=$(getent group video 2>/dev/null | cut -d: -f3 || true)
RENDER_GID=$(getent group render 2>/dev/null | cut -d: -f3 || true)
if [ -n "${VIDEO_GID}" ]; then
    GROUPS_TO_ADD+=("${VIDEO_GID}")
fi
if [ -n "${RENDER_GID}" ]; then
    GROUPS_TO_ADD+=("${RENDER_GID}")
fi

if [ "${#GROUPS_TO_ADD[@]}" -gt 0 ]; then
    {
        echo "    group_add:"
        for GID in "${GROUPS_TO_ADD[@]}"; do
            echo "      - \"${GID}\""
        done
    } >> .devcontainer/docker-compose.override.yml
fi

if [ "${GPU_VENDOR}" = "nvidia" ] || [ "${GPU_VENDOR}" = "nvidia-wsl" ]; then
    if [ "${GPU_VENDOR}" = "nvidia-wsl" ] || [ "${GPU_ALL}" = "true" ]; then
        echo "    gpus: all" >> .devcontainer/docker-compose.override.yml
    elif [ -n "${GPU_NUMS}" ]; then
        echo "    gpus: \"device=${GPU_NUMS}\"" >> .devcontainer/docker-compose.override.yml
    fi
fi

if [ "${GPU_VENDOR}" = "nvidia-wsl" ]; then
    # Add WSL-specific devices if they exist
    if [ -e "/dev/dxg" ]; then
        DEVICE_ENTRIES+=("/dev/dxg:/dev/dxg:rwm")
    fi
    # Add WSL-specific volumes
    if [ -d "/usr/lib/wsl/lib" ] || [ -d "/mnt/wslg" ]; then
        :
    fi
    if [ -d "/usr/lib/wsl/lib" ]; then
        VOLUME_ENTRIES+=("/usr/lib/wsl/lib:/usr/lib/wsl/lib:ro")
    fi
    if [ -d "/mnt/wslg" ]; then
        VOLUME_ENTRIES+=("/mnt/wslg:/mnt/wslg:ro")
    fi
fi

if [ -n "${GPU_DEVICES}" ]; then
    IFS=',' read -r -a GPU_DEVICE_LIST <<< "${GPU_DEVICES}"
    for DEVICE in "${GPU_DEVICE_LIST[@]}"; do
        DEVICE_ENTRIES+=("${DEVICE}")
    done
fi

# Add SSL mount when available (match start-container.sh)
if [ -n "${SSL_DIR}" ] && [ -f "${SSL_DIR}/cert.pem" ] && [ -f "${SSL_DIR}/cert.key" ]; then
    VOLUME_ENTRIES+=("\${SSL_DIR}:/config/ssl:ro")
fi

# Add /mnt mount on non-mac hosts (Docker Desktop for Mac does not share /mnt by default)
if [ "$(uname -s)" != "Darwin" ] && [ -d "/mnt" ]; then
    VOLUME_ENTRIES+=("/mnt:\${HOST_MNT_MOUNT}:rw")
fi

if [ "${#DEVICE_ENTRIES[@]}" -gt 0 ]; then
    {
        echo "    devices:"
        for DEVICE in "${DEVICE_ENTRIES[@]}"; do
            echo "      - ${DEVICE}"
        done
    } >> .devcontainer/docker-compose.override.yml
fi

if [ "${#VOLUME_ENTRIES[@]}" -gt 0 ]; then
    {
        echo "    volumes:"
        for VOLUME in "${VOLUME_ENTRIES[@]}"; do
            echo "      - ${VOLUME}"
        done
    } >> .devcontainer/docker-compose.override.yml
fi

# Copy .env to workspace root for docker-compose
cp "${ENV_FILE}" .env

# README
cat > .devcontainer/README.md << EOF
# VS Code Dev Container Configuration

The files in this directory are generated by \`./create-devcontainer-config.sh\`. It writes the same environment variables as \`start-container.sh\` into \`.devcontainer/.env\` and the repository root \`.env\`.

## Generated settings

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
- Timezone: ${TIMEZONE}
- HTTPS Port: https://localhost:${HOST_PORT_SSL}
- HTTP Port: http://localhost:${HOST_PORT_HTTP}
- TURN Port: ${HOST_PORT_TURN}

## How to use in VS Code
1. Install the Dev Containers extension
2. Open the workspace and run \`F1\` → \`Dev Containers: Reopen in Container\`
3. VS Code reads \`.env\` and starts \`docker compose\`

## How to use in VS Code
1. Install the Dev Containers extension
2. Open the workspace and run \`F1\` → \`Dev Containers: Reopen in Container\`
3. VS Code reads \`.env\` and starts \`docker compose\`
EOF

# Copy .env to workspace root for docker-compose
cp "${ENV_FILE}" .env

echo ""
echo "========================================"
echo "Configuration Complete!"
echo "========================================"
echo ""
echo "Created files:"
echo "  - .devcontainer/devcontainer.json"
echo "  - .devcontainer/docker-compose.base.yml"
echo "  - .devcontainer/docker-compose.override.yml"
echo "  - .devcontainer/.env"
echo "  - .devcontainer/README.md"
echo "  - .env (for docker-compose)"
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
echo "  - Timezone: ${TIMEZONE}"
echo "  - HTTPS Port: ${HOST_PORT_SSL}"
echo "  - HTTP Port: ${HOST_PORT_HTTP}"
echo "  - TURN Port: ${HOST_PORT_TURN}"
echo ""
echo "Access the desktop at: https://localhost:${HOST_PORT_SSL}"
echo "========================================"
