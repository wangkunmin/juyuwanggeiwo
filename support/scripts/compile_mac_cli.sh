#!/usr/bin/env bash
# 打包 macOS CLI（本仓库版本）。
# 可选：SIGN_ID（Developer ID 证书名）与 DEV_EMAIL/APP_PASSWORD/TEAM_ID（公证）；
# 未设置时产出未签名二进制，本机自用足够。
set -euo pipefail

VERSION=$(sed -n 's/^version: \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' app/pubspec.yaml)
# 归档名用本仓库标识；二进制本身沿用 crate 的 bin 名 localsend-cli（协议/CLI 标识有意保留）
ARM_NAME="juyuwanggeiwo-CLI-$VERSION-macos-arm-64"
X64_NAME="juyuwanggeiwo-CLI-$VERSION-macos-x86-64"

rustup target add aarch64-apple-darwin x86_64-apple-darwin

echo
echo "Compiling the CLI..."
echo
cargo build --release --package localsend-cli --target aarch64-apple-darwin
cargo build --release --package localsend-cli --target x86_64-apple-darwin

# stage per-arch directories so the archived binary keeps its plain name
rm -rf "$ARM_NAME" "$X64_NAME" "$ARM_NAME.zip" "$X64_NAME.zip" "$ARM_NAME.tar.gz" "$X64_NAME.tar.gz"
mkdir "$ARM_NAME" "$X64_NAME"
cp target/aarch64-apple-darwin/release/localsend-cli "$ARM_NAME/localsend-cli"
cp target/x86_64-apple-darwin/release/localsend-cli "$X64_NAME/localsend-cli"

# sign the binaries（未设置 SIGN_ID 时跳过）
echo
if [ -n "${SIGN_ID:-}" ]; then
  echo "Signing the CLI with: $SIGN_ID"
  echo
  codesign --force --verbose --options runtime --sign "$SIGN_ID" "$ARM_NAME/localsend-cli"
  codesign --force --verbose --options runtime --sign "$SIGN_ID" "$X64_NAME/localsend-cli"
else
  echo "SIGN_ID 未设置：跳过签名（产出未签名二进制，仅本机自用）"
fi

# send to apple for notarization (the zip is only the submission transport)
if [ -n "${DEV_EMAIL:-}" ] && [ -n "${APP_PASSWORD:-}" ] && [ -n "${TEAM_ID:-}" ]; then
  echo
  echo "Sending to apple for notarization..."
  echo
  zip -j "$ARM_NAME.zip" "$ARM_NAME/localsend-cli"
  zip -j "$X64_NAME.zip" "$X64_NAME/localsend-cli"
  xcrun notarytool submit "$ARM_NAME.zip" --wait --apple-id "$DEV_EMAIL" --password "$APP_PASSWORD" --team-id "$TEAM_ID"
  xcrun notarytool submit "$X64_NAME.zip" --wait --apple-id "$DEV_EMAIL" --password "$APP_PASSWORD" --team-id "$TEAM_ID"
  # bare binaries cannot be stapled; Gatekeeper fetches the ticket online
  rm -f "$ARM_NAME.zip" "$X64_NAME.zip"
else
  echo
  echo "未提供公证凭据（DEV_EMAIL / APP_PASSWORD / TEAM_ID）：跳过公证"
fi

# distribution tarballs; tar preserves the executable bit
echo
echo "Creating tar.gz archives..."
echo
tar -czvf "$ARM_NAME.tar.gz" -C "$ARM_NAME" localsend-cli
tar -czvf "$X64_NAME.tar.gz" -C "$X64_NAME" localsend-cli
rm -rf "$ARM_NAME" "$X64_NAME"
