#!/usr/bin/env python3
"""生成「局域网给我」的占位图标（原创设计，替代上游 LocalSend 标识）。

设计：靛蓝→紫罗兰渐变圆角方块 + 白色双向箭头（上箭头带断点，呼应"断点续传"）。
与上游 LocalSend 的青色放射状标识在造型与配色上均无相似之处。

这是**占位图标**，发布前建议由设计师替换；替换后重跑本脚本即可覆盖全部平台资源。

用法：
    python3 support/scripts/generate_placeholder_icons.py            # 覆盖 app/ 下的全部图标
    python3 support/scripts/generate_placeholder_icons.py --check    # 只列出将要写入的文件

依赖：Pillow（pip install pillow）
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

from PIL import Image, ImageDraw

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

GRADIENT_TOP = (59, 91, 255)      # #3B5BFF
GRADIENT_BOTTOM = (122, 59, 255)  # #7A3BFF
BADGE_ERROR = (229, 72, 77)       # #E5484D
BADGE_SUCCESS = (47, 168, 79)     # #2FA84F

SUPERSAMPLE = 8


def _gradient(size: int) -> Image.Image:
    img = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        img.putpixel(
            (0, y),
            tuple(round(a + (b - a) * t) for a, b in zip(GRADIENT_TOP, GRADIENT_BOTTOM)),
        )
    return img.resize((size, size), Image.NEAREST)


def _rounded_mask(size: int, radius_ratio: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=max(1, int(size * radius_ratio)), fill=255
    )
    return mask


def _draw_glyph(d: ImageDraw.ImageDraw, size: int, color=(255, 255, 255, 255)) -> None:
    """双向箭头；上箭头带断点（"继续"语义）。坐标基于 0..1 归一化空间。"""
    s = size

    def rect(x0, y0, x1, y1):
        d.rounded_rectangle(
            (x0 * s, y0 * s, x1 * s, y1 * s), radius=max(1, int(0.035 * s)), fill=color
        )

    # 上箭头：两段轴 + 箭头（断点即两段之间的空隙）
    rect(0.20, 0.345, 0.42, 0.425)
    rect(0.48, 0.345, 0.60, 0.425)
    d.polygon(
        [(0.58 * s, 0.265 * s), (0.80 * s, 0.385 * s), (0.58 * s, 0.505 * s)], fill=color
    )

    # 下箭头（完整）
    rect(0.40, 0.575, 0.80, 0.655)
    d.polygon(
        [(0.42 * s, 0.495 * s), (0.20 * s, 0.615 * s), (0.42 * s, 0.735 * s)], fill=color
    )


def _draw_badge(d: ImageDraw.ImageDraw, size: int, kind: str) -> None:
    s = size
    color = BADGE_ERROR if kind == "error" else BADGE_SUCCESS
    r = 0.30 * s
    cx, cy = 0.74 * s, 0.74 * s
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color, outline=(255, 255, 255, 255), width=max(1, int(0.02 * s)))
    if kind == "success":
        d.line(
            [(cx - 0.13 * s, cy + 0.01 * s), (cx - 0.03 * s, cy + 0.12 * s), (cx + 0.15 * s, cy - 0.12 * s)],
            fill=(255, 255, 255, 255),
            width=max(2, int(0.045 * s)),
            joint="curve",
        )
    else:
        d.rounded_rectangle(
            (cx - 0.035 * s, cy - 0.16 * s, cx + 0.035 * s, cy + 0.045 * s),
            radius=max(1, int(0.035 * s)),
            fill=(255, 255, 255, 255),
        )
        d.ellipse(
            (cx - 0.042 * s, cy + 0.095 * s, cx + 0.042 * s, cy + 0.179 * s),
            fill=(255, 255, 255, 255),
        )


def render(size: int, variant: str = "app", badge: str | None = None) -> Image.Image:
    """variant: app（渐变圆角底+箭头）/ glyph（仅箭头，白）/ glyph-black（仅箭头，黑）"""
    if size < 32:
        ss = SUPERSAMPLE * 2
    else:
        ss = SUPERSAMPLE
    canvas = size * ss

    if variant in ("glyph", "glyph-black"):
        img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        color = (255, 255, 255, 255) if variant == "glyph" else (0, 0, 0, 255)
        _draw_glyph(ImageDraw.Draw(img), canvas, color)
        return img.resize((size, size), Image.LANCZOS)

    if variant == "glyph-inset":
        img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        inner = int(canvas * 0.62)
        glyph = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
        _draw_glyph(ImageDraw.Draw(glyph), inner, (255, 255, 255, 255))
        img.paste(glyph, ((canvas - inner) // 2, (canvas - inner) // 2), glyph)
        return img.resize((size, size), Image.LANCZOS)

    # app：渐变圆角底
    pad_ratio = 0.0
    img = _gradient(canvas).convert("RGBA")
    img.putalpha(_rounded_mask(canvas, 0.22))
    target = canvas
    if pad_ratio:
        target = int(canvas * (1 - 2 * pad_ratio))
        base = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        base.paste(img.resize((target, target), Image.LANCZOS), (pad_ratio * canvas, pad_ratio * canvas))
        img = base
    _draw_glyph(ImageDraw.Draw(img), canvas)
    if badge:
        _draw_badge(ImageDraw.Draw(img), canvas, badge)
    return img.resize((size, size), Image.LANCZOS)


def render_wide(w: int, h: int) -> Image.Image:
    """宽幅资源（Android TV banner、MSIX 宽磁贴/启动图、DMG 背景）：渐变 + 居中箭头。"""
    ss = 4 if max(w, h) < 200 else 2
    cw, ch = w * ss, h * ss
    img = Image.new("RGB", (1, ch))
    for y in range(ch):
        t = y / max(ch - 1, 1)
        img.putpixel(
            (0, y),
            tuple(round(a + (b - a) * t) for a, b in zip(GRADIENT_TOP, GRADIENT_BOTTOM)),
        )
    img = img.resize((cw, ch), Image.NEAREST).convert("RGBA")
    glyph_size = int(min(cw, ch) * 0.62)
    glyph = Image.new("RGBA", (glyph_size, glyph_size), (0, 0, 0, 0))
    _draw_glyph(ImageDraw.Draw(glyph), glyph_size, (255, 255, 255, 255))
    img.paste(glyph, ((cw - glyph_size) // 2, (ch - glyph_size) // 2), glyph)
    return img.resize((w, h), Image.LANCZOS)


def render_square_full_bleed(size: int, badge: str | None = None) -> Image.Image:
    """iOS 专用：不透明、无圆角（由系统遮罩）。"""
    ss = SUPERSAMPLE
    canvas = size * ss
    img = _gradient(canvas).convert("RGBA")
    _draw_glyph(ImageDraw.Draw(img), canvas)
    if badge:
        _draw_badge(ImageDraw.Draw(img), canvas, badge)
    return img.resize((size, size), Image.LANCZOS).convert("RGB")


def render_macos(size: int, badge: str | None = None) -> Image.Image:
    """macOS：留白 + 圆角（macOS 图标惯例）。"""
    ss = SUPERSAMPLE
    canvas = size * ss
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    inner = int(canvas * 0.82)
    icon = _gradient(inner).convert("RGBA")
    icon.putalpha(_rounded_mask(inner, 0.23))
    _draw_glyph(ImageDraw.Draw(icon), inner)
    if badge:
        _draw_badge(ImageDraw.Draw(icon), inner, badge)
    off = (canvas - inner) // 2
    img.paste(icon, (off, off), icon)
    return img.resize((size, size), Image.LANCZOS)


def variant_for(path: str) -> str:
    rel = os.path.relpath(path, REPO)
    name = os.path.basename(path).lower()
    if "statusbaritemicon" in rel.lower():
        return "glyph-black"
    if "monochrome" in name:
        return "glyph"
    if "foreground" in name or "quicktile" in name:
        return "glyph-inset"
    if "white" in name:
        return "glyph"
    if "black" in name:
        return "glyph-black"
    if "/ios/" in rel:
        return "ios-square"
    if "/macos/" in rel:
        return "macos"
    return "app"


def badge_for(path: str) -> str | None:
    low = path.lower()
    if "witherrormark" in low:
        return "error"
    if "withsuccessmark" in low:
        return "success"
    return None


def targets() -> list[str]:
    """只处理 git 已跟踪的图标文件，避免污染构建产物（build/、.gradle/ 等）。"""
    import subprocess

    try:
        out = subprocess.run(
            ["git", "-C", REPO, "ls-files"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.splitlines()
    except Exception:  # noqa: BLE001
        out = []
    files: list[str] = []
    for rel in out:
        n = os.path.basename(rel).lower()
        if not (rel.lower().endswith((".png", ".ico"))):
            continue
        # 注意：Android 的文件名是 ic_launcher_*（不含 "icon" 子串），必须单独匹配
        if not any(k in n for k in ("logo", "icon", "ic_launcher", "banner", "tile", "splash")):
            if not rel.endswith("support/build/dmg/background.png"):
                continue
            continue
        files.append(os.path.join(REPO, rel))
    return sorted(set(files))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="只列出将写入的文件")
    args = parser.parse_args()

    files = targets()
    if args.check:
        for p in files:
            print(os.path.relpath(p, REPO))
        print(f"共 {len(files)} 个文件")
        return 0

    for path in files:
        if path.lower().endswith(".ico"):
            sizes = [16, 24, 32, 48, 64, 128, 256]
            imgs = [render(s) for s in sizes]
            imgs[0].save(path, format="ICO", sizes=[(s, s) for s in sizes])
            print("icon ", os.path.relpath(path, REPO))
            continue

        try:
            with Image.open(path) as im:
                w, h = im.size
        except Exception as exc:  # noqa: BLE001
            print("skip ", os.path.relpath(path, REPO), exc, file=sys.stderr)
            continue
        if w <= 1 or h <= 1:
            continue

        variant = variant_for(path)
        badge = badge_for(path)
        size = max(w, h)
        if variant == "ios-square":
            img = render_square_full_bleed(size, badge)
        elif variant == "macos":
            img = render_macos(size, badge)
        else:
            img = render(size, variant, badge)
        if w != h:
            # 宽幅资源用「渐变底 + 居中箭头」，而不是留白居中（避免 TV banner / 宽磁贴发虚）
            img = render_wide(w, h)
        else:
            img = img.resize((w, h), Image.LANCZOS)
        img.save(path)
        print("image", os.path.relpath(path, REPO), f"{w}x{h}", variant, badge or "")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
