# syntax=docker/dockerfile:1

###########################################
# Stage 1: Alpine rootfs builder
###########################################
FROM alpine:3.21 AS alpine-rootfs-stage

ARG S6_OVERLAY_VERSION="3.2.1.0"
ARG ROOTFS=/root-out
ARG REL=v3.21
ARG ALPINE_ARCH=x86_64
ARG S6_OVERLAY_ARCH=x86_64
ARG MIRROR=http://dl-cdn.alpinelinux.org/alpine
ARG PACKAGES=alpine-baselayout,alpine-keys,apk-tools,busybox,libc-utils

# install packages
RUN \
  apk add --no-cache bash xz

# build rootfs
RUN \
  mkdir -p "${ROOTFS}/etc/apk" && \
  { \
    echo "${MIRROR}/${REL}/main"; \
    echo "${MIRROR}/${REL}/community"; \
  } > "${ROOTFS}/etc/apk/repositories" && \
  apk --root "${ROOTFS}" --no-cache --keys-dir /etc/apk/keys add --arch ${ALPINE_ARCH} --initdb ${PACKAGES//,/ } && \
  sed -i -e 's/^root::/root:!:/' /root-out/etc/shadow

# add s6 overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz

# add s6 optional symlinks
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz && unlink /root-out/usr/bin/with-contenv
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz


###########################################
# Stage 2: Ubuntu rootfs builder
###########################################
FROM alpine:3 AS ubuntu-rootfs-stage

ARG UBUNTU_ARCH=amd64
ENV REL=noble
ENV ARCH=${UBUNTU_ARCH}
ENV TAG=oci-noble-24.04

# install packages
RUN \
  apk add --no-cache bash curl git jq tzdata xz

# grab base tarball
RUN \
  git clone --depth=1 https://git.launchpad.net/cloud-images/+oci/ubuntu-base -b ${TAG} /build && \
  cd /build/oci && \
  DIGEST=$(jq -r '.manifests[0].digest[7:]' < index.json) && \
  cd /build/oci/blobs/sha256 && \
  if jq -e '.layers // empty' < "${DIGEST}" >/dev/null 2>&1; then \
    TARBALL=$(jq -r '.layers[0].digest[7:]' < ${DIGEST}); \
  else \
    MULTIDIGEST=$(jq -r ".manifests[] | select(.platform.architecture == \"${ARCH}\") | .digest[7:]" < ${DIGEST}) && \
    TARBALL=$(jq -r '.layers[0].digest[7:]' < ${MULTIDIGEST}); \
  fi && \
  mkdir /root-out && \
  tar xf ${TARBALL} -C /root-out && \
  rm -rf \
    /root-out/var/log/* \
    /root-out/home/ubuntu \
    /root-out/root/{.ssh,.bashrc,.profile} \
    /build

# set version for s6 overlay
ARG S6_OVERLAY_VERSION="3.2.1.0"
ARG S6_OVERLAY_ARCH="x86_64"

# add s6 overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz

# add s6 optional symlinks
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz && unlink /root-out/usr/bin/with-contenv
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz


###########################################
# Stage 3: Ubuntu base temp
###########################################
FROM scratch AS ubuntu-base-temp

COPY --from=ubuntu-rootfs-stage /root-out/ /

ARG VERSION
ARG MODS_VERSION="v3"
ARG PKG_INST_VERSION="v1"
ARG LSIOWN_VERSION="v1"
ARG WITHCONTENV_VERSION="v1"

ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/docker-mods.${MODS_VERSION}" "/docker-mods"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/package-install.${PKG_INST_VERSION}" "/etc/s6-overlay/s6-rc.d/init-mods-package-install/run"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/lsiown.${LSIOWN_VERSION}" "/usr/bin/lsiown"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/with-contenv.${WITHCONTENV_VERSION}" "/usr/bin/with-contenv"

ARG DEBIAN_FRONTEND="noninteractive"
ENV HOME="/root" \
    LANGUAGE="en_US.UTF-8" \
    LANG="en_US.UTF-8" \
    TERM="xterm" \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
    S6_VERBOSITY=1 \
    S6_STAGE2_HOOK=/docker-mods \
    VIRTUAL_ENV=/lsiopy \
    PATH="/lsiopy/bin:$PATH"

# copy sources
ARG SOURCES_LIST="sources.list"
COPY ${SOURCES_LIST} /etc/apt/sources.list

RUN \
  echo "**** Ripped from Ubuntu Docker Logic ****" && \
  rm -f /etc/apt/sources.list.d/ubuntu.sources && \
  set -xe && \
  echo '#!/bin/sh' > /usr/sbin/policy-rc.d && \
  echo 'exit 101' >> /usr/sbin/policy-rc.d && \
  chmod +x /usr/sbin/policy-rc.d && \
  dpkg-divert --local --rename --add /sbin/initctl && \
  cp -a /usr/sbin/policy-rc.d /sbin/initctl && \
  sed -i 's/^exit.*/exit 0/' /sbin/initctl && \
  echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/docker-apt-speedup && \
  echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' > /etc/apt/apt.conf.d/docker-clean && \
  echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' >> /etc/apt/apt.conf.d/docker-clean && \
  echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' >> /etc/apt/apt.conf.d/docker-clean && \
  echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/docker-no-languages && \
  echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/docker-gzip-indexes && \
  echo 'Apt::AutoRemove::SuggestsImportant "false";' > /etc/apt/apt.conf.d/docker-autoremove-suggests && \
  mkdir -p /run/systemd && \
  echo 'docker' > /run/systemd/container && \
  echo "**** install apt-utils and locales ****" && \
  apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y apt-utils locales && \
  echo "**** install packages ****" && \
  apt-get install -y \
    catatonit cron curl gnupg jq netcat-openbsd systemd-standalone-sysusers tzdata && \
  echo "**** generate locale ****" && \
  locale-gen en_US.UTF-8 && \
  echo "**** prepare shared folders ****" && \
  mkdir -p /app /config /defaults /lsiopy && \
  echo "**** cleanup ****" && \
  userdel ubuntu && \
  apt-get autoremove && \
  apt-get clean && \
  rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/* /var/log/*

# add local files for ubuntu base
COPY ubuntu-root/ /


###########################################
# Stage 4: Xvfb builder
###########################################
FROM ubuntu-base-temp AS xvfb-builder

COPY /patches /patches
ENV PATCH_VERSION=21 \
    HOME=/config

RUN \
  echo "**** build deps ****" && \
  apt-get update && \
  apt-get install -y devscripts dpkg-dev && \
  apt-get build-dep -y xorg-server

RUN \
  echo "**** get and build xvfb ****" && \
  apt-get source xorg-server && \
  cd xorg-server-* && \
  cp /patches/${PATCH_VERSION}-xvfb-dri3.patch patch.patch && \
  patch -p0 < patch.patch && \
  awk ' \
    { print } \
    /include \/usr\/share\/dpkg\/architecture.mk/ { \
      print ""; \
      print "GLAMOR_DEP_LIBS := $(shell pkg-config --libs gbm epoxy libdrm)"; \
      print "GLAMOR_DEP_CFLAGS := $(shell pkg-config --cflags gbm epoxy libdrm)"; \
      print "export DEB_LDFLAGS_PREPEND ?= $(GLAMOR_DEP_LIBS)"; \
      print "export DEB_CFLAGS_PREPEND ?= $(GLAMOR_DEP_CFLAGS)"; \
    } \
  ' debian/rules > debian/rules.tmp && mv debian/rules.tmp debian/rules && \
  debuild -us -uc -b && \
  mkdir -p /build-out/usr/bin && \
  mv debian/xvfb/usr/bin/Xvfb /build-out/usr/bin/


###########################################
# Stage 5: Alpine base temp
###########################################
FROM alpine-rootfs-stage AS alpine-base-temp

COPY --from=alpine-rootfs-stage /root-out/ /

ARG BUILD_DATE
ARG VERSION
ARG MODS_VERSION="v3"
ARG PKG_INST_VERSION="v1"
ARG LSIOWN_VERSION="v1"
ARG WITHCONTENV_VERSION="v1"

ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/docker-mods.${MODS_VERSION}" "/docker-mods"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/package-install.${PKG_INST_VERSION}" "/etc/s6-overlay/s6-rc.d/init-mods-package-install/run"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/lsiown.${LSIOWN_VERSION}" "/usr/bin/lsiown"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/with-contenv.${WITHCONTENV_VERSION}" "/usr/bin/with-contenv"

ENV PS1="$(whoami)@$(hostname):$(pwd)\\$ " \
  HOME="/root" \
  TERM="xterm" \
  S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
  S6_VERBOSITY=1 \
  S6_STAGE2_HOOK=/docker-mods \
  VIRTUAL_ENV=/lsiopy \
  PATH="/lsiopy/bin:$PATH"

RUN \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    alpine-release bash ca-certificates catatonit coreutils curl findutils jq \
    netcat-openbsd procps-ng shadow tzdata && \
  echo "**** prepare shared folders ****" && \
  mkdir -p /app /config /defaults /lsiopy && \
  echo "**** cleanup ****" && \
  rm -rf /tmp/*

# add local files for alpine base
COPY alpine-root/ /


###########################################
# Stage 6: Selkies frontend builder
###########################################
FROM alpine-base-temp AS frontend

RUN \
  echo "**** install build packages ****" && \
  apk add cmake git nodejs npm

RUN \
  echo "**** ingest code ****" && \
  git clone https://github.com/selkies-project/selkies.git /src && \
  cd /src && \
  git checkout -f f1ade4dd700bf0157bb78a8a58eab42fbb8f02ee

RUN \
  echo "**** build shared core library ****" && \
  cd /src/addons/gst-web-core && \
  npm install && \
  npm run build && \
  echo "**** build multiple dashboards ****" && \
  DASHBOARDS="selkies-dashboard selkies-dashboard-zinc selkies-dashboard-wish" && \
  mkdir /buildout && \
  for DASH in $DASHBOARDS; do \
    cd /src/addons/$DASH && \
    cp ../gst-web-core/dist/selkies-core.js src/ && \
    npm install && \
    npm run build && \
    mkdir -p dist/src dist/nginx && \
    cp ../gst-web-core/dist/selkies-core.js dist/src/ && \
    cp ../universal-touch-gamepad/universalTouchGamepad.js dist/src/ && \
    cp ../gst-web-core/nginx/* dist/nginx/ && \
    cp -r ../gst-web-core/dist/jsdb dist/ && \
    mkdir -p /buildout/$DASH && \
    cp -ar dist/* /buildout/$DASH/; \
  done


###########################################
# Stage 7: Selkies base image
###########################################
FROM ubuntu-base-temp AS selkies-base

# set version label
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION}"
LABEL maintainer="thelamer"

# env
ENV DISPLAY=:1 \
    PERL5LIB=/usr/local/bin \
    HOME=/config \
    START_DOCKER=true \
    PULSE_RUNTIME_PATH=/defaults \
    SELKIES_INTERPOSER=/usr/lib/selkies_joystick_interposer.so \
    NVIDIA_DRIVER_CAPABILITIES=all \
    DISABLE_ZINK=false \
    DISABLE_DRI3=false \
    DPI=96 \
    TITLE=Selkies

ARG APT_EXTRA_PACKAGES=""
ARG LIBVA_DEB_URL="https://launchpad.net/ubuntu/+source/libva/2.22.0-3ubuntu2/+build/30591127/+files/libva2_2.22.0-3ubuntu2_amd64.deb"
ARG LIBVA_LIBDIR="/usr/lib/x86_64-linux-gnu"
ARG PROOT_ARCH="x86_64"

RUN \
  echo "**** dev deps ****" && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y python3-dev && \
  echo "**** enable locales ****" && \
  sed -i '/locale/d' /etc/dpkg/dpkg.cfg.d/excludes && \
  echo "**** install docker ****" && \
  unset VERSION && \
  curl https://get.docker.com | sh && \
  echo "**** install deps ****" && \
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    breeze-cursor-theme ca-certificates cmake console-data dbus-x11 \
    dunst file \
    fonts-noto-cjk fonts-noto-color-emoji fonts-noto-core foot fuse-overlayfs \
    g++ gcc git ${APT_EXTRA_PACKAGES} kbd labwc libatk1.0-0 libatk-bridge2.0-0 \
    libev4 libfontenc1 libfreetype6 libgbm1 libgcrypt20 libgirepository-1.0-1 \
    libgl1-mesa-dri libglu1-mesa libgnutls30 libgtk-3.0 libjpeg-turbo8 \
    libnginx-mod-http-fancyindex libnotify-bin libnss3 libnvidia-egl-wayland1 \
    libopus0 libp11-kit0 libpam0g libtasn1-6 libvulkan1 libwayland-client0 \
    libwayland-cursor0 libwayland-egl1 libwayland-server0 libx11-6 \
    libxau6 libxcb1 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 \
    libxcursor1 libxdmcp6 libxext6 libxfconf-0-3 libxfixes3 libxfont2 libxinerama1 \
    libxkbcommon-dev libxkbcommon-x11-0 libxshmfence1 libxtst6 locales-all make \
    mesa-libgallium mesa-va-drivers mesa-vulkan-drivers nginx openbox openssh-client \
    openssl pciutils procps psmisc pulseaudio pulseaudio-utils python3 python3-venv \
    bash-completion software-properties-common ssl-cert stterm sudo tar util-linux vulkan-tools \
    wl-clipboard wtype x11-apps x11-common x11-utils x11-xkb-utils x11-xserver-utils \
    xauth xclip xcvt xdg-utils xdotool xfconf xfonts-base xkb-data xsel \
    xserver-common xserver-xorg-core xserver-xorg-video-amdgpu xserver-xorg-video-ati \
    xserver-xorg-video-nouveau xserver-xorg-video-qxl \
    xsettingsd xterm xutils xvfb zlib1g zstd && \
  echo "**** install selkies ****" && \
  SELKIES_RELEASE=$(curl -sX GET "https://api.github.com/repos/selkies-project/selkies/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]') && \
  curl -o /tmp/selkies.tar.gz -L \
    "https://github.com/selkies-project/selkies/archive/f1ade4dd700bf0157bb78a8a58eab42fbb8f02ee.tar.gz" && \
  cd /tmp && \
  tar xf selkies.tar.gz && \
  cd selkies-* && \
  sed -i '/cryptography/d' pyproject.toml && \
  python3 -m venv --system-site-packages /lsiopy && \
  pip install . && \
  pip install setuptools && \
  echo "**** install selkies interposer ****" && \
  cd addons/js-interposer && \
  gcc -shared -fPIC -ldl -o selkies_joystick_interposer.so joystick_interposer.c && \
  mv selkies_joystick_interposer.so /usr/lib/selkies_joystick_interposer.so && \
  echo "**** install selkies fake udev ****" && \
  cd ../fake-udev && \
  make && \
  mkdir /opt/lib && \
  mv libudev.so.1.0.0-fake /opt/lib/ && \
  echo "**** add icon ****" && \
  mkdir -p /usr/share/selkies/www && \
  curl -o /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/selkies-logo.png && \
  curl -o /usr/share/selkies/www/favicon.ico \
    https://raw.githubusercontent.com/linuxserver/docker-templates/refs/heads/master/linuxserver.io/img/selkies-icon.ico && \
  echo "**** openbox tweaks ****" && \
  sed -i \
    -e 's/NLIMC/NLMC/g' \
    -e '/debian-menu/d' \
    -e 's|</applications>|  <application class="*"><maximized>yes</maximized></application>\n</applications>|' \
    -e 's|</keyboard>|  <keybind key="C-S-d"><action name="ToggleDecorations"/></keybind>\n</keyboard>|' \
    -e 's|<number>4</number>|<number>1</number>|' \
    /etc/xdg/openbox/rc.xml && \
  sed -i 's/--startup/--replace --startup/g' /usr/bin/openbox-session && \
  echo "**** user perms ****" && \
  sed -e 's/%sudo	ALL=(ALL:ALL) ALL/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/g' -i /etc/sudoers && \
  echo "**** proot-apps ****" && \
  mkdir /proot-apps/ && \
  PAPPS_RELEASE=$(curl -sX GET "https://api.github.com/repos/linuxserver/proot-apps/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]') && \
  curl -L https://github.com/linuxserver/proot-apps/releases/download/${PAPPS_RELEASE}/proot-apps-${PROOT_ARCH}.tar.gz \
    | tar -xzf - -C /proot-apps/ && \
  echo "${PAPPS_RELEASE}" > /proot-apps/pversion && \
  echo "**** dind support ****" && \
  useradd -U dockremap && \
  usermod -G dockremap dockremap && \
  echo 'dockremap:165536:65536' >> /etc/subuid && \
  echo 'dockremap:165536:65536' >> /etc/subgid && \
  curl -o /usr/local/bin/dind -L \
    https://raw.githubusercontent.com/moby/moby/master/hack/dind && \
  chmod +x /usr/local/bin/dind && \
  echo 'hosts: files dns' > /etc/nsswitch.conf && \
  groupadd -f docker && \
  echo "**** libva hack ****" && \
  mkdir /tmp/libva && \
  curl -o /tmp/libva/libva.deb -L "${LIBVA_DEB_URL}" && \
  cd /tmp/libva && \
  ar x libva.deb && \
  tar xf data.tar.zst && \
  rm -f ${LIBVA_LIBDIR}/libva.so.2* && \
  cp -a usr/lib/${LIBVA_LIBDIR#/usr/lib/}/libva.so.2* ${LIBVA_LIBDIR}/ && \
  echo "**** locales ****" && \
  for LOCALE in $(curl -sL https://raw.githubusercontent.com/thelamer/lang-stash/master/langs); do \
    localedef -i $LOCALE -f UTF-8 $LOCALE.UTF-8; \
  done && \
  echo "**** theme ****" && \
  curl -s https://raw.githubusercontent.com/thelamer/lang-stash/master/theme.tar.gz \
    | tar xzvf - -C /usr/share/themes/Clearlooks/openbox-3/ && \
  echo "**** cleanup ****" && \
  apt-get purge -y --autoremove python3-dev && \
  apt-get autoclean && \
  rm -rf /config/.cache /config/.npm /var/lib/apt/lists/* /var/tmp/* /tmp/*

# add local files - this will overwrite ubuntu-root files if conflicts exist
COPY ubuntu-root/ /
COPY --from=frontend /buildout /usr/share/selkies
COPY --from=xvfb-builder /build-out/ /

# ports and volumes
EXPOSE 3000 3001
VOLUME /config


###########################################
# Stage 8: Final webtop image
###########################################
FROM selkies-base

# set version label
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION}"
LABEL maintainer="thelamer"
ARG DEBIAN_FRONTEND="noninteractive"

# title
ENV TITLE="Ubuntu KDE" \
    NO_GAMEPAD=true

RUN \
  echo "**** add icon ****" && \
  curl -o /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/webtop-logo.png && \
  echo "**** install packages ****" && \
  add-apt-repository ppa:xtradeb/apps && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    bc chromium dolphin gwenview kde-config-gtk-style kdialog kfind khotkeys \
    kio-extras knewstuff-dialog konsole ksystemstats kubuntu-settings-desktop \
    kubuntu-wallpapers kubuntu-web-shortcuts kwin-addons kwin-x11 kwrite \
    plasma-desktop plasma-workspace qml-module-qt-labs-platform systemsettings kubuntu-desktop && \
  if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    echo "**** install latest google-chrome (amd64) ****" && \
    cd /tmp && \
    curl -fsSL -o google-chrome-stable.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y ./google-chrome-stable.deb && \
    rm -f /tmp/google-chrome-stable.deb; \
  fi && \
  echo "**** application tweaks ****" && \
  sed -i 's#^Exec=.*#Exec=/usr/local/bin/wrapped-chromium#g' \
    /usr/share/applications/chromium.desktop && \
  echo "**** kde tweaks ****" && \
  sed -i \
    's/applications:org.kde.discover.desktop,/applications:org.kde.konsole.desktop,/g' \
    /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf /config/.cache /config/.launchpadlib /var/lib/apt/lists/* /var/tmp/* /tmp/*

# Initialize bash-completion and command-not-found databases
# This ensures apt tab completion works properly
RUN apt-get update && \
    apt-get install -y apt-file command-not-found && \
    apt-file update && \
    /usr/lib/cnf-update-db && \
    # Disable docker-clean that prevents apt cache completion
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    # Configure apt to keep cache files for completion
    mkdir -p /etc/apt/apt.conf.d && \
    echo 'Dir::Cache::pkgcache "/var/cache/apt/pkgcache.bin";' > /etc/apt/apt.conf.d/00-apt-cache-completion && \
    echo 'Dir::Cache::srcpkgcache "/var/cache/apt/srcpkgcache.bin";' >> /etc/apt/apt.conf.d/00-apt-cache-completion && \
    # Generate apt cache for package name completion
    apt-cache gencaches && \
    chmod 644 /var/cache/apt/*.bin && \
    # Verify cache files were created
    ls -la /var/cache/apt/*.bin
    
# add local files for KDE webtop
COPY kde-root/ /

# ports and volumes
EXPOSE 3000
VOLUME /config

ENTRYPOINT ["/init"]
