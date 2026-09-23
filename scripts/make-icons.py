#!/usr/bin/env python3
#
# 生成输入源菜单图标（矢量 PDF）。
#
# macOS 输入源菜单要求小尺寸仍可辨认，因此用 PDF 矢量而不是位图——
# 这与鼠须管用 rime.pdf 的做法一致（decisions.md 5.4）。
#
# 意象是「一道流光」，与 Glint（一闪而过的光）对应。
#
# **这是 M0 占位版本**，正式图标在 M1 前交付。app 图标走 Asset Catalog，
# 与本脚本无关。
#
# 直接手写 PDF，不依赖任何图形库——构建环境不该为一张占位图多出依赖。
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

import os
import shutil
import subprocess
import sys
import tempfile

SIZE = 20.0      # PDF 页面边长（pt）
CENTER = SIZE / 2
OUTER = 8.0      # 星芒尖端到中心的距离
K = 0.2          # 凹度：控制点离中心的距离比例。越小越尖。


def star_path(center=(CENTER, CENTER), outer=OUTER, k=K):
    """四角星（闪光）路径。

    每个象限从一条尖芒弯向相邻尖芒，控制点拉向中心形成凹边。
    曲线 C1/C2 分别取中心到起点、终点方向上的 k 倍处。
    """
    cx, cy = center
    tips = [
        (cx, cy + outer),   # 上
        (cx + outer, cy),   # 右
        (cx, cy - outer),   # 下
        (cx - outer, cy),   # 左
        (cx, cy + outer),   # 回到上
    ]

    def toward_center(tip):
        return (cx + (tip[0] - cx) * k, cy + (tip[1] - cy) * k)

    parts = ["%.2f %.2f m" % tips[0]]
    for i in range(4):
        start, end = tips[i], tips[i + 1]
        c1 = toward_center(start)
        c2 = toward_center(end)
        parts.append("%.2f %.2f %.2f %.2f %.2f %.2f c"
                     % (c1[0], c1[1], c2[0], c2[1], end[0], end[1]))
    parts.append("f")
    return "\n".join(parts)


# 圆角矩形（app 图标底板）。k 为贝塞尔控制点偏移，≈0.5523*r 得到近似的圆角。
def rounded_rect_path(x, y, w, h, r):
    c = r * 0.5523
    p = []
    p.append("%.2f %.2f m" % (x + r, y))
    p.append("%.2f %.2f l" % (x + w - r, y))
    p.append("%.2f %.2f %.2f %.2f %.2f %.2f c" % (x + w - r + c, y, x + w, y + r - c, x + w, y + r))
    p.append("%.2f %.2f l" % (x + w, y + h - r))
    p.append("%.2f %.2f %.2f %.2f %.2f %.2f c" % (x + w, y + h - r + c, x + w - r + c, y + h, x + w - r, y + h))
    p.append("%.2f %.2f l" % (x + r, y + h))
    p.append("%.2f %.2f %.2f %.2f %.2f %.2f c" % (x + r - c, y + h, x, y + h - r + c, x, y + h - r))
    p.append("%.2f %.2f l" % (x, y + r))
    p.append("%.2f %.2f %.2f %.2f %.2f %.2f c" % (x, y + r - c, x + r - c, y, x + r, y))
    p.append("f")
    return "\n".join(p)


def app_icon_content(size=1024.0):
    """App 图标：深蓝底 + 白色四角星。

    macOS app 图标需要自带底板（系统不再自动加圆角遮罩之外的背景），
    所以不能直接复用输入源那枚纯黑的透明图标。
    """
    margin = size * 0.08
    board = rounded_rect_path(margin, margin, size - 2 * margin, size - 2 * margin,
                              (size - 2 * margin) * 0.225)
    # 深蓝底。选深色是为了让白色星芒在小尺寸下也保持对比。
    background = "0.10 0.16 0.30 rg\n" + board
    star = ("1 1 1 rg\n"
            + star_path(center=(size / 2, size / 2), outer=size * 0.32, k=0.22))
    return background + "\n" + star + "\n"


def build_pdf(content_text, size=SIZE):
    content = content_text.encode("ascii")

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] "
        b"/Contents 4 0 R /Resources << >> >>" % (size, size),
        b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream",
    ]

    # 逐对象记录偏移，末尾写 xref——手写 PDF 最容易错的就是这里。
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"

    xref_at = len(out)
    out += b"xref\n0 %d\n" % (len(objects) + 1)
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += (b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n"
            % (len(objects) + 1, xref_at))
    return bytes(out)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "resources")
    os.makedirs(out, exist_ok=True)

    # 输入源菜单图标：透明底、黑色星芒（系统会按明暗自动着色），小尺寸用。
    menu = os.path.join(out, "glint.pdf")
    with open(menu, "wb") as handle:
        handle.write(build_pdf(star_path()))
    print("已生成 %s" % os.path.relpath(menu, root))

    # app 图标：带底板的方图，再交给 sips + iconutil 转成 .icns。
    app_pdf = os.path.join(out, "glint-appicon.pdf")
    with open(app_pdf, "wb") as handle:
        handle.write(build_pdf(app_icon_content(), size=1024.0))
    print("已生成 %s" % os.path.relpath(app_pdf, root))

    icns = make_icns(app_pdf, out)
    if icns:
        print("已生成 %s" % os.path.relpath(icns, root))


def make_icns(pdf_path, out_dir):
    """PDF → 各尺寸 PNG → .icns。

    用系统的 sips 与 iconutil，不引入图形库依赖；两者都随 macOS 提供。
    """
    iconset = os.path.join(tempfile.mkdtemp(), "Glint.iconset")
    os.makedirs(iconset, exist_ok=True)

    # iconutil 要求的文件名与尺寸组合。
    specs = [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]
    try:
        for pixels, name in specs:
            subprocess.run(
                ["sips", "-s", "format", "png",
                 "--resampleHeightWidth", str(pixels), str(pixels),
                 pdf_path, "--out", os.path.join(iconset, name)],
                check=True, capture_output=True)
        target = os.path.join(out_dir, "GlintIcon.icns")
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", target],
                       check=True, capture_output=True)
        return target
    except (subprocess.CalledProcessError, FileNotFoundError) as error:
        print("⚠️  生成 .icns 失败（%s）；Finder 会显示通用图标" % error, file=sys.stderr)
        return None
    finally:
        shutil.rmtree(os.path.dirname(iconset), ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
