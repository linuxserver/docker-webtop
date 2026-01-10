# kde-selkies-webtop-devcontainer

**[English Version (README_en.md)](README_en.md)**

ブラウザからアクセス可能なコンテナ化されたKubuntu (KDE Plasma) デスクトップ環境。Selkies WebRTCストリーミングを使用し、VNC/RDPなしでフル機能のLinuxデスクトップを提供します。VS Code Dev Containerにも対応。

### 機能対応表（プラットフォーム）

| 環境 | GPUレンダリング | WebGL/Vulkan | ハードウェアエンコード | 備考 |
|------|----------------|--------------|----------------------|------|
| **Linux + NVIDIA GPU** | ✅ 対応 | ✅ ネイティブ | ✅ NVENC | 最高のパフォーマンス |
| **Linux + Intel GPU** | ✅ 対応 | ✅ ネイティブ | ✅ VA-API (QSV) | 統合GPU可 |
| **Linux + AMD GPU** | ✅ 対応 | ✅ ネイティブ | ✅ VA-API | RDNA/GCN対応 |
| **WSL2 + NVIDIA GPU** | ❌ ソフトウェア | ❌ ソフトウェアのみ | ✅ NVENC | WSL2で動作確認済み |
| **macOS (Docker)** | ❌ 非対応 | ❌ ソフトウェアのみ | ❌ 非対応 | VM制限 |

---

## クイックスタート

```bash
# 1. ベースイメージをビルド（初回のみ、30-60分）
./files/build-base-image.sh                         # Ubuntu 24.04 (デフォルト)
./files/build-base-image.sh -u 22.04                # Ubuntu 22.04

# 2. ユーザーイメージをビルド（1-2分）
USER_PASSWORD=yourpassword ./build-user-image.sh              # 英語環境
USER_PASSWORD=yourpassword ./build-user-image.sh -l ja        # 日本語環境
USER_PASSWORD=yourpassword ./build-user-image.sh -u 22.04     # Ubuntu 22.04

# 3. コンテナを起動
./start-container.sh                                          # ソフトウェアレンダリング
./start-container.sh --gpu nvidia --all                       # NVIDIA GPU（全GPU使用）
./start-container.sh --gpu nvidia --num 0                     # NVIDIA GPU（GPU 0のみ）
./start-container.sh --gpu intel                              # Intel GPU
./start-container.sh --gpu amd                                # AMD GPU
./start-container.sh --gpu nvidia-wsl --all                   # WSL2 + NVIDIA

# 4. ブラウザでアクセス
# → https://localhost:<10000+UID> (例: UID=1000 → https://localhost:11000)
# → http://localhost:<20000+UID>  (例: UID=1000 → http://localhost:21000)

# 5. 変更を保存（重要！コンテナ削除前に必ず実行）
./commit-container.sh

# 6. 停止
./stop-container.sh                    # 停止（コンテナ保持、再起動可能）
./stop-container.sh --rm               # 停止して削除（commitした後のみ推奨）
```

以上で完了です！ 🎉

### VS Code Dev Container を使用する場合

```bash
# 1. Dev Container設定を生成
./create-devcontainer-config.sh

# 2. VS Codeで開く
# VS Codeで「F1」→「Dev Containers: Reopen in Container」を選択

# 3. コンテナ内でワークスペースが自動的に開きます
# ブラウザから https://localhost:<表示されたポート> でデスクトップにアクセス
```

---

## 🚀 このプロジェクトの特徴

### アーキテクチャの改善

- **🏗️ 2段階ビルドシステム**: ベースイメージ（5-10 GB）とユーザーイメージ（~100 MB、1-2分でビルド）を分離
  - ベースイメージはシステムパッケージとデスクトップ環境を含む
  - ユーザーイメージはあなたのUID/GIDに合わせたユーザーを追加
  - 毎回30-60分待つ必要なし！

- **🔒 非rootコンテナ実行**: デフォルトでユーザー権限で実行
  - `fakeroot`ハックや権限エスカレーション回避策を削除
  - システムとユーザー操作の適切な権限分離
  - 必要時はsudoアクセス可能

- **📁 自動UID/GID一致**: ファイル権限がシームレスに動作
  - ユーザーイメージが自動的にホストのUID/GIDに一致
  - マウントしたホストディレクトリの所有権が正しく設定
  - 共有フォルダでの「permission denied」エラーなし

### ユーザー体験の向上

- **🔐 セキュアパスワード管理**: 環境変数でパスワード入力
  - コマンドにパスワードを平文で表示しない
  - イメージ内に安全に保存

- **💻 Ubuntu Desktop標準環境**: 完全な`.bashrc`設定
  - Git branch検出付きカラープロンプト
  - ヒストリー最適化（重複無視、追記モード、タイムスタンプ）
  - 便利なエイリアス（ll, la, grep色付けなど）

- **🎮 柔軟なGPU選択**: 明確なコマンド引数
  - `--all` - 全利用可能GPU使用
  - `--num 0,1` - 特定GPUデバイス
  - `--gpu none` - ソフトウェアレンダリング

### 開発者体験

- **📦 バージョン固定**: 再現可能なビルドを保証
  - VirtualGL 3.1.4、Selkies 1.6.2
  - 「昨日は動いた」問題なし

- **🛠️ 完全な管理スクリプト**: 全操作用シェルスクリプト
  - `build-user-image.sh` - パスワード付きビルド
  - `start-container.sh [--gpu <type>]` - GPU選択で起動
  - `stop/shell-container.sh` - ライフサイクル管理
  - `commit-container.sh` - 変更を保存

- **🌐 多言語サポート**: 日本語環境対応
  - ビルド時に`-l ja`で日本語入力（Mozc）
  - タイムゾーン（Asia/Tokyo）とロケール（ja_JP.UTF-8）自動設定
  - fcitx入力メソッドフレームワーク含む
  - 英語がデフォルト

### なぜこのフォーク？

| 元プロジェクト | このフォーク |
|---------------|-------------|
| Pull可能イメージ | ローカルビルド（1-2分） |
| rootコンテナ | ユーザー権限コンテナ |
| 手動UID/GID設定 | 自動マッチング |
| コマンドにパスワード | 環境変数で安全に |
| 汎用bash | Ubuntu Desktop bash |
| GPU自動検出 | GPU明示的選択 |
| バージョンドリフト | バージョン固定 |
| 英語のみ | 多言語（EN/JP） |

---

## 目次

- [システム要件](#システム要件)
- [2段階ビルドシステム](#2段階ビルドシステム)
- [Intel/AMD GPUホストセットアップ](#intelamd-gpuホストセットアップ)
- [インストール](#インストール)
- [使い方](#使い方)
- [スクリプトリファレンス](#スクリプトリファレンス)
- [設定](#設定)
- [HTTPS/SSL](#httpsssl)
- [トラブルシューティング](#トラブルシューティング)
- [既知の制限](#既知の制限)
- [高度なトピック](#高度なトピック)

---

## システム要件

### 必須
- **Docker** 20.10以降（Docker Desktop 4.0+）
- **8GB以上のRAM**（16GB推奨）
- **20GB以上のディスク空き容量**

### GPU（オプション、ハードウェアアクセラレーション用）
- **NVIDIA GPU** ✅ テスト済み
  - ドライバーバージョン 470以降
  - Maxwell世代以降
  - NVIDIA Container Toolkit インストール済み
- **Intel GPU** ✅ テスト済み
  - Intel統合グラフィックス（HD Graphics, Iris, Arc）
  - Quick Sync Videoサポート
  - VA-APIドライバはコンテナに含む
  - **ホストセットアップ必要**（下記参照）
- **AMD GPU** ⚠️ 部分的にテスト済み
  - VCE/VCNエンコーダー搭載Radeonグラフィックス
  - VA-APIドライバはコンテナに含む
  - **ホストセットアップ必要**（下記参照）

## 2段階ビルドシステム

このプロジェクトは高速セットアップと適切なファイル権限のために2段階ビルドアプローチを使用：

```
┌─────────────────────────┐
│   ベースイメージ (5-10 GB)  │  ← 初回のみビルド（30-60分）
│  • 全システムパッケージ    │
│  • デスクトップ環境       │
│  • プリインストールアプリ  │
└────────────┬────────────┘
             │
             ↓ これを基にビルド
┌────────────┴────────────┐
│ ユーザーイメージ (~100 MB) │  ← あなたがビルド（1-2分）
│  • あなたのユーザー名      │
│  • あなたのUID/GID        │
│  • あなたのパスワード      │
└─────────────────────────┘
```

**メリット:**

- ✅ **高速セットアップ:** 30-60分のビルド待ち不要
- ✅ **適切な権限:** ファイルがホストのUID/GIDに一致
- ✅ **簡単な更新:** 新しいベースイメージをビルド、ユーザーイメージを再ビルド

**なぜUID/GID一致が重要？**

- ホストディレクトリ（`$HOME`など）をマウントする際、ファイルに一致する所有権が必要
- UID/GID不一致だと権限エラーが発生
- ユーザーイメージが自動的にホストの認証情報に一致

---

## Intel/AMD GPUホストセットアップ

Intel/AMD GPUでハードウェアエンコード（VA-API）を使用する場合、ホスト側のセットアップが必要：

### 1. ユーザーをvideo/renderグループに追加

コンテナがGPUデバイス（`/dev/dri/*`）にアクセスするには、ホストユーザーが`video`と`render`グループのメンバーである必要があります：

```bash
# video/renderグループに追加
sudo usermod -aG video,render $USER

# ログアウト＆再ログインまたは再起動してグループ変更を適用
# 確認:
groups
# 出力に "video" と "render" が含まれていることを確認
```

### 2. VA-APIドライバーのインストール（Intel）

IntelGPUハードウェアエンコード用：

```bash
# VA-APIツールとIntelドライバーをインストール
sudo apt update
sudo apt install vainfo intel-media-va-driver-non-free

# インストール確認（H.264エンコードサポートを確認）:
vainfo
# 出力に "VAProfileH264Main : VAEntrypointEncSlice" などが含まれていることを確認
```

### 3. VA-APIドライバーのインストール（AMD）

AMD GPUハードウェアエンコード用：

```bash
# VA-APIツールとAMDドライバーをインストール
sudo apt update
sudo apt install vainfo mesa-va-drivers

# インストール確認:
vainfo
# 出力に "VAProfileH264Main : VAEntrypointEncSlice" などが含まれていることを確認
```

**注意:**
- NVIDIA GPUはこのセットアップ不要
- ホストでVA-APIが正しく動作すれば、コンテナでも自動的に動作
- グループ変更後は必ずログアウト/再ログインまたは再起動

---

## インストール

### 1. ベースイメージのビルド

ベースイメージは初回のみビルドが必要（30-60分）：

```bash
# デフォルトのリポジトリ: ghcr.io/tatsuyai713/webtop-kde
# ホストアーキテクチャに合わせて自動検出
./files/build-base-image.sh                         # Ubuntu 24.04 (デフォルト)
./files/build-base-image.sh -u 22.04                # Ubuntu 22.04

# または明示的に指定
./files/build-base-image.sh -a amd64                # Intel/AMD 64-bit
./files/build-base-image.sh -a arm64                # Apple Silicon / ARM
./files/build-base-image.sh -a amd64 -u 22.04       # AMD64 + Ubuntu 22.04

# キャッシュなしでビルド（問題がある場合）
./files/build-base-image.sh --no-cache

# GHCRに保存する場合（デフォルトのリポジトリ名を使用）
./files/push-base-image.sh

# リポジトリ名を変える場合
IMAGE_NAME=ghcr.io/tatsuyai713/your-base ./files/build-base-image.sh
IMAGE_NAME=ghcr.io/tatsuyai713/your-base ./files/push-base-image.sh
```

### 2. ユーザーイメージのビルド

UID/GIDが一致するパーソナルイメージを作成（1-2分）：

```bash
# 英語（デフォルト）
USER_PASSWORD=yourpassword ./build-user-image.sh

# 日本語
USER_PASSWORD=yourpassword ./build-user-image.sh -l ja
```

**オプション: カスタマイズ**

```bash
# Ubuntu 22.04を使用
USER_PASSWORD=yourpassword ./build-user-image.sh -u 22.04

# 別バージョン
USER_PASSWORD=yourpassword ./build-user-image.sh -v 2.0.0

# 別のベースイメージを使用
USER_PASSWORD=yourpassword ./build-user-image.sh -b my-custom-base:1.0.0
```

---

## 使い方

### コンテナの起動

`start-container.sh`スクリプトはGPUとオプションの引数を使用：

```bash
# 構文: ./start-container.sh [--gpu <type>] [options]
# デフォルト: オプション未指定時はソフトウェアレンダリング

# NVIDIA GPUオプション:
./start-container.sh --gpu nvidia --all              # 全利用可能NVIDIA GPUを使用
./start-container.sh --gpu nvidia --num 0            # NVIDIA GPU 0のみ使用
./start-container.sh --gpu nvidia --num 0,1          # NVIDIA GPU 0と1を使用

# Intel/AMD GPUオプション:
./start-container.sh --gpu intel                     # Intel統合GPU使用（Quick Sync Video）
./start-container.sh --gpu amd                       # AMD GPU使用（VCE/VCN）

# WSL2 NVIDIA:
./start-container.sh --gpu nvidia-wsl --all          # WSL2でのNVIDIA GPU

# ソフトウェアレンダリング:
./start-container.sh                                 # GPUなし（デフォルト）
./start-container.sh --gpu none                      # GPUなしを明示的に指定

# 解像度とDPI:
./start-container.sh --gpu nvidia --all -r 3840x2160 -d 192    # 4K HiDPI
./start-container.sh -r 2560x1440 -d 144                       # WQHD
```

**UIDベースのポート割り当て（マルチユーザー対応）:**

ポートは自動的にユーザーIDに基づいて割り当てられ、同一ホストで複数ユーザーが使用可能：

- **HTTPSポート**: `10000 + UID`（例: UID 1000 → ポート 11000）
- **HTTPポート**: `20000 + UID`（例: UID 1000 → ポート 21000）
- **TURNポート**: `3000 + UID`（例: UID 1000 → ポート 4000）

アクセス: `https://localhost:${HTTPS_PORT}`（例: UID 1000で `https://localhost:11000`）

**リモートアクセス（LAN/WAN）:**

TURNサーバーは**デフォルトで有効**で、追加オプションなしでリモートアクセス可能：

- TURNサーバーがWebRTC接続を中継
- LAN IPアドレスを自動検出
- リモートPCからアクセス: `https://<host-ip>:<https-port>`

**コンテナの特徴:**

- **コンテナ永続化:** 停止しても削除されない（再起動またはcommit可能）
- **ホスト名:** `Docker-$(hostname)`に設定
- **ホストホームマウント:** `~/host_home`で利用可能
- **コンテナ名:** `linuxserver-kde-{username}`

### 変更の保存（重要！）

ソフトウェアをインストールしたり設定を変更した場合：

```bash
# コンテナ状態をイメージに保存
./commit-container.sh
```

**重要な注意:**

- ⚠️ **`./stop-container.sh --rm`の前に必ずcommit** - commitしないと変更が失われます
- ✅ イメージ名形式は `webtop-kde-{username}-{arch}:{version}`
- ✅ commitしたイメージはコンテナ削除後も残る
- ✅ 次回起動時は自動的にcommitしたイメージを使用

**ワークフロー例:**

```bash
# 1. コンテナ内で作業、ソフトウェアインストール、設定変更
./shell-container.sh
# ... パッケージインストール、環境設定 ...
exit

# 2. 変更をイメージに保存
./commit-container.sh

# 3. コンテナを安全に停止・削除（変更はイメージに保存済み）
./stop-container.sh --rm

# 4. 次回起動時、commitしたイメージで全変更が反映
./start-container.sh --gpu intel
```

### コンテナの停止

```bash
# 停止（再起動またはcommit用に保持）
./stop-container.sh

# 停止して削除
./stop-container.sh --rm
# または
./stop-container.sh -r
```

---

## スクリプトリファレンス

### コアスクリプト

| スクリプト | 説明 | 使い方 |
|--------|-------------|-------|
| `files/build-base-image.sh` | ベースイメージをビルド | `./files/build-base-image.sh [-a arch]` |
| `build-user-image.sh` | ユーザー固有イメージをビルド | `USER_PASSWORD=xxx ./build-user-image.sh [-l ja]` |
| `start-container.sh` | デスクトップコンテナを起動 | `./start-container.sh [--gpu <type>]` |
| `stop-container.sh` | コンテナを停止 | `./stop-container.sh [--rm]` |

### 管理スクリプト

| スクリプト | 説明 | 使い方 |
|--------|-------------|-------|
| `shell-container.sh` | コンテナシェルにアクセス | `./shell-container.sh` |
| `commit-container.sh` | コンテナ変更をイメージに保存 | `./commit-container.sh` |
| `files/push-base-image.sh` | ベースイメージをGHCRへPush | `./files/push-base-image.sh` |

### GPUオプション詳細

```bash
./start-container.sh [オプション]

GPU選択:
  -g, --gpu <vendor>    GPUベンダー: none|nvidia|nvidia-wsl|intel|amd
  --all                 全GPU使用（nvidia/nvidia-wsl用）
  --num <list>          カンマ区切りGPUリスト（nvidia用、WSL非対応）

GPU使用例:
  --gpu nvidia --all          # NVIDIA GPU - 全利用可能
  --gpu nvidia --num 0,1      # NVIDIA GPU - 特定GPU
  --gpu nvidia-wsl --all      # WSL2上のNVIDIA
  --gpu intel                 # Intel統合/ディスクリートGPU（VA-API）
  --gpu amd                   # AMD GPU（VA-API + 利用可能ならROCm）
  --gpu none                  # ソフトウェアレンダリングのみ

その他オプション:
  -n <name>             コンテナ名
  -r <WxH>              解像度（例: 1920x1080）
  -d <dpi>              DPI（例: 96, 144, 192）
  -s <ssl_dir>          SSL証明書ディレクトリ
```

---

## 設定

### 表示設定

```bash
# 解像度とDPI
./start-container.sh -r 1920x1080 -d 96              # 標準
./start-container.sh -r 2560x1440 -d 144             # WQHD HiDPI
./start-container.sh -r 3840x2160 -d 192             # 4K HiDPI
```

### ビデオエンコード

**利用可能エンコーダー:**

| エンコーダー | GPU | 品質 | CPU負荷 |
|-------------|-----|------|---------|
| `nvh264enc` | NVIDIA NVENC | 高 | 低 |
| `vah264enc` | Intel/AMD VA-API | 高 | 低 |
| `x264enc` | ソフトウェア | 中 | 高 |

エンコーダーは`--gpu`オプションに基づいて自動選択されます。

### オーディオ設定

**オーディオサポート:**

| 機能 | サポート | 技術 |
|------|---------|------|
| スピーカー出力 | ✅ 内蔵 | WebRTC（ブラウザネイティブ） |
| マイク入力 | ✅ 内蔵 | WebRTC（ブラウザネイティブ） |

Selkiesは双方向オーディオをブラウザにWebRTC経由でストリーミングします。

---

## HTTPS/SSL

### SSL証明書の設定

```bash
# 1. ssl/ディレクトリを作成
mkdir -p ssl

# 2. 証明書を配置
cp /path/to/your/cert.pem ssl/
cp /path/to/your/key.pem ssl/cert.key

# 3. コンテナ起動（ssl/フォルダを自動検出）
./start-container.sh --gpu nvidia --all
```

### 自己署名証明書の生成

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/cert.key -out ssl/cert.pem \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Dev/CN=localhost"
```

### 証明書の優先順位

`start-container.sh`スクリプトは以下の順序で証明書を自動検出：

1. `ssl/cert.pem`と`ssl/cert.key`
2. 環境変数`SSL_DIR`
3. 証明書が見つからない場合はイメージのデフォルト証明書を使用

---

## トラブルシューティング

### コンテナが起動しない

```bash
# ログを確認
docker logs linuxserver-kde-$(whoami)

# イメージが存在するか確認
docker images | grep webtop-kde

# ユーザーイメージを再ビルド
USER_PASSWORD=yourpassword ./build-user-image.sh

# ポートが使用中か確認
sudo netstat -tulpn | grep -E "11000|21000"
```

### GPUが検出されない

```bash
# NVIDIA
./shell-container.sh
nvidia-smi

# Intel/AMD
./shell-container.sh
ls -la /dev/dri/
vainfo

# Docker GPUアクセス確認
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### 権限の問題

```bash
# UID一致確認
id  # ホスト上
./shell-container.sh
id  # コンテナ内

# UID/GID不一致の場合、ユーザーイメージを再ビルド
USER_PASSWORD=yourpassword ./build-user-image.sh
```

### 黒画面 / デスクトップが表示されない

```bash
# ログ確認
docker logs linuxserver-kde-$(whoami)

# plasmashellの状態確認
docker exec linuxserver-kde-$(whoami) pgrep -af plasmashell

# ランタイムディレクトリ確認
docker exec linuxserver-kde-$(whoami) ls -la /run/user/$(id -u)
```

**原因と対処:**
- `/run/user/<uid>`が存在しない/権限が不正 → コンテナ再起動
- plasmashellがクラッシュ → コンテナ再起動

### WebGL/Vulkanが動かない

```bash
# OpenGL情報
docker exec linuxserver-kde-$(whoami) glxinfo | head -30

# Vulkan情報
docker exec linuxserver-kde-$(whoami) vulkaninfo | head -50
```

**macOSの場合:** Docker VMの制限により、GPUアクセラレーションは不可。ソフトウェアレンダリングで動作。

### 音声が出ない

```bash
# PulseAudioサーバー確認
docker exec linuxserver-kde-$(whoami) pactl info

# シンク一覧
docker exec linuxserver-kde-$(whoami) pactl list sinks short
```

**対処:**
- ブラウザのオーディオ権限を確認
- HTTPS接続を使用（一部ブラウザはHTTPでオーディオをブロック）

---

## 既知の制限

### Vulkanの制限

- XvfbはDRI3をサポートしていないため、Vulkanアプリケーションはフレームをプレゼントできず動作しません
- VirtualGLを使用したOpenGLアプリケーションは正常に動作します

### macOSの制限

- Docker Desktop for MacはLinux VM内でコンテナを実行するため、Apple GPU（Metal）へのアクセス不可
- WebGL/Vulkanはソフトウェアレンダリング（llvmpipe）で動作
- ハードウェアアクセラレーションが必要な場合はLinux実機またはWSL2を使用

### WSL2 GPUメモ

- WSL2はNVIDIAのみ対応
- WSL2ではレンダリングはソフトウェア（llvmpipe）になり、WebGL/Vulkanもソフトウェア動作

---

## 高度なトピック

### 環境変数リファレンス

<details>
<summary>クリックで環境変数一覧を展開</summary>

#### コンテナ設定

| 変数 | 説明 | デフォルト |
|------|------|----------|
| `CONTAINER_NAME` | コンテナ名 | `linuxserver-kde-$(whoami)` |
| `IMAGE_BASE` | イメージベース名 | `webtop-kde` |
| `IMAGE_VERSION` | イメージバージョン | `1.0.0` |

#### 表示

| 変数 | 説明 | デフォルト |
|------|------|----------|
| `RESOLUTION` | 解像度 | `1920x1080` |
| `DPI` | DPI設定 | `96` |

#### GPU

| 変数 | 説明 | デフォルト |
|------|------|----------|
| `GPU_VENDOR` | GPUベンダー | `none` |

#### ネットワーク

| 変数 | 説明 | デフォルト |
|------|------|----------|
| `PORT_SSL_OVERRIDE` | HTTPSポート上書き | `UID+10000` |
| `PORT_HTTP_OVERRIDE` | HTTPポート上書き | `UID+20000` |
| `PORT_TURN_OVERRIDE` | TURNポート上書き | `UID+3000` |
| `HOST_IP` | TURNサーバー用ホストIP | 自動検出 |

</details>

### プロジェクト構造

```
devcontainer-ubuntu-kde-selkies-for-mac/
├── build-user-image.sh           # ユーザーイメージビルド
├── start-container.sh            # コンテナ起動
├── stop-container.sh             # コンテナ停止
├── shell-container.sh            # シェルアクセス
├── commit-container.sh           # 変更保存
├── ssl/                          # SSL証明書（自動検出）
│   ├── cert.pem
│   └── cert.key
└── files/                        # システムファイル
    ├── build-base-image.sh       # ベースイメージビルド
    ├── push-base-image.sh        # ベースイメージをPush
    ├── linuxserver-kde.base.dockerfile   # ベースイメージ定義
    ├── linuxserver-kde.user.dockerfile   # ユーザーイメージ定義
    ├── alpine-root/              # s6-overlay設定
    ├── kde-root/                 # KDE設定
    └── ubuntu-root/              # Ubuntu設定
```

### バージョン固定

再現可能なビルドのため、外部依存関係は特定バージョンに固定：

- **VirtualGL:** 3.1.4
- **Selkies GStreamer:** 1.6.2

これらは [files/linuxserver-kde.base.dockerfile](files/linuxserver-kde.base.dockerfile) でビルド引数として定義。

---

## ライセンス

**メインプロジェクト:**

このプロジェクトは複数のオープンソースプロジェクトを基にしています：
- [linuxserver/webtop](https://github.com/linuxserver/docker-webtop) - GPL-3.0
- [selkies-project/selkies](https://github.com/selkies-project/selkies) - MPL-2.0
- [VirtualGL](https://github.com/VirtualGL/virtualgl) - LGPL

詳細は各プロジェクトのライセンスを参照してください。

---

## 貢献

Issue・Pull Requestを歓迎します。

1. リポジトリをフォーク
2. フィーチャーブランチを作成
3. プルリクエストを送信

---

## 関連プロジェクト

- [tatsuyai713/devcontainer-egl-desktop](https://github.com/tatsuyai713/devcontainer-egl-desktop) - EGLベース版（3つの表示モード対応）
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) - 元プロジェクト
- [selkies-project/selkies](https://github.com/selkies-project/selkies) - WebRTCストリーミング

---

## クレジット

### 元プロジェクト

- **Selkies Project:** [github.com/selkies-project](https://github.com/selkies-project)
- **LinuxServer.io:** [github.com/linuxserver](https://github.com/linuxserver)

### このフォーク

- **強化:** 2段階ビルドシステム、非root実行、UID/GID一致、セキュアパスワード管理、管理スクリプト、バージョン固定、マルチGPU対応
- **メンテナー:** [@tatsuyai713](https://github.com/tatsuyai713)

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

### files/build-base-image.sh

ベースイメージをビルドします。

```bash
./files/build-base-image.sh [オプション]

オプション:
  -a, --arch <arch>     アーキテクチャ (amd64|arm64) [デフォルト: ホストに合わせる]
  -p, --platform <plat> Dockerプラットフォーム (例: linux/arm64)
  -v, --version <ver>   イメージバージョン [デフォルト: 1.0.0]
  --no-cache            キャッシュなしでビルド
  -h, --help            ヘルプ表示
```

### files/push-base-image.sh

ベースイメージをGHCRにPushします。

```bash
./files/push-base-image.sh [オプション]

オプション:
  -a, --arch <arch>     アーキテクチャ (amd64|arm64) [デフォルト: ホストに合わせる]
  -p, --platform <plat> Dockerプラットフォーム (例: linux/arm64)
  -v, --version <ver>   イメージバージョン [デフォルト: 1.0.0]
  -u, --ubuntu <ver>    Ubuntuバージョン (22.04|24.04)
  -i, --image <name>    リポジトリ名 [デフォルト: ghcr.io/tatsuyai713/webtop-kde]
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
├── Ubuntu 24.04 (Noble) または 22.04 (Jammy)
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
