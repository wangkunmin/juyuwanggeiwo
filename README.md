# 局域网给我（Juyuwanggeiwo）

> 局域网传输 · 跨平台互传 · 断点续传

一个局域网（LAN）点对点文件互传工具，**在 LocalSend 协议实现之上二次开发**，目标是把"传大文件中断就得从头再来"这件事解决掉——即**断点续传**。

> 当前状态：仓库刚建立，代码基线为上游 LocalSend `c5bbe36`，**功能改造尚未开始**。路线图见下文。

---

## ⚠️ 重要声明（请先读）

1. **本项目是非官方二次开发项目，与 LocalSend 官方没有任何隶属或背书关系。** 请勿将本项目的构建产物当作 LocalSend 官方版本使用或分发。
2. **"LocalSend" 名称与徽标归 LocalSend 项目所有**，本项目仅在"上游来源说明"的意义上以文字形式提及（Apache License 2.0 第 6 条明确不授予商标许可）。本项目不把 LocalSend 的名称、图标用于自身标识。
3. **代码来源与许可**：本项目基于 [localsend/localsend](https://github.com/localsend/localsend)（Apache License 2.0）二次开发。
   - 原始许可证全文见仓库根目录 [LICENSE](LICENSE)，**未做任何修改**；
   - 上游归属与本次修改说明见 [NOTICE](NOTICE)；
   - 上游原始 README 原样保留在 [README.upstream.md](README.upstream.md) 以便对照。
4. **本项目不属于官方应用商店渠道**：任何安装包均由本仓库自行构建，使用的包名/签名与官方不同。

---

## 1. 这是什么

一个局域网（LAN）点对点文件互传工具，支持手机 ↔ 电脑 ↔ 平板之间互传，不需要互联网、不经过服务器。技术上沿用 LocalSend 的 HTTP/HTTPS 协议（`/api/localsend/v2/*`）与多播发现机制，因此**可以与官方 LocalSend 及其他兼容实现互通**。

与上游的差异点是**断点续传**：传输中断后，从接收端已经收到的字节处继续，而不是整包重传。

## 2. 目标与路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| — | 建立仓库、改名、中文文档、法律声明 | 进行中 |
| **P0** | 修复上游"断网后重试必失败"的问题：失败文件重新协商会话与令牌 | 待开始（上游 [PR #3462](https://github.com/localsend/localsend/pull/3462) 正在做同一件事且无协议改动，先跟踪） |
| **P1** | 协议与 Rust 核心支持偏移量：`prepare-upload` 响应新增 `resume` 字段、`upload` 支持可选 `offset` 参数、接收端追加写入 + 全文件校验、失败上报已落盘字节数 | 待开始 |
| **P2** | 同一次运行内续传：接收端未完成传输档案（内存）、发送端按偏移量续传、进度语义修正 | 待开始 |
| **P3** | 跨重启续传：未完成传输档案持久化、`.part` 命名与完成时改名、启动对账与清理入口 | 待开始 |
| **P4** | 可选：发送端会话持久化、浏览器上传页分片续传、下载接口 `Range` 支持 | 待开始 |

设计细节、兼容性矩阵、风险与测试计划见 [docs/断点续传方案.md](docs/断点续传方案.md)；可行性验证脚本见 [docs/feasibility-probe.py](docs/feasibility-probe.py)。

**兼容性承诺**（P1 起）：协议扩展双向向后兼容——旧发送端忽略新增响应字段并照旧整包上传；旧接收端忽略新增查询参数。任意新旧组合都不会产生损坏文件。

## 3. 支持的平台

沿用上游实现，覆盖 Android、iOS、Windows、macOS、Linux，以及浏览器（Web 链接收发模式）。

| 平台 | 最低版本 |
|---|---|
| Android | 7.0 |
| iOS | 13.0 |
| Windows | 10 |
| macOS | 11 |
| Linux | 依赖 xdg-desktop-portal |

## 4. 构建

### 4.1 容器化环境（推荐）

仓库自带 Docker 环境，把 Rust、Flutter、Android SDK、FRB codegen 全部按锁定版本装好，并**原样复现 CI 的检查步骤**（依赖缓存走 Docker 卷，重复构建很快）：

```bash
# Rust：clippy + core 测试 + server 测试 + 插件/CLI 检查（等价 CI 的 rust job）
docker compose -f docker/compose.yaml run --rm rust-test

# Dart/Flutter：分析 + 测试（等价 CI 的 test job）
docker compose -f docker/compose.yaml run --rm dart-test

# 格式检查 / 发布前版本一致性 / 打 APK / Linux 桌面
docker compose -f docker/compose.yaml run --rm dart-format
docker compose -f docker/compose.yaml run --rm version-check
docker compose -f docker/compose.yaml run --rm android-apk
docker compose -f docker/compose.yaml run --rm linux-app

# 交互开发 shell（Rust + Flutter + Android SDK + codegen 全都有）
docker compose -f docker/compose.yaml run --rm dev
```

国内网络若无法直连 Docker Hub，加一个变量即可（本机 OrbStack 已验证可用）：

```bash
REGISTRY=docker.m.daocloud.io docker compose -f docker/compose.yaml run --rm rust-test
```

完整说明（各 target、平台限制、常见问题）见 [docker/README.md](docker/README.md)。
注意：**iOS / macOS / Windows 目标无法在 Linux 容器内构建**，须在各自宿主上完成。

### 4.2 本地工具链（不使用容器时）

工具链版本随上游锁定，**必须使用 fvm 管理 Flutter**：

| 组件 | 版本 |
|---|---|
| Flutter | 3.41.9（见 [.fvmrc](.fvmrc)） |
| Rust | 1.97.1（见 [rust-toolchain.toml](rust-toolchain.toml)） |
| flutter_rust_bridge_codegen | 2.12.x |

```bash
# 应用（Flutter）
cd app
fvm flutter pub get
fvm dart run build_runner build    # dart_mappable / freezed / flutter_gen / mockito
fvm dart run slang                 # i18n 代码生成
fvm flutter run

# Rust 核心库：默认 feature 为空，必须带 --features full
cd packages/core
cargo test --features full
```

更完整的命令、目录职责与架构说明见 [AGENTS.md](AGENTS.md)（上游技术文档，本项目继续沿用）。

## 5. 仓库结构

本仓库沿用上游的多语言 monorepo 结构：

| 路径 | 说明 |
|---|---|
| `app/` | Flutter 应用（界面、状态、持久化、平台通道） |
| `packages/core/` | Rust 协议实现（HTTP 服务端/客户端、加密、WebRTC） |
| `packages/localsend_isolates/` | Dart isolate 层 + flutter_rust_bridge 绑定 |
| `packages/typed_isolates/` | 类型化 isolate 通信封装 |
| `server/` | WebRTC 信令服务（WebSocket） |
| `cli/` | 命令行客户端 |
| `docs/` | 本项目的中文文档（断点续传方案等） |

## 6. 与上游同步

```bash
git remote add upstream https://github.com/localsend/localsend.git   # 已配置
git fetch upstream
git rebase upstream/main        # 或 merge，视改动大小而定
```

本仓库的改动尽量按"可独立评审的提交"组织，便于后续把通用修复（例如 P0）回贡上游。

## 7. 贡献

本仓库是个人主导的二次开发项目，欢迎 issue 与 PR。与上游不同，**本项目不禁止 AI 辅助开发**，但要求：

- 提交前跑通相关测试（Rust：`cargo test --features full`；Dart：`fvm flutter test`）；
- 说明改动动机、影响面与验证方式；
- 不要引入与上游不兼容的破坏性协议改动（兼容性承诺见上文）。

## 8. 许可证

[Apache License 2.0](LICENSE)，与上游一致。分发本项目的代码或二进制时，请遵守：

- 随附许可证副本（保留 `LICENSE`）；
- 保留版权与归属声明（见 `NOTICE`）；
- 对被修改的文件给出显著说明；
- 不得使用 "LocalSend" 名称或徽标暗示官方关联。

## 9. 致谢

- 上游项目：[LocalSend](https://github.com/localsend/localsend)（Apache License 2.0），基线提交 `c5bbe3630bb50e0de8253502b41523c4a58825bb`；
- 协议规范：[localsend/protocol](https://github.com/localsend/protocol)；
- 上游作者与贡献者、以及 Weblate 上的翻译者。

中文文档为本仓库主要说明文件；英文说明仅保留上游原文（`README.upstream.md`）。
