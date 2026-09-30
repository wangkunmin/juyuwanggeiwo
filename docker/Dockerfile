# syntax=docker/dockerfile:1.7
#
# 局域网给我（Juyuwanggeiwo）容器化开发环境
# =============================================================================
# 一套镜像覆盖：Rust 核心测试与 clippy、Dart/Flutter 格式检查与测试、FRB 代码生成、
# Android APK 打包、Linux 桌面打包、发布前版本一致性检查。
# 各 target 的步骤与 .github/workflows/ci.yml 保持一致，便于本地复现 CI。
#
# 工具链版本与仓库锁定值一致：
#   Rust    1.97.1  （rust-toolchain.toml）
#   Flutter 3.41.9  （.fvmrc / app/pubspec.yaml / ci.yml）
#   FRB     2.12.0  （packages/localsend_isolates/pubspec.yaml）
#   Android compileSdk 36 / targetSdk 37 / JDK 17（app/android/app/build.gradle）
#
# 用法（在仓库根目录执行）：
#   docker build -f docker/Dockerfile --target rust-test     -t lsg-rust-test .
#   docker build -f docker/Dockerfile --target dart-test     -t lsg-dart-test .
#   docker build -f docker/Dockerfile --target dart-format   -t lsg-dart-format .
#   docker build -f docker/Dockerfile --target version-check -t lsg-version-check .
#   docker build -f docker/Dockerfile --target android-apk   -t lsg-android .
#   docker build -f docker/Dockerfile --target linux-app     -t lsg-linux .
#   docker build -f docker/Dockerfile --target dev           -t lsg-dev .
#   或直接用 docker/compose.yaml（见 docker/README.md）
#
# 国内网络若无法直连 Docker Hub，用镜像源覆盖（OrbStack 已内置镜像，可直接拉取）：
#   docker build --build-arg REGISTRY=docker.m.daocloud.io ...
#
# 平台限制：iOS / macOS / Windows 目标**无法**在 Linux 容器内构建，须在各自宿主完成。
# =============================================================================

ARG REGISTRY=docker.io
# 若所用镜像源上没有 1.97.1 这个 tag，可改用 rust:1-bookworm —— 容器内的 rustup 会依据
# 仓库里的 rust-toolchain.toml 自动安装 1.97.1。
ARG RUST_IMAGE=rust:1.97.1-bookworm
ARG FLUTTER_VERSION=3.41.9
ARG FRB_VERSION=2.12.0
ARG ANDROID_CMDLINE_TOOLS=commandlinetools-linux-11076708_latest.zip
ARG ANDROID_COMPILE_SDK=android-36
ARG ANDROID_BUILD_TOOLS=36.0.0
# Debian 包源主机名。部分网络下 deb.debian.org 极慢（实测 20s 超时，而阿里云 0.2s、
# 中科大 0.6s），可用 DEBIAN_MIRROR=mirrors.aliyun.com 覆盖。
ARG DEBIAN_MIRROR=deb.debian.org
# 可选的 crates.io 源（sparse 索引地址）。国内直连 index.crates.io 实测 21s 才返回一个
# 小文件，可换成 sparse+https://rsproxy.cn/index/ 或 sparse+https://mirrors.ustc.edu.cn/crates.io-index/
ARG CARGO_MIRROR=

# =============================================================================
# 1) Rust 层（含完整测试）
# =============================================================================
FROM ${REGISTRY}/library/${RUST_IMAGE} AS rust

# Rust 工具链固定：
#  - RUSTUP_TOOLCHAIN 让 rustup 直接使用镜像内已安装的 1.97.1，**不再联网**同步
#    channel 清单（否则在无法访问 static.rust-lang.org 的网络里会卡住/失败）。
#    若要改为由仓库的 rust-toolchain.toml 决定，传 RUSTUP_TOOLCHAIN= 空值即可。
#  - RUSTUP_DIST_SERVER：需要在构建期补装组件（clippy）时用的源；国内可换成
#    https://rsproxy.cn 或 https://mirrors.ustc.edu.cn/rust-static
ARG RUST_TOOLCHAIN=1.97.1
ARG RUSTUP_DIST_SERVER=https://static.rust-lang.org
ENV RUSTUP_TOOLCHAIN=${RUST_TOOLCHAIN}
ENV RUSTUP_DIST_SERVER=${RUSTUP_DIST_SERVER}

ARG CARGO_MIRROR
RUN if [ -n "${CARGO_MIRROR}" ]; then \
        printf '[source.crates-io]\nreplace-with = "mirror"\n\n[source.mirror]\nregistry = "%s"\n' "${CARGO_MIRROR}" > "${CARGO_HOME}/config.toml"; \
        cat "${CARGO_HOME}/config.toml"; \
    fi

ENV DEBIAN_FRONTEND=noninteractive
# build-essential/pkg-config/libssl-dev/cmake/perl：ring、dtls、openssl-sys 等依赖的构建兜底
ARG DEBIAN_MIRROR
RUN set -eux; \
    if [ "${DEBIAN_MIRROR}" != "deb.debian.org" ]; then \
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do \
            [ -f "$f" ] || continue; \
            sed -i "s|deb.debian.org|${DEBIAN_MIRROR}|g; s|security.debian.org|${DEBIAN_MIRROR}|g" "$f"; \
        done; \
    fi; \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential pkg-config libssl-dev cmake perl git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && rustup component add clippy

WORKDIR /src
COPY . .

# ---- rust-check：开发内循环用的快速类型检查 ---------------------------------
FROM rust AS rust-check
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo check -p localsend --features full

# ---- rust-test：与 CI 的 rust job 对齐 --------------------------------------
FROM rust AS rust-test
# core 默认 feature 为空，必须 --features full（见 AGENTS.md）
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cd packages/core && cargo clippy --features full --all-targets
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cd packages/core && cargo test --features full
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo test --package server
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo check --package rust_lib_localsend_app --package localsend-cli

# =============================================================================
# 2) Flutter 层（官方 SDK 固定版本；容器内即为锁定版本，无需 fvm）
# =============================================================================
FROM ${REGISTRY}/library/debian:bookworm-slim AS flutter-base
ARG FLUTTER_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    FLUTTER_ROOT=/opt/flutter \
    PUB_CACHE=/root/.pub-cache \
    PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH

ARG DEBIAN_MIRROR
RUN set -eux; \
    if [ "${DEBIAN_MIRROR}" != "deb.debian.org" ]; then \
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do \
            [ -f "$f" ] || continue; \
            sed -i "s|deb.debian.org|${DEBIAN_MIRROR}|g; s|security.debian.org|${DEBIAN_MIRROR}|g" "$f"; \
        done; \
    fi; \
    apt-get update && apt-get install -y --no-install-recommends \
        curl git unzip xz-utils zip ca-certificates file \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 3 \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        -o /tmp/flutter.tar.xz \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics >/dev/null \
    && flutter --version

WORKDIR /src
COPY . .

# ---- dart-format：与 CI 的 format job 对齐（先删 lib/gen，再检查格式） -------
FROM flutter-base AS dart-format
RUN --mount=type=cache,target=/root/.pub-cache \
    cd app && flutter pub get \
    && cd /src/packages/localsend_isolates/rust_builder/cargokit/build_tool && flutter pub get \
    && cd /src/app && rm -rf lib/gen \
    && dart format --set-exit-if-changed lib test

# ---- dart-test：与 CI 的 test job 对齐 --------------------------------------
FROM flutter-base AS dart-test
RUN --mount=type=cache,target=/root/.pub-cache \
    cd app && flutter pub get \
    && cd /src/packages/localsend_isolates/rust_builder/cargokit/build_tool && flutter pub get \
    && cd /src/app && flutter analyze \
    && flutter test
RUN --mount=type=cache,target=/root/.pub-cache \
    cd packages/localsend_isolates && flutter pub get && flutter test

# ---- version-check：发布前版本一致性（CI packaging job 的前半段） -----------
FROM flutter-base AS version-check
RUN set -eux; \
    pv=$(grep '^version: ' app/pubspec.yaml | sed 's/version: //' | sed 's/\+.*//'); \
    iv=$(grep '#define MyAppVersion ' support/scripts/compile_windows_exe-inno.iss | sed 's/#define MyAppVersion "//' | sed 's/"//'); \
    cv=$(grep '^version = ' cli/Cargo.toml | sed 's/version = "//' | sed 's/"//'); \
    mv=$(grep -o ' Version="[0-9.]*"' support/build/msix/content/AppxManifest.xml | sed 's/ Version="//' | sed 's/"//'); \
    ax=$(grep '^    version: ' support/build/appimage/AppImageBuilder_x86_64.yml | sed 's/    version: //'); \
    aa=$(grep '^    version: ' support/build/appimage/AppImageBuilder_arm_64.yml | sed 's/    version: //'); \
    echo "pubspec=$pv inno=$iv cli=$cv msix=$mv appimage-x86_64=$ax appimage-arm64=$aa"; \
    test "$pv" = "$iv"; test "$pv" = "$cv"; test "$pv.0" = "$mv"; test "$pv" = "$ax"; test "$pv" = "$aa"; \
    echo "版本一致性检查通过"

# ---- codegen：flutter_rust_bridge 代码生成（预编译二进制，免 cargo install） --
FROM flutter-base AS codegen
ARG FRB_VERSION
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      amd64) FRB_TARGET=x86_64-unknown-linux-musl ;; \
      arm64) FRB_TARGET=aarch64-unknown-linux-musl ;; \
      *) echo "unsupported arch"; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 \
      "https://github.com/fzyzcjy/flutter_rust_bridge/releases/download/v${FRB_VERSION}/flutter_rust_bridge_codegen-${FRB_TARGET}-v${FRB_VERSION}.tgz" \
      -o /tmp/frb.tgz; \
    tar -xzf /tmp/frb.tgz -C /tmp; \
    find /tmp -type f -name 'flutter_rust_bridge_codegen' -exec install -m 0755 {} /usr/local/bin/ \;; \
    rm -f /tmp/frb.tgz; \
    flutter_rust_bridge_codegen --version
# 运行（生成物会写回宿主仓库，注意先提交/备份）：
#   docker run --rm -v "$PWD":/src lsg-codegen \
#     sh -lc 'cd packages/localsend_isolates && flutter_rust_bridge_codegen generate'

# =============================================================================
# 3) Android 打包层：Flutter + Rust(NDK 交叉编译) + Android SDK
# =============================================================================
FROM flutter-base AS android-apk
ARG ANDROID_CMDLINE_TOOLS
ARG ANDROID_COMPILE_SDK
ARG ANDROID_BUILD_TOOLS
ARG NDK_VERSION

ENV ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    PATH=/usr/local/cargo/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH

# Rust 工具链：cargokit 在 Flutter 构建期间用 cargo 交叉编译 Rust 插件
COPY --from=rust /usr/local/cargo /usr/local/cargo
COPY --from=rust /usr/local/rustup /usr/local/rustup

ARG DEBIAN_MIRROR
RUN set -eux; \
    if [ "${DEBIAN_MIRROR}" != "deb.debian.org" ]; then \
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do \
            [ -f "$f" ] || continue; \
            sed -i "s|deb.debian.org|${DEBIAN_MIRROR}|g; s|security.debian.org|${DEBIAN_MIRROR}|g" "$f"; \
        done; \
    fi; \
    apt-get update && apt-get install -y --no-install-recommends \
        openjdk-17-jdk-headless unzip \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"; \
    curl -fsSL --retry 3 "https://dl.google.com/android/repository/${ANDROID_CMDLINE_TOOLS}" -o /tmp/cmdline.zip; \
    unzip -q /tmp/cmdline.zip -d "$ANDROID_SDK_ROOT/cmdline-tools"; \
    mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"; \
    rm /tmp/cmdline.zip; \
    yes | sdkmanager --licenses >/dev/null || true; \
    sdkmanager --install "platform-tools" "platforms;${ANDROID_COMPILE_SDK}" "build-tools;${ANDROID_BUILD_TOOLS}" "cmake;3.22.1"; \
    NDK="${NDK_VERSION:-$(grep -rhoE 'ndkVersion *= *"[0-9.]+"' /opt/flutter/packages/flutter_tools/gradle/ 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')}"; \
    NDK="${NDK:-27.0.12077973}"; \
    echo "Installing NDK $NDK (优先取 Flutter 期望版本)"; \
    sdkmanager --install "ndk;${NDK}"; \
    rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android

RUN --mount=type=cache,target=/root/.pub-cache \
    --mount=type=cache,target=/root/.gradle \
    --mount=type=cache,target=/src/target \
    cd app && flutter pub get && flutter build apk --release

# =============================================================================
# 4) Linux 桌面打包层（GTK + Rust）
# =============================================================================
FROM flutter-base AS linux-app

ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    PATH=/usr/local/cargo/bin:$PATH

COPY --from=rust /usr/local/cargo /usr/local/cargo
COPY --from=rust /usr/local/rustup /usr/local/rustup

ARG DEBIAN_MIRROR
RUN set -eux; \
    if [ "${DEBIAN_MIRROR}" != "deb.debian.org" ]; then \
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do \
            [ -f "$f" ] || continue; \
            sed -i "s|deb.debian.org|${DEBIAN_MIRROR}|g; s|security.debian.org|${DEBIAN_MIRROR}|g" "$f"; \
        done; \
    fi; \
    apt-get update && apt-get install -y --no-install-recommends \
        clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
        libstdc++-12-dev libsecret-1-dev libjsoncpp-dev \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/root/.pub-cache \
    --mount=type=cache,target=/src/target \
    cd app && flutter pub get && flutter build linux --release

# =============================================================================
# 5) 交互开发层：Rust + Flutter + Android SDK + FRB codegen 全在一台容器里
#    docker run --rm -it -v "$PWD":/src lsg-dev
# =============================================================================
FROM android-apk AS dev
ARG FRB_VERSION
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      amd64) FRB_TARGET=x86_64-unknown-linux-musl ;; \
      arm64) FRB_TARGET=aarch64-unknown-linux-musl ;; \
      *) echo "unsupported arch"; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 \
      "https://github.com/fzyzcjy/flutter_rust_bridge/releases/download/v${FRB_VERSION}/flutter_rust_bridge_codegen-${FRB_TARGET}-v${FRB_VERSION}.tgz" \
      -o /tmp/frb.tgz; \
    tar -xzf /tmp/frb.tgz -C /tmp; \
    find /tmp -type f -name 'flutter_rust_bridge_codegen' -exec install -m 0755 {} /usr/local/bin/ \;; \
    rm -f /tmp/frb.tgz; \
    flutter_rust_bridge_codegen --version
WORKDIR /src
CMD ["bash"]
