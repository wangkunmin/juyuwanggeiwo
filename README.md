# 局域网给我（Juyuwanggeiwo）

> 局域网传输 · 跨平台互传 · 断点续传

在同一个局域网内互传文件与文字：手机 ↔ 电脑 ↔ 平板，不依赖互联网，文件不经由任何服务器。

本仓库基于 [LocalSend](https://github.com/localsend/localsend) 的协议实现二次开发，与 LocalSend 项目方无隶属关系；协议保持兼容，可与 LocalSend 客户端及其他兼容实现互传。详见[许可与致谢](#许可与致谢)。

## 特性

- **局域网直传**：同一 Wi-Fi 下自动发现设备，不消耗流量，不经过中转服务器
- **跨平台**：Android、iOS、Windows、macOS、Linux；另提供浏览器收发模式，接收方无需安装
- **加密传输**：HTTPS + 设备自签证书，双向校验证书指纹；接收端可设置 PIN 码
- **批量与文件夹**：一次发送多个文件或整个目录，保留目录结构
- **断点续传**：传输中断后从已接收的位置继续，而不是整包重传；接收端重启后仍可继续（见下）
- **多语言界面**：内置 50 多种语言

## 断点续传

传输中断（对端离线、切网、应用被杀）后，再次发送同一文件不会从 0 开始：

- **接收端记录进度**：已落盘的字节数写在一份未完成档案里（应用支持目录），应用重启后
  自动对账——文件被删除、被截断或档案过期（7 天）的条目会被丢弃；
- **半截文件可见**：中断的文件会改名为 `文件名.part`，接收方一眼能看出"没传完"，
  续传成功后自动改回原名；同名文件已存在时绝不覆盖；
- **按偏移续传**：接收端在协商阶段告知自己已有多少字节，发送端只补缺少的尾部；
- **校验不降级**：续传后仍然校验**整个文件**的 SHA-256（磁盘上的前缀一并参与计算），
  前缀被改动会被检出（422），不会产出坏文件；
- **重试即可续传**：失败后点重试会重新协商会话并带上偏移（不再因旧令牌失效而必败）。

**兼容性**：这些能力是本仓库对协议的扩展——`prepare-upload` 响应里的可选 `resume`
字段与 `/upload` 的可选 `offset` 参数。两者缺省时行为与上游 LocalSend 完全一致，
因此：

| 场景 | 结果 |
|---|---|
| 本应用 → 官方 LocalSend | 正常传输（扩展字段被忽略） |
| 官方 LocalSend → 本应用 | 正常传输（不回偏移，接收端从 0 开始） |
| 本应用 ↔ 本应用 | 完整续传能力 |

技术细节与兼容性矩阵见 [docs/断点续传方案.md](docs/断点续传方案.md)。

## 支持的平台

| 平台 | 最低版本 |
|---|---|
| Android | 7.0 |
| iOS | 13.0 |
| Windows | 10 |
| macOS | 11 |
| Linux | 依赖 xdg-desktop-portal |
| 浏览器 | Web 链接收发模式 |

## 获取与安装

目前尚未发布安装包，请从源码构建（见下）。上游 LocalSend 的安装包见[其发布页](https://github.com/localsend/localsend/releases)。

## 从源码构建

**容器（推荐）**：仓库自带 Docker 环境，锁定 Rust 1.97.1 / Flutter 3.41.9 / FRB 2.12.0，并复现 CI 的检查步骤。

```bash
docker compose -f docker/compose.yaml run --rm rust-test    # Rust：clippy + core/server 测试
docker compose -f docker/compose.yaml run --rm dart-test    # Dart：分析 + 单元测试
docker compose -f docker/compose.yaml run --rm android-apk  # 打包 Android APK
docker compose -f docker/compose.yaml run --rm dev          # 交互开发 shell
```

各 target、镜像源配置与平台限制见 [docker/README.md](docker/README.md)。**iOS / macOS / Windows 需在各自宿主上构建**，无法在 Linux 容器内完成。

**本地工具链**：用 `fvm` 管理 Flutter（版本见 [.fvmrc](.fvmrc)），Rust 版本见 [rust-toolchain.toml](rust-toolchain.toml)；核心库测试需带 `--features full`。完整命令与架构说明见 [AGENTS.md](AGENTS.md)。

## 使用

1. 让两台设备接入同一局域网，打开应用；
2. 发送端选择文件或文件夹，再选择目标设备；
3. 接收端确认接收（可开启"快速保存"自动接收，或用 PIN 码保护），文件保存到指定目录或相册；
4. 接收方没有安装本应用时，可用 Web 链接模式在浏览器中接收或发送。

`cli/` 目录提供命令行客户端，适合无界面环境或脚本化传输。

## 许可与致谢

- **许可**：代码采用 [Apache License 2.0](LICENSE)。分发时请保留许可证与归属声明；本仓库对上游文件的修改记录见 [NOTICE](NOTICE)，上游原始说明保留在 [README.upstream.md](README.upstream.md)。
- **上游**：[LocalSend](https://github.com/localsend/localsend)（Apache License 2.0，基线提交 `c5bbe3630bb50e0de8253502b41523c4a58825bb`）与协议规范 [localsend/protocol](https://github.com/localsend/protocol)，以及上游作者、贡献者与 Weblate 上的译者。
