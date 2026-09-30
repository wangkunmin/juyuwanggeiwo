# 容器化开发环境（Docker）

本目录用一套镜像覆盖本项目的全部工具链，**版本与仓库锁定值一致**，并把 CI 的检查步骤原样搬进容器，做到"本地跑什么、CI 跑什么、容器跑什么"三者一致。

| 组件 | 版本 | 来源（锁定处） |
|---|---|---|
| Rust | 1.97.1 | [rust-toolchain.toml](../rust-toolchain.toml) |
| Flutter / Dart | 3.41.9 / 3.11 | [.fvmrc](../.fvmrc)、[app/pubspec.yaml](../app/pubspec.yaml) |
| flutter_rust_bridge codegen | 2.12.0 | [packages/localsend_isolates/pubspec.yaml](../packages/localsend_isolates/pubspec.yaml) |
| Android SDK / JDK | compileSdk 36、build-tools 36.0.0、JDK 17 | [app/android/app/build.gradle](../app/android/app/build.gradle) |

容器内**不需要 fvm**：镜像里装的就是 3.41.9 这个确切版本。

---

## 1. 前置条件

- Docker 引擎（macOS 上 OrbStack / Docker Desktop 均可；本项目在 OrbStack ARM64 上开发验证）
- 能访问：`storage.googleapis.com`（Flutter SDK）、`dl.google.com`（Android SDK）、`crates.io`、`pub.dev`、`services.gradle.org`
- **Docker Hub 直连不通时**（国内常见）用镜像源覆盖：

```bash
REGISTRY=docker.m.daocloud.io docker compose -f docker/compose.yaml build rust-test
```

- **`static.rust-lang.org` 不通时**：镜像内已预装 `Rust 1.97.1`，构建默认通过
  `RUSTUP_TOOLCHAIN=1.97.1` 直接使用它、不再联网同步；只有在补装组件（clippy）时才需要源，
  可换成国内镜像：

```bash
RUSTUP_DIST_SERVER=https://rsproxy.cn docker compose -f docker/compose.yaml build rust-test
```

- **`deb.debian.org` 太慢时**（实测 20s 超时，而阿里云 0.2s），换 Debian 源主机：

```bash
DEBIAN_MIRROR=mirrors.aliyun.com docker compose -f docker/compose.yaml build rust-test
```

以上三个变量可同时使用：

```bash
REGISTRY=docker.m.daocloud.io RUSTUP_DIST_SERVER=https://rsproxy.cn \
DEBIAN_MIRROR=mirrors.aliyun.com docker compose -f docker/compose.yaml build rust-test
```

- **`index.crates.io` 太慢时**（实测 21s 才返回索引小文件），换 crates.io sparse 源：

```bash
CARGO_MIRROR=sparse+https://rsproxy.cn/index/ docker compose -f docker/compose.yaml build rust-test
```

- **Flutter SDK / pub 下载慢时**（实测官方源约 1 MB/s，国内镜像约 8.6 MB/s）：

```bash
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
PUB_HOSTED_URL=https://pub.flutter-io.cn \
docker compose -f docker/compose.yaml build dart-test
```

四个变量可一起使用：

```bash
REGISTRY=docker.m.daocloud.io \
RUSTUP_DIST_SERVER=https://rsproxy.cn \
DEBIAN_MIRROR=mirrors.aliyun.com \
CARGO_MIRROR=sparse+https://rsproxy.cn/index/ \
docker compose -f docker/compose.yaml build rust-test
```

`REGISTRY` 只影响基础镜像从哪拉取；`debian`、`rust` 这类官方镜像在镜像源上都以 `library/` 命名空间存在，Dockerfile 已按此拼装。

## 2. 快速开始

```bash
cd <仓库根目录>

# ① Rust 核心测试（等价于 CI 的 rust job：clippy + test + server + 插件/CLI 检查）
docker compose -f docker/compose.yaml build rust-test
docker compose -f docker/compose.yaml run --rm rust-test

# ② Dart/Flutter 分析 + 测试（等价于 CI 的 test job）
docker compose -f docker/compose.yaml run --rm dart-test

# ③ 格式检查（等价于 CI 的 format job：先删 lib/gen 再检查）
docker compose -f docker/compose.yaml run --rm dart-format

# ④ 发布前版本一致性（pubspec / Inno / CLI / MSIX / AppImage）
docker compose -f docker/compose.yaml run --rm version-check

# ⑤ Android APK
docker compose -f docker/compose.yaml run --rm android-apk
#   产物：app/build/app/outputs/flutter-apk/app-release.apk

# ⑥ Linux 桌面
docker compose -f docker/compose.yaml run --rm linux-app

# ⑦ 进入交互 shell（Rust + Flutter + Android SDK + FRB codegen 全都有）
docker compose -f docker/compose.yaml run --rm dev
```

首次构建会下载镜像与 SDK（Rust 镜像约 1 GB+、Flutter SDK 约 1 GB、Android SDK 约 1–2 GB），**耗时较长但只发生一次**；之后依赖缓存卷会让重复构建快很多。

## 3. 单独的 Dockerfile target

不在 compose 里操作时，可直接用 build target：

| target | 作用 | 对应 CI |
|---|---|---|
| `rust-check` | `cargo check --features full`，最快的类型检查 | — |
| `rust-test` | clippy（core，`--all-targets`）+ core 测试 + server 测试 + 插件/CLI 检查 | `rust` job |
| `dart-format` | `rm -rf lib/gen` + `dart format --set-exit-if-changed lib test` | `format` job |
| `dart-test` | `flutter analyze` + `flutter test`（app、isolates） | `test` job |
| `version-check` | 五处版本号一致性 | `packaging` job 前半 |
| `codegen` | 预编译版 `flutter_rust_bridge_codegen` 2.12.0 + Rust(nightly) + `cargo-expand` | — |
| `dart-build-runner` | `build_runner`（dart_mappable/freezed/flutter_gen）+ `slang` i18n 生成 | — |
| `android-apk` | Rust(NDK 交叉编译) + Android SDK → `flutter build apk --release` | — |
| `linux-app` | GTK 依赖 + Rust → `flutter build linux --release` | — |
| `dev` | 以上全部 + 交互 shell | — |

```bash
docker build -f docker/Dockerfile --target rust-test -t lsg-rust-test .
```

FRB 代码生成（注意生成物会写回宿主仓库，执行前先确保工作区干净）：

```bash
docker build -f docker/Dockerfile --target codegen -t lsg-codegen .
docker run --rm -v "$PWD":/src lsg-codegen \
  sh -c 'cd packages/localsend_isolates && flutter_rust_bridge_codegen generate'
```

## 3.5 Apple Silicon（arm64）上的注意事项

Flutter **只发布 x86_64 的 Linux SDK**（官方发布清单里没有 Linux arm64 归档），因此 `codegen`、`dart-format`、`dart-test`、`version-check`、`android-apk`、`linux-app`、`dev` 这些服务在 compose 里固定为 `platform: linux/amd64`：

- **OrbStack**：默认已开启 x86_64 模拟（`orbctl config get rosetta` → `true`），可直接使用；
- **Docker Desktop**：需在设置里勾选 “Use Rosetta for x86/amd64 emulation”；
- 未开启模拟时会报 `Dynamic loader not found: /lib64/ld-linux-x86-64.so.2`；
- 纯 Rust 的服务（`rust-check`/`rust-test`）仍以宿主架构（arm64）原生运行，速度正常；
- 如果在 arm64 宿主上长期开发 Flutter 侧，**直接用宿主 macOS 的 fvm/Flutter 会快得多**，容器主要用于 CI 等价验证。

### 完全离线/加速：用宿主已有的 Flutter SDK

容器内下载 Flutter SDK 往往比宿主慢一个数量级。可以只在宿主下载一次，再用本地 HTTP 服务喂给构建：

```bash
mkdir -p /tmp/flutter-mirror/flutter_infra_release/releases/stable/linux
cd /tmp/flutter-mirror/flutter_infra_release/releases/stable/linux
curl -O https://storage.flutter-io.cn/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.9-stable.tar.xz
cd /tmp/flutter-mirror && python3 -m http.server 8931 --bind 0.0.0.0 &
FLUTTER_STORAGE_BASE_URL=http://host.docker.internal:8931 \
  docker compose -f docker/compose.yaml build dart-test
```

### 注意：pub 镜像会改写 `pubspec.lock`

用 `PUB_HOSTED_URL` 指向镜像后，`flutter pub get` 会把 lock 文件里每个包的 `url` 改成镜像地址（版本号不变）。
提交前请回滚，避免给上游锁文件带来无谓 diff：

```bash
git checkout -- pubspec.lock
```

## 4. 平台限制（重要）

| 目标 | 能否在 Linux 容器内构建 | 说明 |
|---|---|---|
| Rust 测试 / Dart 测试 | ✅ | 与 CI 完全一致 |
| Android APK | ✅ | arm64 宿主上通过 NDK 交叉编译四种 ABI |
| Linux 桌面（deb/AppImage 前一步） | ✅ | 需要 GTK3 等系统库，镜像已装 |
| Web | ⚠️ 未提供 | 需 wasm 版 Rust/FRB 支持，建议先在容器外验证 |
| **iOS / macOS** | ❌ | 必须 macOS + Xcode |
| **Windows** | ❌ | 必须 Windows + MSVC（容器内无法出 MSIX/EXE） |

## 5. 常见问题

- **NDK 版本**：镜像会从 Flutter SDK 中解析其期望的 `ndkVersion` 并安装；若解析失败则回退到 `27.0.12077973`，也可用 `--build-arg NDK_VERSION=xx.y.z` 显式指定。
- **`cargo`/`flutter` 找不到**：请用 `dev` target，它同时具备 Rust 与 Flutter 环境变量（`CARGO_HOME=/usr/local/cargo`、`PATH=/opt/flutter/bin:...`）。
- **生成物属主**：Linux 宿主机上容器以 root 写入会得到 root 属主，必要时构建后 `sudo chown -R $(id -u):$(id -g) .`；macOS（OrbStack/Docker Desktop）通常无需处理。
- **安全**：所有 target 都不需要 `--privileged`，也不需要挂载 Docker socket。
- **首次 `rust-test` 很慢**：`--features full` 包含 WebRTC 相关依赖，首次编译属于正常现象；`cargo-target` 缓存卷会在后续复用。
