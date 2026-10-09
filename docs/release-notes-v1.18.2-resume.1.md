「局域网给我」是基于 LocalSend 1.18.2 的二次开发版本，在保持协议互通的前提下新增**断点续传**。

## 下载（按平台选择）

| 平台 | 文件 | 说明 |
|---|---|---|
| **Android** | `juyuwanggeiwo-1.18.2-6453-arm64-v8a.apk` | 现代安卓手机（推荐） |
| Android | `juyuwanggeiwo-1.18.2-6453-armeabi-v7a.apk` | 早期 32 位设备 |
| Android | `juyuwanggeiwo-1.18.2-6453-x86_64.apk` | 安卓模拟器 / x86 平板 |
| **macOS** | `juyuwanggeiwo-1.18.2-macos-universal.dmg` | 通用二进制（Apple Silicon + Intel），macOS 11+ |
| **Linux** | `juyuwanggeiwo-1.18.2-linux-x86_64.tar.gz` | 解压后运行 `juyuwanggeiwo`（需 GTK3） |
| **Windows** | `juyuwanggeiwo-1.18.2-windows-x64.zip` / `-setup.exe` | 绿色版 / Inno 安装包（构建中，稍后附上） |

校验和见附件 `SHA256SUMS.txt`。安装包均为**自签名/未签名**（无 Apple 开发者账号、无 Windows 代码签名证书），首次打开可能被系统拦截，属正常现象：
- **macOS**：右键 App → 打开；或 `xattr -dr com.apple.quarantine /Applications/juyuwanggeiwo.app`
- **Windows**：SmartScreen 提示时点"更多信息 → 仍要运行"
- **Android**：允许"未知来源"安装

## 亮点：断点续传

- **中断后只补缺失部分**：发送中断（关应用 / 断网 / 换网）后重发同一文件，接收端只收缺少的尾部，不再整包重传。
- **跨重启续传**：未完成进度持久化，接收端重启后仍可继续。
- **半截文件一眼可见**：中断文件改名为 `文件名.part`，续传成功后改回原名；目标位置已有同名文件时**绝不覆盖**。
- **校验不降级**：续传后仍校验**整个文件**的 SHA-256（磁盘上已收到的前缀一并参与），前缀被改动会报错而非产出坏文件。
- **重试按钮可用**：失败后重试会重新协商会话并带上偏移（修复了此前"重试必失败"的问题）。

## 兼容性（重要）

- 与官方 LocalSend **互通**：新增的 `resume` 字段与 `/upload` 的 `offset` 参数在无需续传时**完全不出现在报文里**，协议路径 `/api/localsend/v2/*`、组播格式与 HTTP 头均未改动。
- 与官方版互传时**不会触发续传**（该扩展只有本应用实现），断点续传需要两端都为本应用。

## 来源与许可

基于 [LocalSend](https://github.com/localsend/localsend)（Apache License 2.0）二次开发，与上游项目方无隶属关系。许可证见仓库 `LICENSE`，相对上游的修改说明见 `NOTICE`。
