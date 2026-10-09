#!/usr/bin/env bash
#
# 一键打出 Android APK（面向 macOS / Linux 开发机）。默认**只打包，不安装**。
#
# 用法：
#   ./support/scripts/build_android_apk.sh                # 打三个 ABI 分包（release）
#   ./support/scripts/build_android_apk.sh --abi arm64    # 只关心 arm64（仍按 --split-per-abi 产出，给出对应文件）
#   ./support/scripts/build_android_apk.sh --debug        # debug 包（更快、可用调试器）
#   ./support/scripts/build_android_apk.sh --universal    # 一个通用包（含三个 ABI，体积大）
#   ./support/scripts/build_android_apk.sh --build-number 645
#   ./support/scripts/build_android_apk.sh --from-release # 不打包，直接下载 Gitee Release 里已发布的 APK
#
# 可选（默认关闭）：--install 打包/下载完成后用 adb 安装到已连接设备
#                    --device <serial> 指定设备
#
# 产物位置：app/build/app/outputs/flutter-apk/*.apk
# 自己安装的两种方式：
#   adb install -r app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#   或把 apk 传到手机（微信/网盘/USB）后点击安装，需允许「未知来源」
#
# 说明：打包在仓库自带的 Docker 环境里完成。首次会构建 lsg-android 镜像
#      （约 7 GB、15–20 分钟），之后走缓存；打包本身在 x86_64 模拟下较慢。
#      想更快可改用 CI（见 .github/workflows/）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

APK_DIR="$REPO_ROOT/app/build/app/outputs/flutter-apk"
GITEE_REPO="${GITEE_REPO:-ynzj/juyuwanggeiwo}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/.cache/juyuwanggeiwo}"

MODE="build"          # build | from-release
DEBUG_BUILD=0
UNIVERSAL=0
DO_INSTALL=0
DEVICE=""
BUILD_NUMBER=""
ABI_FILTER=""

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m注意:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
一键打出 Android APK（默认只打包，不安装）。

  ./support/scripts/build_android_apk.sh                 # 三个 ABI 分包（release）
  ./support/scripts/build_android_apk.sh --debug         # debug 包
  ./support/scripts/build_android_apk.sh --universal     # 通用包（三 ABI 合一，体积大）
  ./support/scripts/build_android_apk.sh --from-release  # 直接下载已发布的 APK（不打包，最快）
  ./support/scripts/build_android_apk.sh --build-number 645
  ./support/scripts/build_android_apk.sh --install       # 可选：打包后用 adb 安装

选项：
  --abi <arm64|v7a|x86_64>   只关注某个 ABI（仅影响提示与 --install 选择，构建仍为分包）
  --debug                    构建 debug 包（体积小、可接调试器）
  --universal                构建通用包（含全部 ABI，约 120 MB）
  --build-number <N>         覆盖 versionCode
  --from-release             不打包，下载 Gitee Release 里已发布的 APK
  --install                  打包/下载完成后用 adb 安装（需要设备与 USB 调试）
  --device <serial>          指定 adb 设备
  --help                     显示本帮助

产物目录：app/build/app/outputs/flutter-apk/
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from-release) MODE="from-release" ;;
    --debug)        DEBUG_BUILD=1 ;;
    --universal)    UNIVERSAL=1 ;;
    --install)      DO_INSTALL=1 ;;
    --abi)          ABI_FILTER="${2:-}"; shift ;;
    --device)       DEVICE="${2:-}"; shift ;;
    --build-number) BUILD_NUMBER="${2:-}"; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) die "未知参数：$1（用 --help 查看用法）" ;;
  esac
  shift
done

# ---------------------------------------------------------------- 打包
build_apk() {
  local args=""
  if [ "$UNIVERSAL" = "1" ]; then
    args="--target-platform android-arm,android-arm64,android-x64"
    [ "$DEBUG_BUILD" = "1" ] && args="--debug $args"
  else
    args="--split-per-abi"
    [ "$DEBUG_BUILD" = "1" ] && args="--debug $args"
  fi
  [ -n "$BUILD_NUMBER" ] && args="$args --build-number $BUILD_NUMBER"

  log "用 Docker 打包（首次需构建镜像，约 15–20 分钟；之后走缓存）"
  log "flutter build apk --release $args"
  APK_BUILD_ARGS="$args" \
  PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}" \
  DEBIAN_MIRROR="${DEBIAN_MIRROR:-mirrors.aliyun.com}" \
  CARGO_MIRROR="${CARGO_MIRROR:-sparse+https://rsproxy.cn/index/}" \
  RUSTUP_DIST_SERVER="${RUSTUP_DIST_SERVER:-https://rsproxy.cn}" \
  FLUTTER_SDK_BASE_URL="${FLUTTER_SDK_BASE_URL:-https://storage.flutter-io.cn}" \
  FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}" \
  docker compose -f docker/compose.yaml run --rm --no-deps android-apk
}

# ---------------------------------------------------------------- 下载已发布 APK
download_release_apk() {
  local want="$1" outdir="$TOOLS_DIR/release"
  mkdir -p "$outdir"
  log "查询 Gitee 最新 Release（$GITEE_REPO）"
  local json
  json="$(curl -fsSL "https://gitee.com/api/v5/repos/$GITEE_REPO/releases/latest")" \
    || die "无法获取 Release（检查网络）"
  local url
  url="$(printf '%s' "$json" | python3 -c '
import json,sys
want=sys.argv[1]
d=json.load(sys.stdin)
best=""
for a in d.get("assets") or []:
    n=a.get("name","")
    if n.endswith(".apk") and want in n:
        best=a.get("browser_download_url") or ""; break
print(best)
' "$want")"
  [ -n "$url" ] || die "Release 中没有匹配「$want」的 APK（可用 --abi 指定）"
  local file="$outdir/$(basename "$url")"
  if [ -s "$file" ]; then
    log "已缓存：$(basename "$file")"
  else
    log "下载 $(basename "$url")"
    curl -fL --retry 3 -o "$file" "$url"
  fi
  echo "$file"
}

# ---------------------------------------------------------------- 可选的安装
find_adb() {
  if command -v adb >/dev/null 2>&1; then command -v adb; return; fi
  local adb="$TOOLS_DIR/platform-tools/adb"
  if [ ! -x "$adb" ]; then
    log "未找到 adb，下载 Google 官方 platform-tools（约 10 MB）"
    mkdir -p "$TOOLS_DIR"
    local zip="$TOOLS_DIR/platform-tools.zip"
    local url
    case "$(uname -s)" in
      Darwin) url="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip" ;;
      Linux)  url="https://dl.google.com/android/repository/platform-tools-latest-linux.zip" ;;
      *) die "不支持的系统：$(uname -s)" ;;
    esac
    curl -fL --retry 3 -o "$zip" "$url" || die "下载失败，可手动安装：brew install --cask android-platform-tools"
    (cd "$TOOLS_DIR" && rm -rf platform-tools && unzip -q platform-tools.zip && rm -f platform-tools.zip)
    [ -x "$adb" ] || die "解压后未找到 adb"
  fi
  echo "$adb"
}

pick_device() {
  local adb="$1" devices
  devices="$("$adb" devices | awk 'NR>1 && $2=="device" {print $1}')"
  [ -n "$devices" ] || die "没有检测到已授权设备（需开启 USB 调试并在手机上点「允许」）"
  if [ -n "$DEVICE" ]; then echo "$DEVICE"; else echo "$devices" | head -1; fi
}

# ---------------------------------------------------------------- 主流程
APK=""
if [ "$MODE" = "from-release" ]; then
  want="arm64-v8a"
  case "${ABI_FILTER:-}" in
    arm64) want="arm64-v8a" ;;
    v7a)   want="armeabi-v7a" ;;
    x86_64) want="x86_64" ;;
    "")    [ "$DO_INSTALL" = "1" ] || warn "未指定 --abi，默认下载 arm64-v8a" ;;
  esac
  APK="$(download_release_apk "$want")"
else
  build_apk
  if [ "$UNIVERSAL" = "1" ]; then
    APK="$APK_DIR/app-release.apk"
  else
    suffix="release"; [ "$DEBUG_BUILD" = "1" ] && suffix="debug"
    case "${ABI_FILTER:-}" in
      arm64)  APK="$APK_DIR/app-arm64-v8a-$suffix.apk" ;;
      v7a)    APK="$APK_DIR/app-armeabi-v7a-$suffix.apk" ;;
      x86_64) APK="$APK_DIR/app-x86_64-$suffix.apk" ;;
      "")     APK="" ;;   # 三个都产出了，下面统一列出
    esac
  fi
fi

# ---------------------------------------------------------------- 结果
log "产物目录：$APK_DIR"
if [ "$MODE" = "build" ] && [ -z "$APK" ]; then
  ls -lh "$APK_DIR"/*.apk 2>/dev/null | awk '{printf "   %s  %s\n", $5, $9}'
else
  [ -f "$APK" ] || die "没有找到产物：$APK"
  ls -lh "$APK" | awk '{printf "   %s  %s\n", $5, $9}'
fi

cat >&2 <<EOF

自己安装（任选其一）：
  adb install -r ${APK:-$APK_DIR/app-arm64-v8a-release.apk}
  # 或把 apk 传到手机后点击安装（需允许「未知来源」）

包名：com.gitee.ynzj.juyuwanggeiwo（可与官方 LocalSend 共存）
EOF

if [ "$DO_INSTALL" = "1" ]; then
  [ -n "$APK" ] || die "--install 需要配合 --abi 使用（或改用 --universal / --from-release）"
  ADB="$(find_adb)"
  SERIAL="$(pick_device "$ADB")"
  log "安装到 $SERIAL：$(basename "$APK")"
  "$ADB" -s "$SERIAL" install -r -d "$APK"
  "$ADB" -s "$SERIAL" shell dumpsys package com.gitee.ynzj.juyuwanggeiwo 2>/dev/null | grep -E "versionName|versionCode" | head -2 >&2 || true
fi
