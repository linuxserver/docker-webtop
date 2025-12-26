# devcontainer-ubuntu-kde-selkies-for-mac

Containerized Ubuntu KDE desktop with Selkies, derived from linuxserver/webtop, tuned for macOS usage with the following advantages:
- Works on macOS for both Apple Silicon (arm64) and amd64 via buildx/platform selection.
- Runs the desktop as your host user (UID/GID/username), not root.
- Propagates the host hostname as `Docker-<host>` and uses it in the shell prompt.
- Mounts the host `$HOME` to `/home/<user>/host_home` (usable if host permissions allow).
- Split base/user images; supports platform selection (amd64/arm64) and `--no-cache` builds.
- External SSL cert directory can be mounted for WSS.
- Creates virtual PulseAudio sinks automatically for audio forwarding (used by selkies).

## Quick Start
1. Build the base image  
   `./build-base-image.sh --no-cache` (optionally `-a amd64|arm64`, `-p linux/amd64|linux/arm64`)
2. Build the user image (prompts for your user password)  
   `./build-user-image.sh --no-cache`
3. Start the container  
   `./start-container.sh`  
   - Change resolution/DPI: `./start-container.sh -r 1920x1080 -d 144`  
   - Use external SSL certs: `./start-container.sh -s /path/to/ssl` (expects `cert.pem` and `cert.key`)
4. Enter the container shell (starts in your home)  
   `./shell-container.sh`
5. Stop/remove  
   `./stop-container.sh` (`-r` to remove)

## Scripts
- `build-base-image.sh`  
  Builds the base image. Supports `-a/--arch`, `-p/--platform`, `--no-cache`. Tags: `webtop-kde:base-<arch>-latest`.
- `build-user-image.sh`  
  Builds the user image with host UID/GID/username/password. Supports `--no-cache`. Tags: `<image-base>-<user>:latest`.
- `start-container.sh`  
  Starts a container from the user image. Options: `-r` resolution, `-d` DPI, `-p` platform, `-s` SSL dir. Mounts host `$HOME` to `/home/<user>/host_home`.
- `stop-container.sh`  
  Stops the container; `-r`/`--rm` also removes it.
- `shell-container.sh`  
  Exec into the running container as the host user (cwd = `/home/<user>`).
- `commit-container.sh`  
  Commit the running container to a new image.

## Notes
- If your host `$HOME` has restrictive permissions (e.g., 750), non-root in the container may not access `/home/<user>/host_home`. Adjust host permissions/ACLs or mount a more permissive directory.
- Audio: `svc-selkies` loads two virtual PulseAudio sinks (`output`, `input`) for streaming. Check with `pactl list short sinks`.
