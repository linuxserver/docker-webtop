# devcontainer-ubuntu-kde-selkies-for-mac

Containerized Ubuntu KDE desktop with Selkies, derived from linuxserver/webtop, tuned for macOS usage with the following advantages:
- macOS-ready for both Apple Silicon (arm64) and amd64; images are tagged with the arch (e.g., `-arm64:latest`, `-amd64:latest`) and `start-container.sh` auto-picks the tag from `--platform` or host arch.
- Runs the desktop as your host user (UID/GID/username), not root; hostname is `Docker-<host>` and appears in PS1.
- Host `$HOME` is mounted to `/home/<user>/host_home` (requires permissive host permissions).
- Split base/user images; supports platform selection (amd64/arm64) and `--no-cache` builds.
- Optional Japanese locale/input (`-l ja` when building user image).
- External SSL cert dir can be mounted for WSS.
- Virtual PulseAudio sinks auto-created for streaming (selkies).

## Quick Start
1. Build the base image  
   `./build-base-image.sh --no-cache` (optional: `-a amd64|arm64`, `-p linux/amd64|linux/arm64`)
2. Build the user image (prompts for your user password)  
   `./build-user-image.sh --no-cache [-l en|ja]`  
   Tags created: `webtop-kde-<user>-<arch>:latest` and `...:<arch>`
3. Start the container  
   `./start-container.sh` (auto-uses `-<arch>-latest` based on host or `-p`)  
   - Resolution/DPI: `./start-container.sh -r 1920x1080 -d 144`  
   - External SSL certs: `./start-container.sh -s /path/to/ssl` (expects `cert.pem` and `cert.key`)  
   - Ports: HTTPS on `UID+10000 -> 3001`, HTTP on `UID+20000 -> 3000` (override via `PORT_SSL_OVERRIDE` / `PORT_HTTP_OVERRIDE`)
4. Enter the container shell (starts in your home)  
   `./shell-container.sh`
5. Stop/remove  
   `./stop-container.sh` (`-r` to remove)

## Scripts
- `build-base-image.sh`  
  Builds the base image. Supports `-a/--arch`, `-p/--platform`, `--no-cache`. Tags: `webtop-kde-base-<arch>:latest`.
- `build-user-image.sh`  
  Builds the user image with host UID/GID/username/password. Supports `--no-cache`, `-l/--language en|ja`. Tags: `<image-base>-<user>-<arch>:latest` and `<arch>`.
- `start-container.sh`  
  Starts a container from the user image. Options: `-r` resolution, `-d` DPI, `-p` platform, `-s` SSL dir. Auto-selects `-<arch>-latest` tag from host or `-p` unless `-t` overrides. Mounts host `$HOME` to `/home/<user>/host_home`. Ports: HTTPS `UID+10000`→3001, HTTP `UID+20000`→3000 (override with `PORT_SSL_OVERRIDE` / `PORT_HTTP_OVERRIDE`).
- `stop-container.sh`  
  Stops the container; `-r`/`--rm` also removes it.
- `shell-container.sh`  
  Exec into the running container as the host user (cwd = `/home/<user>`).
- `commit-container.sh`  
  Commits the running container to an arch-suffixed user image (matches current container arch).

## Notes
- If your host `$HOME` has restrictive permissions (e.g., 750), non-root in the container may not access `/home/<user>/host_home`. Adjust host permissions/ACLs or mount a more permissive directory.
- Audio: `svc-selkies` loads two virtual PulseAudio sinks (`output`, `input`) for streaming. Check with `pactl list short sinks`.
