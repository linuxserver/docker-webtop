# devcontainer-ubuntu-kde-selkies-for-mac

ブラウザからアクセス可能なコンテナ化されたKubuntu (KDE Plasma) デスクトップ環境。Selkies WebRTCストリーミングを使用し、VNC/RDPなしでフル機能のLinuxデスクトップを提供します。

---

## 目次

- [特徴](#特徴)
- [システム要件](#システム要件)
- [アーキテクチャとGPUサポート](#アーキテクチャとgpuサポート)
- [クイックスタート](#クイックスタート)
- [詳細な使い方](#詳細な使い方)
- [GPUアクセラレーション](#gpuアクセラレーション)
- [スクリプトリファレンス](#スクリプトリファレンス)
- [環境変数](#環境変数)
- [トラブルシューティング](#トラブルシューティング)
- [技術詳細](#技術詳細)

---

## 特徴

### コア機能
- 🖥️ **フルKDEデスクトップ**: Kubuntu 24.04ベースの完全なデスクトップ環境
- 🌐 **ブラウザアクセス**: Selkies WebRTCでVNC/RDPクライアント不要
- 🔐 **セキュア認証**: フォームベース認証（Cookie セッション、Basic認証ではない）
- 🔊 **オーディオサポート**: 双方向音声（スピーカー/マイク）をブラウザにストリーミング
- 📁 **ホストホーム共有**: ホストの`$HOME`を`/home/<user>/host_home`にマウント

### プラットフォーム対応
- 🍎 **macOS対応**: Apple Silicon (arm64) / Intel (amd64) 両対応
- 🐧 **Linux対応**: ネイティブGPUアクセラレーション（NVIDIA/Intel/AMD）
- 🪟 **WSL2対応**: Windows上でNVIDIA GPUによるハードウェアエンコード

### 国際化
- 🇯🇵 **日本語環境**: `-l ja`で日本語ロケール、fcitx+mozc、jp106キーボード、Notoフォント一括導入
- 🌍 **他言語**: `-l en`（英語）をデフォルトとし、ロケール追加可能

---

## システム要件

### 必須
- Docker Engine 20.10+ または Docker Desktop 4.0+
- 8GB以上のRAM（16GB推奨）
- 20GB以上のディスク空き容量

### 推奨
- GPU（NVIDIA/Intel/AMD）- ハードウェアアクセラレーション用
- 最新のChrome/Edge/Firefox（WebRTC対応ブラウザ）

---

## アーキテクチャとGPUサポート

### GPUサポートマトリックス

| 環境 | GPUレンダリング | WebGL/Vulkan | ハードウェアエンコード | 備考 |
|------|----------------|--------------|----------------------|------|
| **Linux + NVIDIA GPU** | ✅ 完全対応 | ✅ ネイティブ | ✅ NVENC | 最高のパフォーマンス |
| **Linux + Intel GPU** | ✅ 完全対応 | ✅ ネイティブ | ✅ VA-API (QSV) | 統合GPU可 |
| **Linux + AMD GPU** | ✅ 完全対応 | ✅ ネイティブ | ✅ VA-API | RDNA/GCN対応 |
| **WSL2 + NVIDIA GPU** | ✅ 対応 | ✅ DirectML経由 | ✅ NVENC | Windows統合 |
| **WSL2 + Intel/AMD** | ⚠️ 限定的 | ❌ ソフトウェアのみ | ❌ 非対応 | VA-API不可 |
| **macOS (Docker)** | ❌ 非対応 | ❌ ソフトウェアのみ | ❌ 非対応 | VMのため |
| **NVIDIA Jetson** | ⚠️ 部分的 | ✅ ネイティブ | ❌ 非対応 | nvv4l2非対応 |

### 重要な注意事項

#### macOS (Apple Silicon / Intel)
Docker Desktop for Macは**Linux VM内**でコンテナを実行するため、Apple GPU（Metal）へのアクセスはできません。WebGL/Vulkanはソフトウェアレンダリング（llvmpipe）で動作します。
- ✅ 動作はする（遅い）
- ❌ GPUアクセラレーション不可
- 💡 ハードウェアアクセラレーションが必要な場合はLinux実機またはWSL2を使用

#### WSL2
WSL2のGPUパススルーは`/dev/dxg`デバイスとDirectX 12経由で動作します。
- **NVIDIA GPU**: フルサポート（CUDA, NVENC, Vulkan）
- **Intel/AMD GPU**: DirectML経由のML処理のみ、VA-APIは不可

---

## クイックスタート

### 1. ベースイメージのビルド

```bash
# Apple Silicon Mac / ARM64 Linux
./build-base-image.sh -a arm64

# Intel Mac / AMD64 Linux / WSL2
./build-base-image.sh -a amd64

# キャッシュなしでビルド（問題がある場合）
./build-base-image.sh -a amd64 --no-cache
```

### 2. ユーザーイメージのビルド

```bash
# 日本語環境
USER_PASSWORD=yourpassword ./build-user-image.sh -a arm64 -l ja

# 英語環境
USER_PASSWORD=yourpassword ./build-user-image.sh -a amd64 -l en
```

### 3. コンテナの起動

```bash
# 基本起動（ソフトウェアレンダリング）
./start-container.sh -r 1920x1080

# NVIDIA GPU使用（Linux）
./start-container.sh -g nvidia --all -r 1920x1080

# Intel GPU使用（Linux）
./start-container.sh -g intel -r 1920x1080

# AMD GPU使用（Linux）
./start-container.sh -g amd -r 1920x1080

# WSL2 + NVIDIA GPU
./start-container.sh -g nvidia-wsl -r 1920x1080
```

### 4. ブラウザでアクセス

ポートはUID（ユーザーID）に基づいて自動計算されます：
- **HTTPS**: `https://localhost:<UID+10000>` （例: UID=1000 → ポート11000）
- **HTTP**: `http://localhost:<UID+20000>` （例: UID=1000 → ポート21000）

ビルド時に設定したユーザー名とパスワードでログインしてください。

### 5. 停止

```bash
# コンテナを停止（状態保持）
./stop-container.sh

# コンテナを停止して削除
./stop-container.sh --rm
```

---

## 詳細な使い方

### 永続化とVM的な使用

#### コンテナ状態の保持
```bash
# 停止（削除せず）
./stop-container.sh

# 後で再開
./start-container.sh
```

#### イメージへのコミット
インストールしたアプリやカスタマイズを永続化：
```bash
./commit-container.sh
# → webtop-kde-<user>-<arch>:<version> として保存
```

#### ホームディレクトリの永続化
ホストの`$HOME`が`/home/<user>/host_home`にマウントされます。
重要なファイルはここに保存することで永続化できます。

### 解像度とDPI設定

```bash
# 4K HiDPI
./start-container.sh -r 3840x2160 -d 192

# 1080p 標準DPI
./start-container.sh -r 1920x1080 -d 96

# カスタム
./start-container.sh -r 2560x1440 -d 144
```

### SSL証明書の使用

自己署名証明書の警告を避けるため、独自の証明書を使用できます：

```bash
# ssl/ディレクトリにcert.pemとcert.keyを配置
mkdir -p ssl
cp /path/to/your/cert.pem ssl/
cp /path/to/your/key.pem ssl/cert.key

# 起動時に自動マウント
./start-container.sh

# または明示的に指定
./start-container.sh -s /path/to/ssl/dir
```

### コンテナ内シェル

```bash
# ユーザーとしてシェルに入る
./shell-container.sh

# rootとしてシェルに入る
docker exec -it -u root <container-name> bash
```

---

## GPUアクセラレーション

### NVIDIA GPU（Linux）

```bash
# 全GPUを使用
./start-container.sh -g nvidia --all

# 特定のGPUを使用（デバイス番号指定）
./start-container.sh -g nvidia --num 0
./start-container.sh -g nvidia --num 0,1
```

**前提条件**:
- NVIDIA Driver 470+
- NVIDIA Container Toolkit（nvidia-docker2）

**確認**:
```bash
# コンテナ内で
nvidia-smi
glxinfo | grep "OpenGL renderer"
vulkaninfo | grep "deviceName"
```

### Intel GPU（Linux）

```bash
./start-container.sh -g intel
```

**前提条件**:
- Intel GPU（6th Gen以降推奨）
- `i915`ドライバ
- `/dev/dri`デバイス

**確認**:
```bash
# コンテナ内で
vainfo
glxinfo | grep "OpenGL renderer"
```

### AMD GPU（Linux）

```bash
./start-container.sh -g amd
```

**前提条件**:
- AMD GPU（GCN/RDNA）
- `amdgpu`ドライバ
- `/dev/dri`および`/dev/kfd`デバイス

**確認**:
```bash
# コンテナ内で
vainfo
radeontop
vulkaninfo | grep "deviceName"
```

### WSL2 + NVIDIA GPU

```bash
./start-container.sh -g nvidia-wsl
```

**前提条件**:
- Windows 10 21H2+ または Windows 11
- WSL2（バージョン2）
- NVIDIA GPU + Windows用ドライバ（CUDA対応版）

**注意**: WSL2では`--gpus all`のみサポート。個別GPU選択（`--num`）は使用不可。

### ソフトウェアレンダリング

GPUがない環境やmacOSでは自動的にソフトウェアレンダリング（llvmpipe）が使用されます：

```bash
./start-container.sh  # -g オプションなし、または -g none
```

---

## スクリプトリファレンス

### build-base-image.sh

ベースイメージをビルドします。

```bash
./build-base-image.sh [オプション]

オプション:
  -a, --arch <arch>     アーキテクチャ (amd64|arm64) [デフォルト: ホストに合わせる]
  -p, --platform <plat> Dockerプラットフォーム (例: linux/arm64)
  -v, --version <ver>   イメージバージョン [デフォルト: 1.0.0]
  --no-cache            キャッシュなしでビルド
  -h, --help            ヘルプ表示
```

### build-user-image.sh

ユーザーイメージをビルドします。

```bash
USER_PASSWORD=<password> ./build-user-image.sh [オプション]

オプション:
  -a, --arch <arch>     アーキテクチャ (amd64|arm64)
  -b, --base <image>    ベースイメージ名 [デフォルト: 自動検出]
  -l, --lang <lang>     言語 (en|ja) [デフォルト: en]
  -v, --version <ver>   イメージバージョン
  -h, --help            ヘルプ表示

環境変数:
  USER_PASSWORD         必須。ログインパスワード
```

### start-container.sh

コンテナを起動します。

```bash
./start-container.sh [オプション]

オプション:
  -n <name>             コンテナ名 [デフォルト: linuxserver-kde-<user>]
  -i <base>             イメージベース名
  -t <version>          イメージバージョン
  -r <WxH>              解像度 (例: 1920x1080) [デフォルト: 1920x1080]
  -d <dpi>              DPI [デフォルト: 96]
  -p <platform>         Dockerプラットフォーム
  -s <ssl_dir>          SSL証明書ディレクトリ
  -g, --gpu <vendor>    GPUベンダー: none|nvidia|nvidia-wsl|intel|amd
  --all                 全NVIDIA GPUを使用 (-g nvidia必須)
  --num <list>          NVIDIA GPUデバイス番号 (-g nvidia必須)
  -h, --help            ヘルプ表示
```

### stop-container.sh

コンテナを停止します。

```bash
./stop-container.sh [オプション]

オプション:
  --rm, -r              停止後にコンテナを削除
```

### shell-container.sh

コンテナ内のシェルにアクセスします。

```bash
./shell-container.sh
```

### commit-container.sh

実行中のコンテナをイメージとして保存します。

```bash
./commit-container.sh
```

---

## 環境変数

### ビルド時

| 変数 | 説明 | デフォルト |
|------|------|----------|
| `USER_PASSWORD` | ログインパスワード（必須） | - |
| `IMAGE_BASE` | イメージベース名 | `webtop-kde` |
| `IMAGE_VERSION` | イメージバージョン | `1.0.0` |

### 実行時

| 変数 | 説明 | デフォルト |
|------|------|----------|
| `RESOLUTION` | 画面解像度 | `1920x1080` |
| `DPI` | 画面DPI | `96` |
| `GPU_VENDOR` | GPUベンダー | `none` |
| `PORT_SSL_OVERRIDE` | HTTPSポート上書き | `UID+10000` |
| `PORT_HTTP_OVERRIDE` | HTTPポート上書き | `UID+20000` |
| `HOST_IP` | TURNサーバー用ホストIP | 自動検出 |

### コンテナ内

| 変数 | 説明 |
|------|------|
| `DISPLAY` | Xディスプレイ (`:1`) |
| `SELKIES_ENCODER` | ビデオエンコーダー (`nvh264enc`/`vah264enc`/`x264enc`) |
| `ENABLE_NVIDIA` | NVIDIA GPUサポート有効化 |
| `VGL_DISPLAY` | VirtualGL表示デバイス |
| `LIBVA_DRIVER_NAME` | VA-APIドライバー名 |

---

## トラブルシューティング

### 黒画面 / デスクトップが表示されない

```bash
# plasmashellの状態確認
docker exec <container-name> pgrep -af plasmashell

# ランタイムディレクトリの確認
docker exec <container-name> ls -la /run/user/$(id -u)

# ログ確認
docker logs <container-name>
```

**原因と対処**:
- `/run/user/<uid>`が存在しない/権限が不正 → コンテナ再起動
- plasmashellがクラッシュ → `docker exec`でkill後に自動再起動を待つ

### GPUが認識されない

```bash
# NVIDIA
docker exec <container-name> nvidia-smi

# Intel/AMD
docker exec <container-name> ls -la /dev/dri/
docker exec <container-name> vainfo

# グループ確認
docker exec <container-name> id
```

**原因と対処**:
- `/dev/dri`がマウントされていない → `-g intel`や`-g nvidia --all`を指定
- グループ権限がない → `video`/`render`グループに所属しているか確認
- ドライバがインストールされていない → ホスト側でドライバをインストール

### WebGL/Vulkanが動かない

```bash
# OpenGL情報
docker exec <container-name> glxinfo | head -30

# Vulkan情報
docker exec <container-name> vulkaninfo | head -50
```

**macOSの場合**: Docker VMの制限により、GPUアクセラレーションは不可。ソフトウェアレンダリングで動作。

### 音声が出ない

```bash
# PulseAudioサーバー確認
docker exec <container-name> pactl info

# シンク一覧
docker exec <container-name> pactl list sinks short
```

**対処**:
- ブラウザのオーディオ権限を確認
- HTTPS接続を使用（一部ブラウザはHTTPでオーディオをブロック）

### ホストホームにアクセスできない

ホスト側の`$HOME`パーミッションが`750`などの場合、コンテナ内からアクセスできないことがあります。

**対処**:
```bash
# ホスト側でACLを追加
setfacl -m u:$(id -u):rx $HOME

# または別ディレクトリをマウント
docker run ... -v /path/to/share:/home/<user>/shared ...
```

### 接続が切れる / WebRTCが不安定

```bash
# TURNサーバー状態確認
docker exec <container-name> pgrep -af turnserver
```

**対処**:
- ファイアウォールでTURNポート（デフォルト: UID+3000）を開放
- HTTPS接続を使用

---

## 技術詳細

### イメージ構成

```
webtop-kde-base-<arch>:<version>
├── Ubuntu 24.04 (Noble)
├── s6-overlay (init system)
├── KDE Plasma Desktop
├── Selkies (WebRTC streaming)
├── Selkies-GStreamer (AMD64のみ、ハードウェアエンコード)
├── VirtualGL (3Dアクセラレーション)
├── PulseAudio (オーディオ)
├── nginx (Webサーバー)
├── coturn (TURNサーバー、AMD64のみ)
└── 各種GPUドライバ/ライブラリ

webtop-kde-<user>-<arch>:<version>
├── webtop-kde-base を継承
├── ユーザー作成 (ホストUID/GID)
├── グループ設定 (video, render, sudo等)
├── 言語設定 (ja: fcitx+mozc, フォント)
└── 認証設定 (web-auth.json)
```

### ネットワークポート

| ポート | 用途 | 計算式 |
|--------|------|--------|
| 3000 | HTTP（コンテナ内） | - |
| 3001 | HTTPS（コンテナ内） | - |
| UID+10000 | HTTPS（ホスト） | 例: 11000 |
| UID+20000 | HTTP（ホスト） | 例: 21000 |
| UID+3000 | TURN | 例: 4000 |

### ビデオエンコーダー

| エンコーダー | GPU | 品質 | CPU負荷 |
|-------------|-----|------|---------|
| `nvh264enc` | NVIDIA NVENC | 高 | 低 |
| `vah264enc` | Intel/AMD VA-API | 高 | 低 |
| `x264enc` | ソフトウェア | 中 | 高 |

### ファイルシステム構成

```
/config             # ユーザー設定永続化用
/home/<user>        # ユーザーホーム
  └── host_home/    # ホスト$HOMEのマウントポイント
/run/user/<uid>     # XDGランタイム (DBus, Qt用)
/opt/gstreamer      # GStreamer (AMD64)
/usr/share/selkies  # Selkies Webフロントエンド
```

---

## ライセンス

このプロジェクトは複数のオープンソースプロジェクトを基にしています：
- [linuxserver/webtop](https://github.com/linuxserver/docker-webtop) - GPL-3.0
- [selkies-project/selkies](https://github.com/selkies-project/selkies) - MPL-2.0
- [VirtualGL](https://github.com/VirtualGL/virtualgl) - LGPL

詳細は各プロジェクトのライセンスを参照してください。

---

## 貢献

Issue・Pull Requestを歓迎します。

---

## 関連プロジェクト

- [devcontainer-egl-desktop](./devcontainer-egl-desktop/) - EGLベースの軽量版（KDE Plasma）
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) - 元プロジェクト
- [selkies-project/selkies](https://github.com/selkies-project/selkies) - WebRTCストリーミング
