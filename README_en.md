# kde-selkies-webtop-devcontainer

**[日本語版 (README.md)](README.md)**

A containerized Kubuntu (KDE Plasma) desktop environment accessible via browser. Uses Selkies WebRTC streaming to provide a fully functional Linux desktop without VNC/RDP. Supports VS Code Dev Containers.

### Feature Support Matrix (Platforms)

| Environment | GPU Rendering | WebGL/Vulkan | Hardware Encoding | Notes |
|-------------|---------------|--------------|-------------------|-------|
| **Linux + NVIDIA GPU** | ✅ Supported | ✅ Supported | ✅ NVENC | Best performance |
| **Linux + Intel GPU** | ✅ Supported | ✅ Supported | ✅ VA-API (QSV) | Integrated GPU OK |
| **Linux + AMD GPU** | ✅ Supported | ✅ Supported | ✅ VA-API | RDNA/GCN supported |
| **WSL2 + NVIDIA GPU** | ❌ Software | ❌ Software only | ✅ NVENC | Tested on WSL2 |
| **macOS (Docker)** | ❌ Not supported | ❌ Software only | ❌ Not supported | VM limitation |

---

## Quick Start

```bash
# 1. Build user image (1-2 minutes)
# The base image is pulled automatically from GHCR
./build-user-image.sh                                         # English environment
./build-user-image.sh -l ja                                   # Japanese environment
./build-user-image.sh -u 22.04                                # Ubuntu 22.04

# 2. Start container
./start-container.sh                                          # Software rendering
./start-container.sh --gpu nvidia --all                       # NVIDIA GPU (all GPUs)
./start-container.sh --gpu nvidia --num 0                     # NVIDIA GPU (GPU 0 only)
./start-container.sh --gpu intel                              # Intel GPU
./start-container.sh --gpu amd                                # AMD GPU
./start-container.sh --gpu nvidia-wsl --all                   # WSL2 + NVIDIA

# 3. Access via browser
# → https://localhost:<10000+UID> (e.g., UID=1000 → https://localhost:11000)
# → http://localhost:<20000+UID>  (e.g., UID=1000 → http://localhost:21000)

# 4. Save your changes (IMPORTANT! Always do this before removing container)
./commit-container.sh

# 5. Stop
./stop-container.sh                    # Stop (container persists, can restart)
./stop-container.sh --rm               # Stop and remove (only after commit!)
```

That's it! 🎉

### Using VS Code Dev Container

```bash
# 1. Generate Dev Container configuration
./create-devcontainer-config.sh

# 2. Open in VS Code
# In VS Code, press "F1" → select "Dev Containers: Reopen in Container"

# 3. The workspace will automatically open inside the container
# Access the desktop via browser at https://localhost:<displayed-port>
```

---

## 🚀 Key Improvements in This Project

### Architecture Improvements

- **🏗️ Two-Stage Build System:** Split into base (5-10 GB) and user images (~100 MB, 1-2 min build)
  - Base image contains all system packages and desktop environment
  - User image adds your specific user with matching UID/GID
  - No more 30-60 minute builds for every user!

- **🔒 Non-Root Container Execution:** Containers run with user privileges by default
  - Removed all `fakeroot` hacks and privilege escalation workarounds
  - Proper permission separation between system and user operations
  - Sudo access available when needed for specific operations

- **📁 Automatic UID/GID Matching:** File permissions work seamlessly
  - User image matches your host UID/GID automatically
  - Mounted host directories have correct ownership
  - No more "permission denied" errors on shared folders

### User Experience Enhancements

- **🔐 Secure Password Management:** Environment variable for password input
  - No plain text passwords in commands
  - Passwords stored securely in the image

- **💻 Ubuntu Desktop Standard Environment:** Full `.bashrc` configuration
  - Colored prompt with Git branch detection
  - History optimization (ignoredups, append mode, timestamps)
  - Useful aliases (ll, la, grep colors, etc.)

- **🎮 Flexible GPU Selection:** Clear command arguments
  - `--all` - Use all available GPUs
  - `--num 0,1` - Specific GPU devices
  - `--gpu none` - Software rendering

### Developer Experience

- **📦 Version Pinning:** Reproducible builds guaranteed
  - VirtualGL 3.1.4, Selkies 1.6.2
  - No more "it worked yesterday" issues

- **🛠️ Complete Management Scripts:** Shell scripts for all operations
  - `build-user-image.sh` - Build with password
  - `start-container.sh [--gpu <type>]` - Start with GPU selection
  - `stop/shell-container.sh` - Lifecycle management
  - `commit-container.sh` - Save your changes

- **🌐 Multi-Language Support:** Japanese language environment available
  - Pass `-l ja` argument during build for Japanese input (Mozc)
  - Automatic timezone (Asia/Tokyo) and locale (ja_JP.UTF-8) configuration
  - fcitx input method framework included
  - English remains the default

### Why This Project?

| Original Projects | This Project |
|------------------|--------------|
| Pull-ready image | Local build (1-2 min) |
| Root container | User-privilege container |
| Manual UID/GID setup | Automatic matching |
| Password in command | Environment variable |
| Generic bash | Ubuntu Desktop bash |
| GPU auto-detected | GPU explicitly selected |
| Version drift | Version pinned |
| English only | Multi-language (EN/JP) |

---

## Table of Contents

- [System Requirements](#system-requirements)
- [Two-Stage Build System](#two-stage-build-system)
- [Intel/AMD GPU Host Setup](#intelamd-gpu-host-setup)
- [Setup (Typical Use)](#setup-typical-use)
- [Usage](#usage)
- [Appendix: Build Base Image (For Developers)](#appendix-build-base-image-for-developers)
- [Appendix: Scripts Reference](#appendix-scripts-reference)
- [Appendix: Configuration](#appendix-configuration)
- [Appendix: HTTPS/SSL](#appendix-httpsssl)
- [Troubleshooting](#troubleshooting)
- [Known Limitations](#known-limitations)
- [Appendix: Advanced Topics](#appendix-advanced-topics)

---

## System Requirements

### Required
- **Docker** 20.10 or later (Docker Desktop 4.0+)
- **8GB+ RAM** (16GB recommended)
- **20GB+ free disk space**

### GPU (Optional, for hardware acceleration)
- **NVIDIA GPU** ✅ Tested
  - Driver version 470 or later
  - Maxwell generation or newer
  - NVIDIA Container Toolkit installed
- **Intel GPU** ✅ Tested
  - Intel integrated graphics (HD Graphics, Iris, Arc)
  - Quick Sync Video support
  - VA-API drivers included in container
  - **Host setup required** (see below)
- **AMD GPU** ⚠️ Partially Tested
  - Radeon graphics with VCE/VCN encoder
  - VA-API drivers included in container
  - **Host setup required** (see below)

## Two-Stage Build System

This project uses a two-stage build approach for fast setup and proper file permissions:

```
┌─────────────────────────┐
│   Base Image (5-10 GB)  │  ← Build once (30-60 minutes)
│  • All system packages  │
│  • Desktop environment  │
│  • Pre-installed apps   │
└────────────┬────────────┘
             │
             ↓ builds from
┌────────────┴────────────┐
│ User Image (~100 MB)    │  ← You build this (1-2 minutes)
│  • Your username        │
│  • Your UID/GID         │
│  • Your password        │
└─────────────────────────┘
```

**Benefits:**

- ✅ **Fast Setup:** No 30-60 minute build wait
- ✅ **Proper Permissions:** Files match your host UID/GID
- ✅ **Easy Updates:** Build new base image, rebuild user image

**Why UID/GID Matching Matters:**

- When you mount host directories (like `$HOME`), files need matching ownership
- Without matching UID/GID, you get permission errors
- The user image automatically matches your host credentials

---

## Intel/AMD GPU Host Setup

If you plan to use hardware encoding (VA-API) with Intel or AMD GPUs, host-side setup is required:

### 1. Add User to video/render Groups

For the container to access GPU devices (`/dev/dri/*`), the host user must be a member of the `video` and `render` groups:

```bash
# Add user to video/render groups
sudo usermod -aG video,render $USER

# Logout and re-login or reboot to apply group changes
# Verify:
groups
# Confirm output includes "video" and "render"
```

### 2. Install VA-API Drivers (Intel)

For Intel GPU hardware encoding:

```bash
# Install VA-API tools and Intel driver
sudo apt update
sudo apt install vainfo intel-media-va-driver-non-free

# Verify installation (check for H.264 encoding support):
vainfo
# Confirm output includes "VAProfileH264Main : VAEntrypointEncSlice" etc.
```

### 3. Install VA-API Drivers (AMD)

For AMD GPU hardware encoding:

```bash
# Install VA-API tools and AMD driver
sudo apt update
sudo apt install vainfo mesa-va-drivers

# Verify installation:
vainfo
# Confirm output includes "VAProfileH264Main : VAEntrypointEncSlice" etc.
```

**Notes:**
- NVIDIA GPUs do not require this setup
- If VA-API works correctly on the host, it will automatically work in the container
- Always logout/re-login or reboot after group changes

---

## Setup (Typical Use)

The base image is pulled automatically from GHCR, so no build is required for normal use.

### Build User Image

Create your personal image with matching UID/GID (1-2 minutes):

```bash
# English (default)
./build-user-image.sh

# Japanese
./build-user-image.sh -l ja
```

Note: Prefix with `USER_PASSWORD=...` to skip the interactive prompt.

**Optional: Customization**

```bash
# Use Ubuntu 22.04
./build-user-image.sh -u 22.04

# Different version
./build-user-image.sh -v 2.0.0

# Use a different base image
./build-user-image.sh -b my-custom-base:1.0.0
```

---

## Usage

### Starting the Container

The `start-container.sh` script uses GPU and optional arguments:

```bash
# Syntax: ./start-container.sh [--gpu <type>] [options]
# Default: Software rendering if no options specified

# NVIDIA GPU options:
./start-container.sh --gpu nvidia --all              # Use all available NVIDIA GPUs
./start-container.sh --gpu nvidia --num 0            # Use NVIDIA GPU 0 only
./start-container.sh --gpu nvidia --num 0,1          # Use NVIDIA GPU 0 and 1

# Intel/AMD GPU options:
./start-container.sh --gpu intel                     # Use Intel integrated GPU (Quick Sync Video)
./start-container.sh --gpu amd                       # Use AMD GPU (VCE/VCN)

# WSL2 NVIDIA:
./start-container.sh --gpu nvidia-wsl --all          # NVIDIA GPU on WSL2

# Software rendering:
./start-container.sh                                 # No GPU (default)
./start-container.sh --gpu none                      # Explicitly specify no GPU

# Resolution and DPI:
./start-container.sh --gpu nvidia --all -r 3840x2160 -d 192    # 4K HiDPI
./start-container.sh -r 2560x1440 -d 144                       # WQHD
```

**UID-Based Port Assignment (Multi-User Support):**

Ports are automatically assigned based on your user ID to enable multiple users on the same host:

- **HTTPS Port**: `10000 + UID` (e.g., UID 1000 → port 11000)
- **HTTP Port**: `20000 + UID` (e.g., UID 1000 → port 21000)
- **TURN Port**: `3000 + UID` (e.g., UID 1000 → port 4000)

Access via: `https://localhost:${HTTPS_PORT}` (e.g., `https://localhost:11000` for UID 1000)

**Remote Access (LAN/WAN):**

TURN server is **enabled by default** for remote access without additional options:

- TURN server relays WebRTC connections
- Auto-detects LAN IP address
- Access from remote PC: `https://<host-ip>:<https-port>`

**Container Features:**

- **Container persistence:** Not removed when stopped (can restart or commit)
- **Hostname:** Set to `Docker-$(hostname)`
- **Host home mount:** Available at `~/host_home`
- **Container name:** `linuxserver-kde-{username}`

### Saving Changes (Important!)

If you've installed software or made changes:

```bash
# Save container state to image
./commit-container.sh
```

**Important Notes:**

- ⚠️ **Always commit before `./stop-container.sh --rm`** - Changes are lost if you remove without committing
- ✅ The image name format is `webtop-kde-{username}-{arch}:{version}`
- ✅ Committed images persist even after container deletion
- ✅ Next startup automatically uses the committed image

**Workflow Example:**

```bash
# 1. Work in container, install software, configure settings
./shell-container.sh
# ... install packages, configure environment ...
exit

# 2. Save your changes to the image
./commit-container.sh

# 3. Stop and remove container safely (changes are saved in image)
./stop-container.sh --rm

# 4. Next startup uses the committed image with all your changes
./start-container.sh --gpu intel
```

### Stopping the Container

```bash
# Stop (persists for restart or commit)
./stop-container.sh

# Stop and remove
./stop-container.sh --rm
# or
./stop-container.sh -r
```

---

## Appendix: Build Base Image (For Developers)

The base image only needs to be built once (30-60 minutes):

```bash
# Default repository: ghcr.io/tatsuyai713/webtop-kde
# Auto-detect host architecture
./files/build-base-image.sh                         # Ubuntu 24.04 (default)
./files/build-base-image.sh -u 22.04                # Ubuntu 22.04

# Or specify explicitly
./files/build-base-image.sh -a amd64                # Intel/AMD 64-bit
./files/build-base-image.sh -a arm64                # Apple Silicon / ARM
./files/build-base-image.sh -a amd64 -u 22.04       # AMD64 + Ubuntu 22.04

# Build without cache (if having issues)
./files/build-base-image.sh --no-cache

# Push to GHCR (uses the default repository)
./files/push-base-image.sh

# Use a custom repository name
IMAGE_NAME=ghcr.io/tatsuyai713/your-base ./files/build-base-image.sh
IMAGE_NAME=ghcr.io/tatsuyai713/your-base ./files/push-base-image.sh
```

---

## Appendix: Scripts Reference

### Core Scripts

| Script | Description | Usage |
|--------|-------------|-------|
| `files/build-base-image.sh` | Build the base image | `./files/build-base-image.sh [-a arch]` |
| `build-user-image.sh` | Build user-specific image | `./build-user-image.sh [-l ja]` |
| `start-container.sh` | Start the desktop container | `./start-container.sh [--gpu <type>]` |
| `stop-container.sh` | Stop the container | `./stop-container.sh [--rm]` |

### Management Scripts

| Script | Description | Usage |
|--------|-------------|-------|
| `shell-container.sh` | Access container shell | `./shell-container.sh` |
| `commit-container.sh` | Save container changes to image | `./commit-container.sh` |
| `files/push-base-image.sh` | Push base image to GHCR | `./files/push-base-image.sh` |

### GPU Options Details

```bash
./start-container.sh [options]

GPU Selection:
  -g, --gpu <vendor>    GPU vendor: none|nvidia|nvidia-wsl|intel|amd
  --all                 Use all GPUs (for nvidia/nvidia-wsl)
  --num <list>          Comma-separated GPU list (for nvidia, not supported on WSL)

GPU Examples:
  --gpu nvidia --all          # NVIDIA GPU - all available
  --gpu nvidia --num 0,1      # NVIDIA GPU - specific GPUs
  --gpu nvidia-wsl --all      # NVIDIA on WSL2
  --gpu intel                 # Intel integrated/discrete GPU (VA-API)
  --gpu amd                   # AMD GPU (VA-API + ROCm if available)
  --gpu none                  # Software rendering only

Other Options:
  -n <name>             Container name
  -r <WxH>              Resolution (e.g., 1920x1080)
  -d <dpi>              DPI (e.g., 96, 144, 192)
  -s <ssl_dir>          SSL certificate directory
```

---

## Appendix: Configuration

### Display Settings

```bash
# Resolution and DPI
./start-container.sh -r 1920x1080 -d 96              # Standard
./start-container.sh -r 2560x1440 -d 144             # WQHD HiDPI
./start-container.sh -r 3840x2160 -d 192             # 4K HiDPI
```

### Video Encoding

**Available Encoders:**

| Encoder | GPU | Quality | CPU Load |
|---------|-----|---------|----------|
| `nvh264enc` | NVIDIA NVENC | High | Low |
| `vah264enc` | Intel/AMD VA-API | High | Low |
| `x264enc` | Software | Medium | High |

Encoder is automatically selected based on `--gpu` option.

### Audio Settings

**Audio Support:**

| Feature | Support | Technology |
|---------|---------|------------|
| Speaker output | ✅ Built-in | WebRTC (browser native) |
| Microphone input | ✅ Built-in | WebRTC (browser native) |

Selkies streams bidirectional audio to the browser via WebRTC.

---

## Appendix: HTTPS/SSL

### SSL Certificate Setup

```bash
# 1. Create ssl/ directory
mkdir -p ssl

# 2. Place certificates
cp /path/to/your/cert.pem ssl/
cp /path/to/your/key.pem ssl/cert.key

# 3. Start container (auto-detects ssl/ folder)
./start-container.sh --gpu nvidia --all
```

### Self-Signed Certificate Generation

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/cert.key -out ssl/cert.pem \
  -subj "/C=US/ST=State/L=City/O=Dev/CN=localhost"
```

### Certificate Priority

The `start-container.sh` script auto-detects certificates in this order:

1. `ssl/cert.pem` and `ssl/cert.key`
2. Environment variable `SSL_DIR`
3. Uses image default certificate if none found

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs linuxserver-kde-$(whoami)

# Check if image exists
docker images | grep webtop-kde

# Rebuild user image
./build-user-image.sh

# Check if port is in use
sudo netstat -tulpn | grep -E "11000|21000"
```

### GPU Not Detected

```bash
# NVIDIA
./shell-container.sh
nvidia-smi

# Intel/AMD
./shell-container.sh
ls -la /dev/dri/
vainfo

# Check Docker GPU access
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### Permission Issues

```bash
# Check UID match
id  # on host
./shell-container.sh
id  # inside container

# If UID/GID mismatch, rebuild user image
./build-user-image.sh
```

### Black Screen / Desktop Not Showing

```bash
# Check logs
docker logs linuxserver-kde-$(whoami)

# Check plasmashell status
docker exec linuxserver-kde-$(whoami) pgrep -af plasmashell

# Check runtime directory
docker exec linuxserver-kde-$(whoami) ls -la /run/user/$(id -u)
```

**Causes and Solutions:**
- `/run/user/<uid>` doesn't exist / wrong permissions → Restart container
- plasmashell crashed → Restart container

### WebGL/Vulkan Not Working

```bash
# OpenGL info
docker exec linuxserver-kde-$(whoami) glxinfo | head -30

# Vulkan info
docker exec linuxserver-kde-$(whoami) vulkaninfo | head -50
```

**For macOS:** Due to Docker VM limitations, GPU acceleration is not available. Works with software rendering.

### No Audio

```bash
# Check PulseAudio server
docker exec linuxserver-kde-$(whoami) pactl info

# List sinks
docker exec linuxserver-kde-$(whoami) pactl list sinks short
```

**Solutions:**
- Check browser audio permissions
- Use HTTPS connection (some browsers block audio over HTTP)

---

## Known Limitations

### Vulkan Limitation

- Xvfb does not support DRI3, so Vulkan applications cannot present frames
- VirtualGL-based OpenGL applications work normally

### macOS Limitation

- Docker Desktop for Mac runs containers inside a Linux VM, so Apple GPU (Metal) access is not possible
- WebGL/Vulkan runs via software rendering (llvmpipe)
- Use Linux native or WSL2 if hardware acceleration is needed

### WSL2 GPU Notes

- Only NVIDIA is supported on WSL2
- Rendering is software (llvmpipe), so WebGL/Vulkan are software-only

---

## Appendix: Advanced Topics

### Environment Variables Reference

<details>
<summary>Click to expand environment variables list</summary>

#### Container Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `CONTAINER_NAME` | Container name | `linuxserver-kde-$(whoami)` |
| `IMAGE_BASE` | Image base name | `webtop-kde` |
| `IMAGE_VERSION` | Image version | `1.0.0` |

#### Display

| Variable | Description | Default |
|----------|-------------|---------|
| `RESOLUTION` | Resolution | `1920x1080` |
| `DPI` | DPI setting | `96` |

#### GPU

| Variable | Description | Default |
|----------|-------------|---------|
| `GPU_VENDOR` | GPU vendor | `none` |

#### Network

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT_SSL_OVERRIDE` | HTTPS port override | `UID+10000` |
| `PORT_HTTP_OVERRIDE` | HTTP port override | `UID+20000` |
| `PORT_TURN_OVERRIDE` | TURN port override | `UID+3000` |
| `HOST_IP` | Host IP for TURN server | Auto-detect |

</details>

### Project Structure

```
devcontainer-ubuntu-kde-selkies-for-mac/
├── build-user-image.sh           # Build user image
├── start-container.sh            # Start container
├── stop-container.sh             # Stop container
├── shell-container.sh            # Shell access
├── commit-container.sh           # Save changes
├── ssl/                          # SSL certificates (auto-detected)
│   ├── cert.pem
│   └── cert.key
└── files/                        # System files
    ├── build-base-image.sh       # Build base image
    ├── push-base-image.sh        # Push base image
    ├── linuxserver-kde.base.dockerfile   # Base image definition
    ├── linuxserver-kde.user.dockerfile   # User image definition
    ├── alpine-root/              # s6-overlay configuration
    ├── kde-root/                 # KDE configuration
    └── ubuntu-root/              # Ubuntu configuration
```

### Version Pinning

External dependencies are pinned to specific versions for reproducible builds:

- **VirtualGL:** 3.1.4
- **Selkies GStreamer:** 1.6.2

These are defined in [files/linuxserver-kde.base.dockerfile](files/linuxserver-kde.base.dockerfile) as build arguments.

---

## License

**Main Project:**

This project is based on multiple open source projects:
- [linuxserver/webtop](https://github.com/linuxserver/docker-webtop) - GPL-3.0
- [selkies-project/selkies](https://github.com/selkies-project/selkies) - MPL-2.0
- [VirtualGL](https://github.com/VirtualGL/virtualgl) - LGPL

See each project's license for details.

---

## Related Projects

- [tatsuyai713/devcontainer-egl-desktop](https://github.com/tatsuyai713/devcontainer-egl-desktop) - EGL-based version (3 display modes)
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) - Original project
- [selkies-project/selkies](https://github.com/selkies-project/selkies) - WebRTC streaming

---

## Credits

### Original Projects

- **Selkies Project:** [github.com/selkies-project](https://github.com/selkies-project)
- **LinuxServer.io:** [github.com/linuxserver](https://github.com/linuxserver)

### This Project

- **Enhancements:** Two-stage build system, non-root execution, UID/GID matching, secure password management, management scripts, version pinning, multi-GPU support
- **Maintainer:** [@tatsuyai713](https://github.com/tatsuyai713)
