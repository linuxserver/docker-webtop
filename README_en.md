# devcontainer-ubuntu-kde-selkies-for-mac

A containerized Kubuntu (KDE Plasma) desktop environment accessible via browser. Uses Selkies WebRTC streaming to provide a fully functional Linux desktop without VNC/RDP.

---

## Table of Contents

- [Features](#features)
- [System Requirements](#system-requirements)
- [Architecture and GPU Support](#architecture-and-gpu-support)
- [Quick Start](#quick-start)
- [Detailed Usage](#detailed-usage)
- [GPU Acceleration](#gpu-acceleration)
- [Script Reference](#script-reference)
- [Environment Variables](#environment-variables)
- [Troubleshooting](#troubleshooting)
- [Technical Details](#technical-details)

---

## Features

### Core Features
- 🖥️ **Full KDE Desktop**: Complete desktop environment based on Kubuntu 24.04
- 🌐 **Browser Access**: No VNC/RDP client needed thanks to Selkies WebRTC
- 🔐 **Secure Authentication**: Form-based auth with cookie sessions (not Basic auth)
- 🔊 **Audio Support**: Bidirectional audio (speakers/microphone) streaming to browser
- 📁 **Host Home Sharing**: Host `$HOME` mounted at `/home/<user>/host_home`

### Platform Support
- 🍎 **macOS Support**: Both Apple Silicon (arm64) and Intel (amd64)
- 🐧 **Linux Support**: Native GPU acceleration (NVIDIA/Intel/AMD)
- 🪟 **WSL2 Support**: Hardware encoding with NVIDIA GPU on Windows

### Internationalization
- 🇯🇵 **Japanese Environment**: `-l ja` installs Japanese locale, fcitx+mozc, jp106 keyboard, Noto fonts
- 🌍 **Other Languages**: `-l en` (English) is default, additional locales can be added

---

## System Requirements

### Required
- Docker Engine 20.10+ or Docker Desktop 4.0+
- 8GB+ RAM (16GB recommended)
- 20GB+ free disk space

### Recommended
- GPU (NVIDIA/Intel/AMD) - for hardware acceleration
- Latest Chrome/Edge/Firefox (WebRTC-compatible browser)

---

## Architecture and GPU Support

### GPU Support Matrix

| Environment | GPU Rendering | WebGL/Vulkan | Hardware Encoding | Notes |
|-------------|---------------|--------------|-------------------|-------|
| **Linux + NVIDIA GPU** | ✅ Full | ✅ Native | ✅ NVENC | Best performance |
| **Linux + Intel GPU** | ✅ Full | ✅ Native | ✅ VA-API (QSV) | Integrated GPU OK |
| **Linux + AMD GPU** | ✅ Full | ✅ Native | ✅ VA-API | RDNA/GCN supported |
| **WSL2 + NVIDIA GPU** | ✅ Supported | ✅ via DirectML | ✅ NVENC | Windows integration |
| **WSL2 + Intel/AMD** | ⚠️ Limited | ❌ Software only | ❌ Not supported | No VA-API |
| **macOS (Docker)** | ❌ Not supported | ❌ Software only | ❌ Not supported | VM limitation |
| **NVIDIA Jetson** | ⚠️ Partial | ✅ Native | ❌ Not supported | nvv4l2 not supported |

### Important Notes

#### macOS (Apple Silicon / Intel)
Docker Desktop for Mac runs containers inside a **Linux VM**, so Apple GPU (Metal) access is not possible. WebGL/Vulkan runs via software rendering (llvmpipe).
- ✅ Works (but slow)
- ❌ No GPU acceleration
- 💡 Use Linux native or WSL2 if hardware acceleration is needed

#### WSL2
WSL2 GPU passthrough works via `/dev/dxg` device and DirectX 12.
- **NVIDIA GPU**: Full support (CUDA, NVENC, Vulkan)
- **Intel/AMD GPU**: DirectML for ML only, no VA-API

---

## Quick Start

### 1. Build Base Image

```bash
# Apple Silicon Mac / ARM64 Linux
./build-base-image.sh -a arm64

# Intel Mac / AMD64 Linux / WSL2
./build-base-image.sh -a amd64

# Build without cache (if having issues)
./build-base-image.sh -a amd64 --no-cache
```

### 2. Build User Image

```bash
# Japanese environment
USER_PASSWORD=yourpassword ./build-user-image.sh -a arm64 -l ja

# English environment
USER_PASSWORD=yourpassword ./build-user-image.sh -a amd64 -l en
```

### 3. Start Container

```bash
# Basic startup (software rendering)
./start-container.sh -r 1920x1080

# With NVIDIA GPU (Linux)
./start-container.sh -g nvidia --all -r 1920x1080

# With Intel GPU (Linux)
./start-container.sh -g intel -r 1920x1080

# With AMD GPU (Linux)
./start-container.sh -g amd -r 1920x1080

# WSL2 + NVIDIA GPU
./start-container.sh -g nvidia-wsl -r 1920x1080
```

### 4. Access via Browser

Ports are automatically calculated based on UID (user ID):
- **HTTPS**: `https://localhost:<UID+10000>` (e.g., UID=1000 → port 11000)
- **HTTP**: `http://localhost:<UID+20000>` (e.g., UID=1000 → port 21000)

Log in with the username and password set during image build.

### 5. Stop

```bash
# Stop container (preserve state)
./stop-container.sh

# Stop and remove container
./stop-container.sh --rm
```

---

## Detailed Usage

### Persistence and VM-like Usage

#### Preserving Container State
```bash
# Stop (without removing)
./stop-container.sh

# Resume later
./start-container.sh
```

#### Committing to Image
Persist installed apps and customizations:
```bash
./commit-container.sh
# → Saved as webtop-kde-<user>-<arch>:<version>
```

#### Home Directory Persistence
Host `$HOME` is mounted at `/home/<user>/host_home`.
Save important files here for persistence.

### Resolution and DPI Settings

```bash
# 4K HiDPI
./start-container.sh -r 3840x2160 -d 192

# 1080p standard DPI
./start-container.sh -r 1920x1080 -d 96

# Custom
./start-container.sh -r 2560x1440 -d 144
```

### Using SSL Certificates

To avoid self-signed certificate warnings, use your own certificates:

```bash
# Place cert.pem and cert.key in ssl/ directory
mkdir -p ssl
cp /path/to/your/cert.pem ssl/
cp /path/to/your/key.pem ssl/cert.key

# Auto-mounted on startup
./start-container.sh

# Or specify explicitly
./start-container.sh -s /path/to/ssl/dir
```

### Container Shell Access

```bash
# Enter shell as user
./shell-container.sh

# Enter shell as root
docker exec -it -u root <container-name> bash
```

---

## GPU Acceleration

### NVIDIA GPU (Linux)

```bash
# Use all GPUs
./start-container.sh -g nvidia --all

# Use specific GPU (by device number)
./start-container.sh -g nvidia --num 0
./start-container.sh -g nvidia --num 0,1
```

**Prerequisites**:
- NVIDIA Driver 470+
- NVIDIA Container Toolkit (nvidia-docker2)

**Verification**:
```bash
# Inside container
nvidia-smi
glxinfo | grep "OpenGL renderer"
vulkaninfo | grep "deviceName"
```

### Intel GPU (Linux)

```bash
./start-container.sh -g intel
```

**Prerequisites**:
- Intel GPU (6th Gen or later recommended)
- `i915` driver
- `/dev/dri` devices

**Verification**:
```bash
# Inside container
vainfo
glxinfo | grep "OpenGL renderer"
```

### AMD GPU (Linux)

```bash
./start-container.sh -g amd
```

**Prerequisites**:
- AMD GPU (GCN/RDNA)
- `amdgpu` driver
- `/dev/dri` and `/dev/kfd` devices

**Verification**:
```bash
# Inside container
vainfo
radeontop
vulkaninfo | grep "deviceName"
```

### WSL2 + NVIDIA GPU

```bash
./start-container.sh -g nvidia-wsl
```

**Prerequisites**:
- Windows 10 21H2+ or Windows 11
- WSL2 (version 2)
- NVIDIA GPU + Windows driver (CUDA-enabled version)

**Note**: WSL2 only supports `--gpus all`. Individual GPU selection (`--num`) is not available.

### Software Rendering

Software rendering (llvmpipe) is automatically used in environments without GPU or on macOS:

```bash
./start-container.sh  # no -g option, or -g none
```

---

## Script Reference

### build-base-image.sh

Builds the base image.

```bash
./build-base-image.sh [options]

Options:
  -a, --arch <arch>     Architecture (amd64|arm64) [default: host arch]
  -p, --platform <plat> Docker platform (e.g., linux/arm64)
  -v, --version <ver>   Image version [default: 1.0.0]
  --no-cache            Build without cache
  -h, --help            Show help
```

### build-user-image.sh

Builds the user image.

```bash
USER_PASSWORD=<password> ./build-user-image.sh [options]

Options:
  -a, --arch <arch>     Architecture (amd64|arm64)
  -b, --base <image>    Base image name [default: auto-detect]
  -l, --lang <lang>     Language (en|ja) [default: en]
  -v, --version <ver>   Image version
  -h, --help            Show help

Environment Variables:
  USER_PASSWORD         Required. Login password
```

### start-container.sh

Starts the container.

```bash
./start-container.sh [options]

Options:
  -n <name>             Container name [default: linuxserver-kde-<user>]
  -i <base>             Image base name
  -t <version>          Image version
  -r <WxH>              Resolution (e.g., 1920x1080) [default: 1920x1080]
  -d <dpi>              DPI [default: 96]
  -p <platform>         Docker platform
  -s <ssl_dir>          SSL certificate directory
  -g, --gpu <vendor>    GPU vendor: none|nvidia|nvidia-wsl|intel|amd
  --all                 Use all NVIDIA GPUs (requires -g nvidia)
  --num <list>          NVIDIA GPU device numbers (requires -g nvidia)
  -h, --help            Show help
```

### stop-container.sh

Stops the container.

```bash
./stop-container.sh [options]

Options:
  --rm, -r              Remove container after stopping
```

### shell-container.sh

Access the container shell.

```bash
./shell-container.sh
```

### commit-container.sh

Save running container as an image.

```bash
./commit-container.sh
```

---

## Environment Variables

### Build Time

| Variable | Description | Default |
|----------|-------------|---------|
| `USER_PASSWORD` | Login password (required) | - |
| `IMAGE_BASE` | Image base name | `webtop-kde` |
| `IMAGE_VERSION` | Image version | `1.0.0` |

### Runtime

| Variable | Description | Default |
|----------|-------------|---------|
| `RESOLUTION` | Screen resolution | `1920x1080` |
| `DPI` | Screen DPI | `96` |
| `GPU_VENDOR` | GPU vendor | `none` |
| `PORT_SSL_OVERRIDE` | HTTPS port override | `UID+10000` |
| `PORT_HTTP_OVERRIDE` | HTTP port override | `UID+20000` |
| `HOST_IP` | Host IP for TURN server | auto-detect |

### Inside Container

| Variable | Description |
|----------|-------------|
| `DISPLAY` | X display (`:1`) |
| `SELKIES_ENCODER` | Video encoder (`nvh264enc`/`vah264enc`/`x264enc`) |
| `ENABLE_NVIDIA` | Enable NVIDIA GPU support |
| `VGL_DISPLAY` | VirtualGL display device |
| `LIBVA_DRIVER_NAME` | VA-API driver name |

---

## Troubleshooting

### Black Screen / Desktop Not Showing

```bash
# Check plasmashell status
docker exec <container-name> pgrep -af plasmashell

# Check runtime directory
docker exec <container-name> ls -la /run/user/$(id -u)

# Check logs
docker logs <container-name>
```

**Causes and Solutions**:
- `/run/user/<uid>` doesn't exist or has wrong permissions → Restart container
- plasmashell crashed → Kill via `docker exec`, wait for auto-restart

### GPU Not Detected

```bash
# NVIDIA
docker exec <container-name> nvidia-smi

# Intel/AMD
docker exec <container-name> ls -la /dev/dri/
docker exec <container-name> vainfo

# Check groups
docker exec <container-name> id
```

**Causes and Solutions**:
- `/dev/dri` not mounted → Specify `-g intel` or `-g nvidia --all`
- Missing group permissions → Check `video`/`render` group membership
- Driver not installed → Install driver on host

### WebGL/Vulkan Not Working

```bash
# OpenGL info
docker exec <container-name> glxinfo | head -30

# Vulkan info
docker exec <container-name> vulkaninfo | head -50
```

**macOS**: GPU acceleration not available due to Docker VM limitations. Software rendering is used.

### No Audio

```bash
# Check PulseAudio server
docker exec <container-name> pactl info

# List sinks
docker exec <container-name> pactl list sinks short
```

**Solutions**:
- Check browser audio permissions
- Use HTTPS connection (some browsers block audio over HTTP)

### Cannot Access Host Home

Host `$HOME` with restrictive permissions (e.g., `750`) may not be accessible from container.

**Solutions**:
```bash
# Add ACL on host
setfacl -m u:$(id -u):rx $HOME

# Or mount a different directory
docker run ... -v /path/to/share:/home/<user>/shared ...
```

### Connection Drops / Unstable WebRTC

```bash
# Check TURN server status
docker exec <container-name> pgrep -af turnserver
```

**Solutions**:
- Open TURN port (default: UID+3000) in firewall
- Use HTTPS connection

---

## Technical Details

### Image Structure

```
webtop-kde-base-<arch>:<version>
├── Ubuntu 24.04 (Noble)
├── s6-overlay (init system)
├── KDE Plasma Desktop
├── Selkies (WebRTC streaming)
├── Selkies-GStreamer (AMD64 only, hardware encoding)
├── VirtualGL (3D acceleration)
├── PulseAudio (audio)
├── nginx (web server)
├── coturn (TURN server, AMD64 only)
└── Various GPU drivers/libraries

webtop-kde-<user>-<arch>:<version>
├── Inherits from webtop-kde-base
├── User creation (host UID/GID)
├── Group configuration (video, render, sudo, etc.)
├── Language settings (ja: fcitx+mozc, fonts)
└── Authentication settings (web-auth.json)
```

### Network Ports

| Port | Purpose | Formula |
|------|---------|---------|
| 3000 | HTTP (inside container) | - |
| 3001 | HTTPS (inside container) | - |
| UID+10000 | HTTPS (host) | e.g., 11000 |
| UID+20000 | HTTP (host) | e.g., 21000 |
| UID+3000 | TURN | e.g., 4000 |

### Video Encoders

| Encoder | GPU | Quality | CPU Load |
|---------|-----|---------|----------|
| `nvh264enc` | NVIDIA NVENC | High | Low |
| `vah264enc` | Intel/AMD VA-API | High | Low |
| `x264enc` | Software | Medium | High |

### Filesystem Layout

```
/config             # User config persistence
/home/<user>        # User home
  └── host_home/    # Host $HOME mount point
/run/user/<uid>     # XDG runtime (DBus, Qt)
/opt/gstreamer      # GStreamer (AMD64)
/usr/share/selkies  # Selkies web frontend
```

---

## License

This project is based on multiple open source projects:
- [linuxserver/webtop](https://github.com/linuxserver/docker-webtop) - GPL-3.0
- [selkies-project/selkies](https://github.com/selkies-project/selkies) - MPL-2.0
- [VirtualGL](https://github.com/VirtualGL/virtualgl) - LGPL

See individual project licenses for details.

---

## Contributing

Issues and Pull Requests are welcome.

---

## Related Projects

- [devcontainer-egl-desktop](./devcontainer-egl-desktop/) - Lightweight EGL-based version (KDE Plasma)
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) - Original project
- [selkies-project/selkies](https://github.com/selkies-project/selkies) - WebRTC streaming
