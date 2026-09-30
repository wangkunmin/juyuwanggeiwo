# 局域网给我（Juyuwanggeiwo）

> 局域网传输 · 跨平台互传 · 断点续传

基于 LocalSend 协议实现二次开发的局域网（LAN）点对点文件互传工具，支持手机 ↔ 电脑 ↔ 平板之间互传，不需要互联网、不经过服务器。与上游的差异点是**断点续传**（设计与进度见[断点续传方案](docs/断点续传方案.md)）；目前已完成项目标识切换，功能改造尚未开始。

- **非官方项目**：本仓库是社区二次开发，与 LocalSend 项目方无隶属关系。
- **可与 LocalSend 互传**：协议路径保持 `/api/localsend/v2/*` 不变，能与官方客户端及其他兼容实现互通；包名不同，可与原版共存。
- **许可与归属**：代码采用 [Apache License 2.0](LICENSE)；上游来源与修改说明见 [NOTICE](NOTICE)，上游原始说明保留在 [README.upstream.md](README.upstream.md)。

## 支持的平台

| 平台 | 最低版本 |
|---|---|
| Android | 7.0 |
| iOS | 13.0 |
| Windows | 10 |
| macOS | 11 |
| Linux | 依赖 xdg-desktop-portal |
| 浏览器 | Web 链接收发模式 |

## 构建

推荐使用仓库自带的容器环境（锁定 Rust 1.97.1 / Flutter 3.41.9 / FRB 2.12.0，并复现 CI 的检查步骤）：

```bash
docker compose -f docker/compose.yaml run --rm rust-test    # Rust：clippy + core/server 测试
docker compose -f docker/compose.yaml run --rm dart-test    # Dart：分析 + 单元测试
docker compose -f docker/compose.yaml run --rm android-apk  # 打包 Android APK
docker compose -f docker/compose.yaml run --rm dev          # 交互开发 shell
```

国内网络可配置镜像源（见 [docker/README.md](docker/README.md)）；各 target、平台限制与常见问题同样见该文档。
**iOS / macOS / Windows 无法在 Linux 容器内构建**，须在各自宿主完成。

不使用容器时：用 `fvm` 管理 Flutter（版本见 [.fvmrc](.fvmrc)），Rust 版本见 [rust-toolchain.toml](rust-toolchain.toml)，核心库测试需带 `--features full`。完整命令、仓库结构与架构说明见 [AGENTS.md](AGENTS.md)。

## 文档

- [docs/断点续传方案.md](docs/断点续传方案.md) — 协议扩展设计、兼容矩阵、分阶段路线与上游调研
- [docs/改名清单.md](docs/改名清单.md) — 与上游的标识差异、已完成项与验收方式
- [docker/README.md](docker/README.md) — 容器化环境用法
- [AGENTS.md](AGENTS.md) — 仓库结构、架构与开发约定（上游技术文档）

## 与上游同步

```bash
git fetch upstream && git rebase upstream/main
```

## 致谢

- [LocalSend](https://github.com/localsend/localsend)（Apache License 2.0，基线 `c5bbe3630bb50e0de8253502b41523c4a58825bb`）
- [localsend/protocol](https://github.com/localsend/protocol) 协议规范
- 上游作者、贡献者，以及 Weblate 上的译者
