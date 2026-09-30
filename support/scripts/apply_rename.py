#!/usr/bin/env python3
"""把上游 LocalSend 的项目标识替换为「局域网给我 / juyuwanggeiwo」。

一次性脚本（执行后可删除）：严格排除协议路径 /api/localsend/v2/...、PROTOCOL_VERSION、
上游版权与许可证文件、上游 issue/仓库 URL 引用。
"""
from __future__ import annotations

import os
import re
import sys

REPO = "/Users/wangkm/workspace/gitee/localsend"
APP_ID = "com.gitee.ynzj.juyuwanggeiwo"
APP_ID_OLD = "org.localsend.localsend_app"
APP_ID_CAMEL_OLD = "org.localsend.localsendApp"
NAME_ZH = "局域网给我"
NAME_ASCII = "juyuwanggeiwo"
CHANNEL = f"{APP_ID}/channel"
CHANNEL_OLD = "org.localsend.localsend_app/localsend"

# (相对路径, 旧串, 新串)；路径支持通配
RULES: list[tuple[str, str, str]] = [
    # ---------------- Android ----------------
    ("app/android/app/build.gradle", f'namespace "{APP_ID_OLD}"', f'namespace "{APP_ID}"'),
    ("app/android/app/build.gradle", f'applicationId "{APP_ID_OLD}"', f'applicationId "{APP_ID}"'),
    ("app/android/app/src/main/AndroidManifest.xml", f'package="{APP_ID_OLD}"', f'package="{APP_ID}"'),
    ("app/android/app/src/main/AndroidManifest.xml", 'android:label="LocalSend"', f'android:label="{NAME_ZH}"'),
    ("app/android/app/src/debug/AndroidManifest.xml", f'package="{APP_ID_OLD}"', f'package="{APP_ID}"'),
    ("app/android/app/src/debug/AndroidManifest.xml", 'android:label="LocalSend Debug"', f'android:label="{NAME_ZH} Debug"'),
    ("app/android/app/src/profile/AndroidManifest.xml", f'package="{APP_ID_OLD}"', f'package="{APP_ID}"'),
    ("app/android/app/src/main/res/values/ic_launcher_background.xml", "#FFFFFF", "#3B5BFF"),
    # ---------------- Dart 方法通道（必须与 Kotlin 成对改） ----------------
    ("app/lib/util/native/channel/android_channel.dart", CHANNEL_OLD, CHANNEL),
    ("packages/localsend_isolates/lib/util/android_channel.dart", CHANNEL_OLD, CHANNEL),
    # ---------------- iOS ----------------
    ("app/ios/Runner/Info.plist", "<string>LocalSend</string>", f"<string>{NAME_ZH}</string>"),
    ("app/ios/Runner/Info.plist", "<string>localsend_app</string>", f"<string>{NAME_ASCII}</string>"),
    ("app/ios/Runner/Runner.entitlements", "group.org.localsend.localsendApp", f"group.{APP_ID}"),
    ("app/ios/ShareExtension/ShareExtension.entitlements", "group.org.localsend.localsendApp", f"group.{APP_ID}"),
    ("app/ios/Runner.xcodeproj/project.pbxproj", APP_ID_CAMEL_OLD, APP_ID),
    # ---------------- macOS ----------------
    ("app/macos/Runner/Configs/AppInfo.xcconfig", "PRODUCT_NAME = LocalSend", f"PRODUCT_NAME = {NAME_ASCII}"),
    ("app/macos/Runner/Configs/AppInfo.xcconfig", f"PRODUCT_BUNDLE_IDENTIFIER = {APP_ID_CAMEL_OLD}", f"PRODUCT_BUNDLE_IDENTIFIER = {APP_ID}"),
    ("app/macos/Runner/Configs/AppInfo.xcconfig",
     "PRODUCT_COPYRIGHT = Copyright © 2022-2026 Tien Do Nam",
     f"PRODUCT_COPYRIGHT = Copyright © 2026 ynzj · 基于 LocalSend（Apache-2.0）"),
    ("app/macos/Runner/Info.plist", "<string>LocalSend</string>", f"<string>{NAME_ZH}</string>"),
    ("app/macos/Runner/Info.plist", "<string>Send to LocalSend</string>", f"<string>发送到{NAME_ZH}</string>"),
    ("app/macos/Runner/Base.lproj/MainMenu.xib", 'title="LocalSend"', f'title="{NAME_ZH}"'),
    ("app/macos/Runner/Base.lproj/MainMenu.xib", 'title="About LocalSend"', f'title="关于{NAME_ZH}"'),
    ("app/macos/Runner/Base.lproj/MainMenu.xib", 'title="Hide LocalSend"', f'title="隐藏{NAME_ZH}"'),
    ("app/macos/Runner/Base.lproj/MainMenu.xib", 'title="Quit LocalSend"', f'title="退出{NAME_ZH}"'),
    ("app/macos/Runner/AppDelegate.swift", "showLocalSendFromMenuBar", "showAppFromMenuBar"),
    ("app/macos/Runner/AppDelegate.swift", "localsendBrandColor", "brandColor"),
    ("app/macos/Runner/AppDelegate.swift",
     "NSColor(red: 0, green: 0.392, blue: 0.353, alpha: 0.8) // #00645a",
     "NSColor(red: 0.231, green: 0.357, blue: 1.0, alpha: 0.9) // #3B5BFF"),
    ("app/lib/util/native/macos_channel.dart", "'showLocalSendFromMenuBar'", "'showAppFromMenuBar'"),
    ("app/macos/Runner/Shared.swift", "localsend.shared_group", f"{NAME_ASCII}.shared_group"),
    ("app/macos/Runner/DebugProfile.entitlements", "localsend.shared_group", f"{NAME_ASCII}.shared_group"),
    ("app/macos/Runner/Release.entitlements", "localsend.shared_group", f"{NAME_ASCII}.shared_group"),
    ("app/macos/ShareExtension/ShareExtension.entitlements", "localsend.shared_group", f"{NAME_ASCII}.shared_group"),
    ("app/macos/Runner.xcodeproj/project.pbxproj", APP_ID_CAMEL_OLD, APP_ID),
    ("app/macos/ShareExtension/Info.plist", "<string>LocalSend</string>", f"<string>{NAME_ZH}</string>"),
    # ---------------- Linux ----------------
    ("app/linux/CMakeLists.txt", 'set(BINARY_NAME "localsend_app")', f'set(BINARY_NAME "{NAME_ASCII}")'),
    ("app/linux/CMakeLists.txt", f'set(APPLICATION_ID "{APP_ID_OLD}")', f'set(APPLICATION_ID "{APP_ID}")'),
    ("app/linux/my_application.cc", 'gtk_header_bar_set_title(header_bar, "LocalSend");', f'gtk_header_bar_set_title(header_bar, "{NAME_ZH}");'),
    ("app/linux/my_application.cc", 'gtk_window_set_title(window, "LocalSend");', f'gtk_window_set_title(window, "{NAME_ZH}");'),
    ("app/linux/packaging/deb/make_config.yaml", "display_name: LocalSend", f"display_name: {NAME_ZH}"),
    ("app/linux/packaging/deb/make_config.yaml", "package_name: localsend", f"package_name: {NAME_ASCII}"),
    ("app/linux/packaging/deb/make_config.yaml", "  name: Tienisto\n  email: dev.tien.donam@gmail.com",
     "  name: ynzj\n  email: 927070135@qq.com"),
    ("app/linux/packaging/deb/make_config.yaml", 'postinstall_scripts:\n  - echo "Installed Localsend successfully"',
     f'postinstall_scripts:\n  - echo "Installed {NAME_ASCII} successfully"'),
    ("app/linux/packaging/rpm/make_config.yaml", "display_name: LocalSend", f"display_name: {NAME_ZH}"),
    ("app/linux/packaging/rpm/make_config.yaml", "packager: Tienisto", "packager: ynzj"),
    ("app/linux/packaging/rpm/make_config.yaml", "packagerEmail: dev.tien.donam@gmail.com", "packagerEmail: 927070135@qq.com"),
    ("app/linux/packaging/rpm/make_config.yaml", "url: https://localsend.org", f"url: https://gitee.com/ynzj/{NAME_ASCII}"),
    ("app/linux/packaging/rpm/make_config.yaml", "license: MIT", "license: Apache-2.0"),
    ("app/linux/packaging/rpm/make_config.yaml", "summary: Share files easily with LocalSend",
     "summary: 局域网传输 · 跨平台互传 · 断点续传（基于 LocalSend 协议二次开发）"),
    # ---------------- Windows ----------------
    ("app/windows/CMakeLists.txt", "project(localsend_app LANGUAGES CXX)", f"project({NAME_ASCII} LANGUAGES CXX)"),
    ("app/windows/CMakeLists.txt", 'set(BINARY_NAME "localsend_app")', f'set(BINARY_NAME "{NAME_ASCII}")'),
    ("app/windows/CMakeLists.txt", '"localsend_msix_helper.msix"', f'"{NAME_ASCII}_msix_helper.msix"'),
    ("app/windows/runner/main.cpp", 'window.Create(L"LocalSend", origin, size)',
     'window.Create(L"\\u5c40\\u57df\\u7f51\\u7ed9\\u6211", origin, size)'),
    ("app/windows/runner/Runner.rc", 'VALUE "FileDescription", "LocalSend" "\\0"', f'VALUE "FileDescription", "{NAME_ZH}" "\\0"'),
    ("app/windows/runner/Runner.rc", 'VALUE "InternalName", "localsend_app" "\\0"', f'VALUE "InternalName", "{NAME_ASCII}" "\\0"'),
    ("app/windows/runner/Runner.rc", 'VALUE "OriginalFilename", "localsend_app.exe" "\\0"', f'VALUE "OriginalFilename", "{NAME_ASCII}.exe" "\\0"'),
    ("app/windows/runner/Runner.rc", 'VALUE "ProductName", "LocalSend" "\\0"', f'VALUE "ProductName", "{NAME_ASCII}" "\\0"'),
    ("app/windows/install_msix_helper.ps1", "localsend_msix_helper.msix", f"{NAME_ASCII}_msix_helper.msix"),
    ("app/windows/.gitignore", "localsend_msix_helper.msix", f"{NAME_ASCII}_msix_helper.msix"),
    # ---------------- Web ----------------
    ("app/web/index.html", 'content="localsend_app"', f'content="{NAME_ZH}"'),
    ("app/web/index.html", "<title>localsend_app</title>", f"<title>{NAME_ZH}</title>"),
    ("app/web/manifest.json", '"name": "localsend_app"', f'"name": "{NAME_ZH}"'),
    ("app/web/manifest.json", '"short_name": "localsend_app"', f'"short_name": "{NAME_ASCII}"'),
    # ---------------- Dart 应用层 ----------------
    ("app/lib/widget/local_send_logo.dart", "'LocalSend'", f"'{NAME_ZH}'"),
    ("app/lib/pages/home_page.dart", "'LocalSend'", f"'{NAME_ZH}'"),
    ("app/lib/util/native/context_menu_helper.dart", "const _windowsFileName = 'LocalSend';", f"const _windowsFileName = '{NAME_ASCII}';"),
    ("app/lib/util/native/autostart_helper.dart", "const _windowsRegistryKeyValue = 'LocalSend';", f"const _windowsRegistryKeyValue = '{NAME_ASCII}';"),
    ("app/lib/config/init_error.dart", "'LocalSend ${info.version} (${info.buildNumber})", f"'{NAME_ZH} ${{info.version}} (${{info.buildNumber}})"),
    ("app/lib/config/init_error.dart", "title: 'LocalSend: Error'", f"title: '{NAME_ZH}：错误'"),
    ("app/lib/provider/persistence_provider.dart", r"'$appData\\LocalSend\\settings.json'", r"'$appData\\" + NAME_ASCII + r"\\settings.json'"),
    ("app/lib/pages/troubleshoot_page.dart", 'name="LocalSend"', f'name="{NAME_ASCII}"'),
    ("app/pubspec.yaml", "description: An open source cross-platform alternative to AirDrop",
     "description: 局域网传输 · 跨平台互传 · 断点续传（基于 LocalSend 协议二次开发）"),
    # ---------------- CLI ----------------
    ("cli/src/banner.rs", '"  LocalSend CLI"', f'"  {NAME_ZH} CLI"'),
    ("cli/src/storage/paired.rs", "Was it written by a newer LocalSend CLI?", f"Was it written by a newer {NAME_ASCII} CLI?"),
    ("cli/Cargo.toml", 'description = "LocalSend CLI"', f'description = "{NAME_ASCII} CLI"'),
]


def main() -> int:
    missing: list[str] = []
    changed = 0
    for path, old, new in RULES:
        full = os.path.join(REPO, path)
        if not os.path.exists(full):
            missing.append(f"{path} (文件不存在)")
            continue
        with open(full, encoding="utf-8") as fh:
            content = fh.read()
        if old not in content:
            missing.append(f"{path} :: 未找到 {old[:60]!r}")
            continue
        content = content.replace(old, new)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(content)
        changed += 1

    # Kotlin 包名 + 通道
    kt_dir = os.path.join(REPO, "app/android/app/src/main/kotlin/org/localsend/localsend_app")
    if os.path.isdir(kt_dir):
        for name in os.listdir(kt_dir):
            if not name.endswith(".kt"):
                continue
            full = os.path.join(kt_dir, name)
            with open(full, encoding="utf-8") as fh:
                c = fh.read()
            c = c.replace("package org.localsend.localsend_app", f"package {APP_ID}")
            c = c.replace(f'CHANNEL = "{CHANNEL_OLD}"', f'CHANNEL = "{CHANNEL}"')
            with open(full, "w", encoding="utf-8") as fh:
                fh.write(c)
            changed += 1

    # i18n：所有语言包的 appName
    i18n_dir = os.path.join(REPO, "app/assets/i18n")
    locale_hits = 0
    for name in sorted(os.listdir(i18n_dir)):
        if not name.endswith(".json") or name.startswith("_missing"):
            continue
        full = os.path.join(i18n_dir, name)
        with open(full, encoding="utf-8") as fh:
            c = fh.read()
        if '"appName": "LocalSend"' not in c:
            continue
        c = c.replace('"appName": "LocalSend"', f'"appName": "{NAME_ZH}"')
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(c)
        locale_hits += 1
    changed += locale_hits

    print(f"完成 {changed} 处文件/条目替换；i18n appName 命中 {locale_hits} 个语言包")
    if missing:
        print("以下条目未命中（需人工确认）：")
        for m in missing:
            print("  -", m)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
