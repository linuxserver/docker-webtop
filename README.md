# devcontainer-ubuntu-kde-selkies-for-mac

Containerized Kubuntu (KDE Plasma) desktop with Selkies streaming, derived from linuxserver/webtop and tuned for macOS (Apple Silicon/Intel).

## Highlights
- Full Kubuntu (KDE Plasma) desktop streamed in-browser via Selkies (no VNC/RDP needed).
- Runs as your host user (UID/GID/username), non-root by default; host `$HOME` mount for persistence.
- One toggle for Japanese environment (`-l ja`): locale, fcitx+mozc, jp106, Noto CJK/emoji.
- Audio-ready: virtual PulseAudio sinks, speaker/mic streaming; optional SSL mount for WSS.
- macOS-friendly (arm64/amd64) images with helper scripts for build/start/stop/shell.
- On macOS you can build/run both arm64 native and amd64 (via buildx/QEMU).

## Image naming
- Base: `webtop-kde-base-amd64:1.0.0`, `webtop-kde-base-arm64:1.0.0`
- User: `webtop-kde-<user>-amd64:1.0.0`, `webtop-kde-<user>-arm64:1.0.0`
  - `build-user-image.sh` auto-picks a local matching base if `-b` is omitted (avoid `latest`).

## Quick start
1) Build base  
   `./build-base-image.sh -a arm64 --no-cache` (Intel: `-a amd64`)
2) Build user  
   `USER_PASSWORD=<pw> ./build-user-image.sh -a arm64 -l ja` (use `-l en` if English only)
3) Start  
   `./start-container.sh -r 1920x1080 -d 120`  
   Ports: HTTP `UID+20000 -> 3000`, HTTPS `UID+10000 -> 3001`
4) Browser  
   - HTTP: `http://localhost:<UID+20000>`  
   - HTTPS: `https://localhost:<UID+10000>` (self-signed or mount `-s /path/to/ssl`)
5) Shell  
   `./shell-container.sh`
6) Stop/remove  
   `./stop-container.sh --rm`
7) Save current state as an image (optional)  
   `./commit-container.sh`

## Persist / VM-like use
- Keep container, restart later: `./stop-container.sh` (no remove) → `./start-container.sh`
- Save state to image: `./commit-container.sh` → `webtop-kde-<user>-<arch>:<version>`
- Home persistence: host `$HOME` mounted at `/home/<user>/host_home`; if host perms are strict (e.g. 750), loosen or mount another dir.

## User/permissions
- Builds with host UID/GID/username and groups: `adm,cdrom,dip,plugdev,lpadmin,lxd,sudo,docker,users,audio,video,render`.
- Runs with same UID/GID; `/home/<user>/host_home` mounts host home.
- Init ensures `/run/user/<uid>` exists (700, owned by user) for DBus/Qt (stabilizes plasmashell).

## Japanese input/display
- `-l ja` installs `language-pack-ja`, fcitx+mozc, jp106 keymap, Noto fonts.
- IM env/autostart via `/etc/profile.d/fcitx.sh` and `~/.xprofile`.

## Audio/video
- Selkies creates virtual PulseAudio sink/source (`output`, `input`) and streams to browser.
- Xvfb + H.264 (CPU) streaming; set resolution/DPI with `start-container.sh -r/-d`.

## Scripts
- `build-base-image.sh` : builds `webtop-kde-base-<arch>:<version>` (`-a/-p/-v/--no-cache`).
- `build-user-image.sh` : builds `webtop-kde-<user>-<arch>:<version>` (`-b` optional, `-l en|ja`).
- `start-container.sh` : start user image (`-r` resolution, `-d` DPI, `-p` platform, `-s` SSL dir, `-t` version).
- `stop-container.sh` : stop (`--rm` to remove).
- `shell-container.sh` : enter shell as the user.
- `commit-container.sh` : commit running container to `webtop-kde-<user>-<arch>:<version>`.

## Troubleshooting
- Black screen: `docker exec <name> pgrep -af plasmashell`; ensure `/run/user/<uid>` exists/owned by user.
- Host home inaccessible: adjust host perms/ACL or mount another dir.
- PackageKit/udisks2 DBus noise: autostart/system services are disabled in startup scripts; rebuild if needed.

---

## ハイライト
- ブラウザでそのまま使える Kubuntu (KDE Plasma) デスクトップを Selkies で配信（VNC/RDP 不要）
- 非 root でホストの UID/GID/ユーザー名で動作、ホスト `$HOME` をマウントして永続化
- 日本語環境は `-l ja` で一括導入（ロケール、fcitx+mozc、jp106、Noto CJK/emoji）
- 音声対応: 仮想 PulseAudio sink/source でスピーカー/マイク配信、SSL マウントで WSS も可能
- macOS フレンドリー（arm64/amd64）なイメージとビルド/起動/停止/シェル用ヘルパー付き
- macOS 上で arm64 ネイティブも amd64（buildx/QEMU 経由）もビルド・実行可能

## イメージ命名
- Base: `webtop-kde-base-amd64:1.0.0`, `webtop-kde-base-arm64:1.0.0`
- User: `webtop-kde-<user>-amd64:1.0.0`, `webtop-kde-<user>-arm64:1.0.0`
  - `build-user-image.sh` は `-b` 未指定ならローカルの一致する base を自動採用（`latest` 非推奨）

## クイックスタート
1) Base ビルド  
   `./build-base-image.sh -a arm64 --no-cache`（Intel は `-a amd64`）
2) User ビルド  
   `USER_PASSWORD=<pw> ./build-user-image.sh -a arm64 -l ja`（英語のみなら `-l en`）
3) 起動  
   `./start-container.sh -r 1920x1080 -d 120`  
   ポート: HTTP `UID+20000 -> 3000`, HTTPS `UID+10000 -> 3001`
4) ブラウザアクセス  
   - HTTP: `http://localhost:<UID+20000>`  
   - HTTPS: `https://localhost:<UID+10000>`（自己署名または `-s /path/to/ssl` で外部証明書）
5) シェル  
   `./shell-container.sh`
6) 停止/削除  
   `./stop-container.sh --rm`
7) 状態をイメージ化（任意）  
   `./commit-container.sh`

## 永続化/VM 的に使う
- コンテナを残して再起動: `./stop-container.sh`（削除なし）→ `./start-container.sh`
- 状態をイメージ化: `./commit-container.sh` → `webtop-kde-<user>-<arch>:<version>` を更新
- ホーム永続化: ホスト `$HOME` を `/home/<user>/host_home` にマウント。権限が厳しい場合は緩和か別ディレクトリを指定。

## ユーザー/権限
- ビルド時にホスト UID/GID/ユーザー名を適用、グループ `adm,cdrom,dip,plugdev,lpadmin,lxd,sudo,docker,users,audio,video,render` を付与
- 起動時も同 UID/GID で動作、`/home/<user>/host_home` をマウント
- init が `/run/user/<uid>` を作成し 700/ユーザー所有に設定（plasmashell 安定化）

## 日本語入力/表示
- `-l ja` で `language-pack-ja`, fcitx+mozc, jp106, Noto フォントを導入
- `/etc/profile.d/fcitx.sh` と `~/.xprofile` で IM 環境変数と自動起動を設定

## 音声/映像
- Selkies が仮想 PulseAudio sink/source (`output`, `input`) を生成しブラウザ配信
- Xvfb + H.264 (CPU) 配信。解像度/DPI は `start-container.sh -r/-d`

## スクリプト
- `build-base-image.sh` : `webtop-kde-base-<arch>:<version>` をビルド（`-a/-p/-v/--no-cache`）
- `build-user-image.sh` : `webtop-kde-<user>-<arch>:<version>` をビルド（`-b` 省略時はローカル base を検出、`-l en|ja`）
- `start-container.sh` : ユーザーイメージを起動（`-r` 解像度, `-d` DPI, `-p` platform, `-s` SSL, `-t` version）
- `stop-container.sh` : 停止（`--rm` で削除）
- `shell-container.sh` : ユーザーでシェルに入る
- `commit-container.sh` : 実行中コンテナを `webtop-kde-<user>-<arch>:<version>` にコミット

## トラブルシュート
- 黒画面: `docker exec <name> pgrep -af plasmashell` で確認、`/run/user/<uid>` の存在/権限を確認
- ホストホームにアクセスできない: ホスト側の権限/ACL を緩和するか別ディレクトリをマウント
- PackageKit/udisks2 の DBus ノイズ: 起動スクリプトで autostart/system-service を無効化済み（必要なら再ビルド）
