# kde-selkies-webtop-devcontainer

**[日本語版 (README_ja.md)](README_ja.md)**

A containerized Kubuntu (KDE Plasma) desktop accessible from any browser. Powered by Selkies WebRTC streaming — no VNC or RDP needed.

Works on **Ubuntu/Linux**, **macOS (Docker Desktop)**, and **WSL2**. All platforms share the same entry points: `build-user-image.sh`, `start-container.sh`, and `create-devcontainer-config.sh`.

## Why This Project?

This is a fork of [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) that focuses on developer usability and multi-platform support.

| | Original | This Project |
|---|---|---|
| **Image delivery** | Pull-ready image | Two-stage local build (user image in 1-2 min) |
| **Container user** | Root | Your own UID/GID (non-root) |
| **UID/GID setup** | Manual | Automatic matching |
| **Password handling** | Plaintext in command | Environment variable |
| **Shell** | Generic bash | Ubuntu Desktop bash (color prompt, Git branch, aliases) |
| **GPU selection** | Auto-detect | Explicit `--encoder` / `--gpu` flags |
| **Dependency versions** | Floating | Pinned (VirtualGL 3.1.4, Pixelflux 1.6.0, Selkies latest main / pinnable via `SELKIES_COMMIT`) |
| **Docker-in-Docker** | — | `--docker-mode dind\|dood` |
| **Stream tuning** | — | `-S` stream scale, `-f` framerate control |
| **Dev Container** | — | `create-devcontainer-config.sh` (same settings as CLI) |
| **Language support** | English only | Multi-language (EN/JA) |

## Key Features

- **Two-stage build** — Heavy base image (5-10 GB, built once) + lightweight user image (~100 MB, 1-2 min). No more 30-60 min waits.
- **Non-root by default** — Containers run under your own user. Proper permission separation, sudo when needed.
- **Automatic UID/GID matching** — Mounted host directories just work. No "permission denied" on shared folders.
- **Unified configuration** — `start-container.sh` (day-to-day) and `create-devcontainer-config.sh` (VS Code Dev Container) share the same interactive settings.
- **Explicit encoder/GPU control** — `--encoder nvidia|intel|amd|software|nvidia-wsl` selects the encoder. `--all`/`--num` controls Docker GPU assignment independently.
- **Stream scaling** — `-S 0.5` halves the actual encoding resolution, reducing both bandwidth and encoder load.
- **Docker mode switching** — `--docker-mode dood` (host socket) or `dind` (container-internal dockerd).
- **Browser-only access** — `https://localhost:<30000+UID>` after startup. No SSH/RDP distribution needed.
- **Secure passwords** — Set via environment variable; never exposed in commands or logs.
- **Multi-language** — `-l ja` at build time installs Japanese input (Mozc), timezone, and locale.
- **Version-pinned** — Reproducible builds with pinned VirtualGL 3.1.4, Pixelflux 1.6.0, and Selkies (latest `main` by default; pinnable via `SELKIES_COMMIT` build arg).

## Platform Support

| Environment | GPU Rendering | WebGL / Vulkan | HW Encoding | Notes |
|---|---|---|---|---|
| **Ubuntu + NVIDIA GPU** | ✅ | ✅ | ✅ NVENC | Best performance |
| **Ubuntu + Intel GPU** | ✅ | ✅ | ✅ VA-API (QSV) | Integrated GPU OK |
| **Ubuntu + AMD GPU** | ✅ | ✅ | ✅ VA-API | RDNA / GCN |
| **WSL2 + NVIDIA GPU** | ❌ Software | ❌ Software | ✅ NVENC | Encoding works, rendering is software |
| **macOS (Docker Desktop)** | ❌ | ❌ Software | ❌ | VM limitation; workflow is identical |

---

## Quick Start

```bash
# 1. Build user image (1-2 min; base image pulled from GHCR automatically)
./build-user-image.sh                    # English (default)
./build-user-image.sh -l ja              # Japanese environment
./build-user-image.sh -u 22.04           # Ubuntu 22.04
./build-user-image.sh -u 26.04           # Ubuntu 26.04 (X11/Xvfb)

# 2. Start the container
./start-container.sh                     # Interactive settings
./start-container.sh --encoder software  # Software encoding
./start-container.sh --encoder nvidia --all          # NVIDIA NVENC (all GPUs)
./start-container.sh --encoder nvidia --num 0        # NVIDIA NVENC (GPU 0 only)
./start-container.sh --encoder intel                 # Intel VA-API
./start-container.sh --encoder amd -r 1920x1080 -S 0.5  # AMD + half stream resolution
./start-container.sh --encoder nvidia-wsl --all      # WSL2 + NVIDIA NVENC

# 3. Open in browser
#    https://localhost:<30000+UID>  (e.g. UID 1000 → https://localhost:31000)
#    http://localhost:<40000+UID>   (e.g. UID 1000 → http://localhost:41000)

# 4. Save changes (IMPORTANT — do this before removing the container)
./commit-container.sh

# 5. Stop
./stop-container.sh            # Stop (container persists, can restart)
./stop-container.sh --rm       # Stop and remove (only recommended after commit)
```

### Platform-Specific Examples

**Ubuntu / Linux**
```bash
./build-user-image.sh -u 22.04
./start-container.sh --encoder intel
```

**macOS (Docker Desktop)**
```bash
./build-user-image.sh -u 22.04 -a amd64
./start-container.sh --encoder software -a amd64 --docker-mode dood
```

**WSL2 + NVIDIA**
```bash
./build-user-image.sh -u 22.04
./start-container.sh --encoder nvidia-wsl --all
```

### VS Code Dev Container

```bash
# 1. Generate Dev Container configuration (same interactive settings as start-container.sh)
./create-devcontainer-config.sh

# 2. In VS Code: F1 → "Dev Containers: Reopen in Container"

# 3. Access the desktop at https://localhost:<displayed-port>
```

---

## Table of Contents

- [Why This Project?](#why-this-project)
- [Key Features](#key-features)
- [Platform Support](#platform-support)
- [Quick Start](#quick-start)
- [System Requirements](#system-requirements)
- [Two-Stage Build System](#two-stage-build-system)
- [Intel/AMD GPU Host Setup](#intelamd-gpu-host-setup)
- [Setup (Build User Image)](#setup-build-user-image)
- [Usage](#usage)
- [Appendix: Build Base Image](#appendix-build-base-image)
- [Appendix: Scripts Reference](#appendix-scripts-reference)
- [Appendix: Configuration](#appendix-configuration)
- [Appendix: HTTPS/SSL](#appendix-httpsssl)
- [Troubleshooting](#troubleshooting)
- [Known Limitations](#known-limitations)
- [Appendix: Advanced Topics](#appendix-advanced-topics)

---

## System Requirements

### Required

- **Docker** 20.10+ (Docker Desktop 4.0+)
- **8 GB+ RAM** (16 GB recommended)
- **20 GB+ free disk space**

### GPU (Optional — for hardware acceleration)

- **NVIDIA GPU** ✅ Tested
  - Driver 470+, Maxwell generation or newer
  - NVIDIA Container Toolkit installed
- **Intel GPU** ✅ Tested
  - Integrated graphics (HD Graphics, Iris, Arc) with Quick Sync Video
  - VA-API drivers included in the container
  - **Host setup required** (see below)
- **AMD GPU** ⚠️ Partially tested
  - Radeon with VCE/VCN encoder
  - VA-API drivers included in the container
  - **Host setup required** (see below)

---

## Two-Stage Build System

```
┌─────────────────────────┐
│   Base Image (5-10 GB)  │  ← Built once (30-60 min) or pulled from GHCR
│  • System packages      │
│  • Desktop environment  │
│  • Pre-installed apps   │
└────────────┬────────────┘
             │
             ↓  builds on top
┌────────────┴────────────┐
│ User Image (~100 MB)    │  ← You build this (1-2 min)
│  • Your username        │
│  • Your UID/GID         │
│  • Your password        │
└─────────────────────────┘
```

**Benefits:**
- ✅ **Fast setup** — No 30-60 min build wait
- ✅ **Proper permissions** — Files match your host UID/GID
- ✅ **Easy updates** — Pull new base image, rebuild user image

**Why UID/GID matching matters:**
Mounting host directories (e.g. `$HOME`) requires matching file ownership. Without it you get permission errors. The user image handles this automatically.

---

## Intel/AMD GPU Host Setup

Required only for Intel/AMD hardware encoding (VA-API). NVIDIA GPUs do not need this.

### 1. Add user to video/render groups

```bash
sudo usermod -aG video,render $USER
# Log out and back in, then verify:
groups  # should include "video" and "render"
```

### 2. Install VA-API drivers

**Intel:**
```bash
sudo apt update && sudo apt install vainfo intel-media-va-driver-non-free
vainfo  # should show VAProfileH264Main : VAEntrypointEncSlice
```

**AMD:**
```bash
sudo apt update && sudo apt install vainfo mesa-va-drivers
vainfo  # should show VAProfileH264Main : VAEntrypointEncSlice
```

> If VA-API works on the host, it automatically works inside the container.

---

## Setup (Build User Image)

The base image is pulled from GHCR automatically — no manual base build needed for typical use.

```bash
# English (default)
./build-user-image.sh

# Japanese
./build-user-image.sh -l ja

# Skip password prompt
USER_PASSWORD=yourpass ./build-user-image.sh
```

**Options:**
```bash
./build-user-image.sh -u 22.04           # Ubuntu 22.04
./build-user-image.sh -u 26.04           # Ubuntu 26.04 (X11/Xvfb)
./build-user-image.sh -v 2.0.0           # Custom version
./build-user-image.sh -b my-base:1.1.0   # Custom base image tag
./build-user-image.sh -i ghcr.io/you/img  # Custom base image name
./build-user-image.sh -a amd64           # Architecture hint
./build-user-image.sh -p linux/amd64     # Explicit platform override
./build-user-image.sh -n                 # Build without Docker cache
```

---

## Usage

### Starting the Container

On the first run, the interactive wizard saves settings to `configs/<name>.yml`.
Later runs load that file automatically. Use `--reconfigure` to edit saved settings interactively.

```bash
# First run — prompts for all settings and saves them
./start-container.sh

# Reconfigure — uses the saved settings as prompt defaults, then starts
./start-container.sh --reconfigure

# CLI examples
./start-container.sh --encoder software
./start-container.sh --encoder nvidia --all
./start-container.sh --encoder nvidia --num 0
./start-container.sh --encoder intel --dri-node /dev/dri/renderD129
./start-container.sh --encoder amd -r 2560x1440 -d 144 -S 0.5
./start-container.sh --encoder nvidia-wsl --all --docker-mode dood
./start-container.sh --encoder software -a amd64   # adds --platform linux/amd64
```

**Interactive settings** (managed by `configure-container.sh`):

container name, Ubuntu version, architecture, docker mode (`dind`/`dood`), encoder, Docker GPU selection (`--all`/`--num`), DRI node, resolution, DPI, stream scale, framerate, timezone, language, SSL directory, Mac/Docker Desktop options.

**Existing container behavior:**
- Stopped container with the same name → resumes with previous settings (no prompts)
- Running container with the same name → script exits

**UID-based port assignment** (multi-user safe):
- HTTPS: `30000 + UID` (e.g. UID 1000 → port 31000)
- HTTP: `40000 + UID` (e.g. UID 1000 → port 41000)

**Remote access:** WebRTC-based. LAN IP is auto-detected; access from `https://<host-ip>:<https-port>`.

**Container notes:**
- Containers persist after stop (restart or commit anytime)
- Hostname: `Docker-$(hostname)`
- Host home mounted at `~/host_home`
- Host `/mnt` mounted at `~/host_mnt` (Linux/WSL2 only, skipped on macOS)
  - On WSL2 this gives access to Windows drives (e.g. `~/host_mnt/c/Users/...`)
- Container name: `linuxserver-kde-{username}`
- `dind` runs `dockerd` inside the container; `dood` shares the host Docker socket
- `STREAM_SCALE` reduces the actual encoding resolution, not just the display

### Saving Changes (Important!)

```bash
./commit-container.sh
```

- ⚠️ **Always commit before `./stop-container.sh --rm`** — otherwise changes are lost
- Image format: `webtop-kde-{username}-{arch}-u{ubuntu_version}:{version}`
- Committed images persist after container deletion
- Next startup automatically uses the committed image

**Typical workflow:**
```bash
./shell-container.sh          # Work inside the container
# ... install packages, configure environment ...
exit
./commit-container.sh         # Save to image
./stop-container.sh --rm      # Safe to remove now
./start-container.sh --encoder intel   # Resumes with all changes
```

### Stopping the Container

```bash
./stop-container.sh            # Stop (keeps container)
./stop-container.sh --rm       # Stop and remove
```

---

## Appendix: Build Base Image

Only needed if you want to build from scratch instead of pulling from GHCR (30-60 min):

```bash
./files/build-base-image.sh                         # Ubuntu 24.04, auto-detect arch
./files/build-base-image.sh -u 22.04                # Ubuntu 22.04
./files/build-base-image.sh -u 26.04                # Ubuntu 26.04 (X11/Xvfb)
./files/build-base-image.sh -a amd64                # Intel/AMD 64-bit
./files/build-base-image.sh -a arm64                # Apple Silicon / ARM
./files/build-base-image.sh -a amd64 -u 26.04       # Combine options
./files/build-base-image.sh --no-cache               # Clean rebuild

# Push to GHCR
./files/push-base-image.sh

# Custom repository
IMAGE_NAME=ghcr.io/you/your-base ./files/build-base-image.sh
IMAGE_NAME=ghcr.io/you/your-base ./files/push-base-image.sh
```

---

## Appendix: Scripts Reference

### Core Scripts

| Script | Description | Usage |
|---|---|---|
| `build-user-image.sh` | Build user-specific image | `./build-user-image.sh [-l ja] [-u 22.04|24.04|26.04]` |
| `start-container.sh` | Start or resume the container | `./start-container.sh [--encoder <type>]` |
| `configure-container.sh` | Create or edit saved startup settings | `./configure-container.sh [--config <file>]` |
| `create-devcontainer-config.sh` | Generate Dev Container config | `./create-devcontainer-config.sh` |
| `stop-container.sh` | Stop the container | `./stop-container.sh [--rm]` |

### Management Scripts

| Script | Description | Usage |
|---|---|---|
| `shell-container.sh` | Open a shell inside the container | `./shell-container.sh` |
| `commit-container.sh` | Save container state to image | `./commit-container.sh` |
| `logs-container.sh` | View container logs | `./logs-container.sh` |
| `restart-container.sh` | Restart the container | `./restart-container.sh` |
| `delete-image.sh` | Delete the user image | `./delete-image.sh` |
| `files/build-base-image.sh` | Build the base image | `./files/build-base-image.sh [-a arch]` |
| `files/push-base-image.sh` | Push base image to GHCR | `./files/push-base-image.sh` |

### Start Options

```
./start-container.sh [options]

Encoder / GPU:
  -e, --encoder <type>       software | nvidia | nvidia-wsl | intel | amd
  -g, --gpu <value>          Docker --gpus value: all or device=0,1
  --all                      Shortcut for --gpu all
  --num <list>               Shortcut for --gpu device=<list>
  --dri-node <path>          DRI render node for VA-API

Display:
  -r <WxH>                   Resolution (e.g. 1920x1080)
  -d <dpi>                   DPI (e.g. 96, 144, 192)
  -S, --stream-scale <f>     Encoding resolution scale (0.25–1.0)
  -f <fps|min-max>           Framerate (e.g. 30, 30-60)

Other:
  --docker-mode <mode>       dind or dood
  --timezone <tz>            Timezone (e.g. Asia/Tokyo)
  -a <arch>                  amd64 / arm64
  -p <platform>              Explicit --platform for docker run
  -s <ssl_dir>               SSL certificate directory
  -n <name>                  Container name
  --config <file>            YAML config file (default: configs/<name>.yml)
  --reconfigure              Edit saved settings interactively before starting
```

---

## Appendix: Configuration

### Display Settings

```bash
./start-container.sh -r 1920x1080 -d 96              # Standard
./start-container.sh -r 2560x1440 -d 144             # WQHD HiDPI
./start-container.sh -r 3840x2160 -d 192             # 4K HiDPI

# Stream scale — reduces actual encoding resolution
./start-container.sh --encoder software -r 1920x1080 -S 0.5
# Encodes at 960x540, displayed in a 1920x1080 viewport
```

### Video Encoding

| GPU | Encoder | Quality | CPU Load |
|---|---|---|---|
| NVIDIA | NVENC | High | Low |
| Intel | VA-API (Quick Sync) | High | Low |
| AMD | VA-API | High | Low |
| None | Software (libx264) | Medium | High |

`-S/--stream-scale` reduces the resolution before encoding, cutting both bandwidth and encoder load.

### Audio

| Feature | Status | Technology |
|---|---|---|
| Speaker output | ✅ Built-in | WebRTC (browser native) |
| Microphone input | ✅ Built-in | WebRTC (browser native) |

Selkies streams bidirectional audio to the browser via WebRTC.

---

## Appendix: HTTPS/SSL

### Quick Setup (Recommended)

Generate a CA-signed certificate and trust it on your OS:

```bash
# 1. Generate CA + server certificate
./generate-ssl-cert.sh

# 2. Trust the CA on your OS (one-time setup)
#    macOS:
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ./ssl/ca.crt

#    Linux (Ubuntu/Debian):
sudo cp ./ssl/ca.crt /usr/local/share/ca-certificates/local-dev-ca.crt
sudo update-ca-certificates

#    Windows (PowerShell as Administrator):
Import-Certificate -FilePath .\ssl\ca.crt -CertStoreLocation Cert:\LocalMachine\Root

# 3. Start the container (ssl/ is auto-detected)
./start-container.sh
```

After step 2, browsers will show a green lock icon with no warnings.

> **Note:** If you regenerate certificates (`./generate-ssl-cert.sh -f`), you must repeat step 2 because the CA key changes.

### Using Your Own Certificates

```bash
mkdir -p ssl
cp /path/to/cert.pem ssl/
cp /path/to/key.pem ssl/cert.key
./start-container.sh   # auto-detects ssl/
```

### generate-ssl-cert.sh Options

| Option | Description | Default |
|---|---|---|
| `-c <hostname>` | Common name / hostname | `localhost` |
| `-d <dir>` | Output directory | `./ssl` |
| `-n <days>` | Validity period | `365` |
| `--no-ca` | Self-signed cert (no CA) | CA mode |
| `-f` | Force overwrite existing certs | — |

Output files: `ssl/ca.crt`, `ssl/ca.key`, `ssl/cert.pem`, `ssl/cert.key`

### Certificate Priority

1. `ssl/cert.pem` + `ssl/cert.key` (project directory)
2. `SSL_DIR` environment variable
3. Image default certificate (fallback)

---

## Troubleshooting

### Container Won't Start

```bash
docker logs linuxserver-kde-$(whoami)
docker images | grep webtop-kde
./build-user-image.sh                           # Rebuild user image
sudo netstat -tulpn | grep -E "31000|41000"     # Check port conflicts
```

### GPU Not Detected

```bash
# NVIDIA
./shell-container.sh
nvidia-smi

# Intel / AMD
./shell-container.sh
ls -la /dev/dri/ && vainfo

# Verify Docker GPU access
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### Permission Issues

```bash
id                    # On host
./shell-container.sh
id                    # Inside container — UIDs should match
# If mismatched, rebuild: ./build-user-image.sh
```

### Black Screen / Desktop Not Showing

```bash
docker logs linuxserver-kde-$(whoami)
docker exec linuxserver-kde-$(whoami) pgrep -af plasmashell
docker exec linuxserver-kde-$(whoami) ls -la /run/user/$(id -u)
```

Causes: `/run/user/<uid>` missing or wrong permissions, plasmashell crash → restart the container.

### WebGL/Vulkan Not Working

```bash
docker exec linuxserver-kde-$(whoami) glxinfo | head -30
docker exec linuxserver-kde-$(whoami) vulkaninfo | head -50
```

On macOS: GPU acceleration is unavailable due to Docker VM limitations. Software rendering is used.

### No Audio

```bash
docker exec linuxserver-kde-$(whoami) bash -lc 's6-setuidgid "${USER_NAME}" pactl info'
docker exec linuxserver-kde-$(whoami) bash -lc 's6-setuidgid "${USER_NAME}" pactl list sinks short'
```

Check browser audio permissions and use HTTPS (some browsers block audio over HTTP).

---

## Known Limitations

### Vulkan
- Xvfb does not support DRI3, so Vulkan applications cannot present frames
- VirtualGL-based OpenGL works normally
- In some setups, vkcube detects the NVIDIA GPU under Xvfb, but presentation behavior is configuration-dependent
- Ubuntu 26.04 uses the distro Xvfb because the custom DRI3 patch is not compatible with xorg-server 21.1.22

### macOS
- Docker Desktop runs containers inside a Linux VM — no access to Apple GPU (Metal)
- WebGL/Vulkan uses software rendering (llvmpipe)
- Use native Linux or WSL2 for hardware acceleration

### WSL2
- Only NVIDIA GPUs are supported
- Rendering is software (llvmpipe); WebGL/Vulkan are software-only
- Hardware encoding (NVENC) works via `--encoder nvidia-wsl`

---

## Appendix: Advanced Topics

### Environment Variables

<details>
<summary>Click to expand</summary>

#### Container

| Variable | Description | Default |
|---|---|---|
| `CONTAINER_NAME` | Container name | `linuxserver-kde-$(whoami)` |
| `IMAGE_BASE` | Image base name | `webtop-kde` |
| `IMAGE_VERSION` | Image version | `1.1.0` |

#### Display

| Variable | Description | Default |
|---|---|---|
| `RESOLUTION` | Resolution | `1920x1080` |
| `DPI` | DPI | `96` |
| `STREAM_SCALE` | Encoding resolution scale | `1.0` |
| `FRAMERATE` | Selkies framerate | `30` |
| `TIMEZONE` | Timezone | `UTC` |

#### GPU

| Variable | Description | Default |
|---|---|---|
| `ENCODER` | Encoder type | (unset) |
| `GPU_VENDOR` | GPU vendor | `software` |
| `DOCKER_MODE` | Docker mode | `dind` |

#### Network

| Variable | Description | Default |
|---|---|---|
| `PORT_SSL_OVERRIDE` | HTTPS port override | `UID + 30000` |
| `PORT_HTTP_OVERRIDE` | HTTP port override | `UID + 40000` |

</details>

### Project Structure

```
kde-selkies-webtop-devcontainer/
├── build-user-image.sh           # Build user image
├── start-container.sh            # Start container
├── create-devcontainer-config.sh # Generate Dev Container config
├── compose-env.sh                # Generate env for compose/devcontainer
├── interactive-common.sh         # Shared interactive settings
├── stop-container.sh             # Stop container
├── restart-container.sh          # Restart container
├── shell-container.sh            # Shell access
├── commit-container.sh           # Save changes
├── logs-container.sh             # View logs
├── delete-image.sh               # Delete user image
├── generate-ssl-cert.sh          # Generate SSL certificate
├── ssl/                          # SSL certificates (auto-detected)
│   ├── cert.pem
│   └── cert.key
└── files/                        # System files
    ├── build-base-image.sh       # Build base image
    ├── push-base-image.sh        # Push base image to GHCR
    ├── linuxserver-kde.base.dockerfile
    ├── linuxserver-kde.user.dockerfile
    ├── alpine-root/              # s6-overlay config
    ├── kde-root/                 # KDE defaults
    └── ubuntu-root/              # Ubuntu defaults
```

### Version Pinning

External dependencies are pinned for reproducible builds:

- **VirtualGL:** 3.1.4 (build argument in Dockerfile)
- **Pixelflux:** 1.6.0 (local `.whl` files in `files/pixelflux/`)
- **Selkies:** Tracks latest `main` branch by default. Pin to a specific commit via `--build-arg SELKIES_COMMIT=<hash>`

Hardware encoding:
- **NVIDIA:** NVENC via Pixelflux
- **Intel:** VA-API (Quick Sync Video) via Pixelflux
- **AMD:** VA-API via Pixelflux

Versions are defined in [files/linuxserver-kde.base.dockerfile](files/linuxserver-kde.base.dockerfile).

---

## License

This project is based on multiple open source projects:
- [linuxserver/webtop](https://github.com/linuxserver/docker-webtop) — GPL-3.0
- [selkies-project/selkies](https://github.com/selkies-project/selkies) — MPL-2.0
- [VirtualGL](https://github.com/VirtualGL/virtualgl) — LGPL

See each project's license for details.

## Related Projects

- [tatsuyai713/devcontainer-egl-desktop](https://github.com/tatsuyai713/devcontainer-egl-desktop) — EGL-based version (3 display modes)
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) — Original project
- [selkies-project/selkies](https://github.com/selkies-project/selkies) — WebRTC streaming

## Credits

**Original projects:**
- **Selkies Project:** [github.com/selkies-project](https://github.com/selkies-project)
- **LinuxServer.io:** [github.com/linuxserver](https://github.com/linuxserver)

**This project:**
- **Enhancements:** Two-stage build, non-root execution, UID/GID matching, secure passwords, management scripts, version pinning, multi-GPU/encoder support, Dev Container integration
- **Maintainer:** [@tatsuyai713](https://github.com/tatsuyai713)
