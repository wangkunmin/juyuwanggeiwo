#!/usr/bin/env bash
# 打包 macOS DMG（本仓库版本）。
#
# 前置：
#   - 已安装 Xcode 并选中：sudo xcode-select -s /Applications/Xcode.app
#   - brew install fvm create-dmg
#
# 可选环境变量（不设置则产出未签名包，本机自用足够；分发给他人会被 Gatekeeper 拦截）：
#   SIGN_ID="Developer ID Application: 你的名字 (TEAMID)"     # 应用与 DMG 签名
#   DEV_EMAIL / APP_PASSWORD / TEAM_ID                        # 公证（三者齐备才执行）
set -euo pipefail

VERSION=$(sed -n 's/^version: \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' app/pubspec.yaml)
# 与 app/macos/Runner/Configs/AppInfo.xcconfig 的 PRODUCT_NAME 保持一致
APP_NAME="juyuwanggeiwo"
DMG="juyuwanggeiwo-$VERSION.dmg"
APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"

cd app
fvm flutter clean
fvm flutter pub get
fvm flutter build macos

# sign the app（未设置 SIGN_ID 时跳过）
echo
if [ -n "${SIGN_ID:-}" ]; then
  echo "Signing the app with: $SIGN_ID"
  codesign --deep --force --verbose --options runtime --preserve-metadata=entitlements --sign "$SIGN_ID" "$APP_PATH"
else
  echo "SIGN_ID 未设置：跳过签名（产出未签名 App，仅本机自用）"
fi

# create dmg
# brew install create-dmg
echo
echo "Creating dmg..."
echo
rm -f "$DMG"
create-dmg \
  --volname "局域网给我" \
  --window-size 500 300 \
  --background "../support/build/dmg/background.png" \
  --icon "$APP_NAME.app" 130 110 \
  --app-drop-link 360 110 \
  "$DMG" \
  "$APP_PATH"

# sign the dmg
if [ -n "${SIGN_ID:-}" ]; then
  echo
  echo "Signing the dmg..."
  echo
  codesign --force --verbose --sign "$SIGN_ID" "$DMG"
fi

# send to apple for notarization（凭据齐备才执行）
if [ -n "${DEV_EMAIL:-}" ] && [ -n "${APP_PASSWORD:-}" ] && [ -n "${TEAM_ID:-}" ]; then
  echo
  echo "Sending to apple for notarization..."
  echo
  xcrun notarytool submit "$DMG" --wait --apple-id "$DEV_EMAIL" --password "$APP_PASSWORD" --team-id "$TEAM_ID"

  echo
  echo "Run stapler..."
  echo
  xcrun stapler staple "$DMG"
else
  echo
  echo "未提供公证凭据（DEV_EMAIL / APP_PASSWORD / TEAM_ID）：跳过公证"
fi
cd ..
