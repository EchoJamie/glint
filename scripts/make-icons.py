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
import sys

SIZE = 20.0      # PDF 页面边长（pt）
CENTER = SIZE / 2
OUTER = 8.0      # 星芒尖端到中心的距离
K = 0.2          # 凹度：控制点离中心的距离比例。越小越尖。


def star_path():
    """四角星（闪光）路径。

    每个象限从一条尖芒弯向相邻尖芒，控制点拉向中心形成凹边。
    曲线 C1/C2 分别取中心到起点、终点方向上的 k 倍处。
    """
    tips = [
        (CENTER, CENTER + OUTER),   # 上
        (CENTER + OUTER, CENTER),   # 右
        (CENTER, CENTER - OUTER),   # 下
        (CENTER - OUTER, CENTER),   # 左
        (CENTER, CENTER + OUTER),   # 回到上
    ]

    def toward_center(tip):
        return (CENTER + (tip[0] - CENTER) * K, CENTER + (tip[1] - CENTER) * K)

    parts = ["%.2f %.2f m" % tips[0]]
    for i in range(4):
        start, end = tips[i], tips[i + 1]
        c1 = toward_center(start)
        c2 = toward_center(end)
        parts.append("%.2f %.2f %.2f %.2f %.2f %.2f c"
                     % (c1[0], c1[1], c2[0], c2[1], end[0], end[1]))
    parts.append("f")
    return "\n".join(parts)


def build_pdf():
    content = star_path().encode("ascii")

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.0f %.0f] "
        b"/Contents 4 0 R /Resources << >> >>" % (SIZE, SIZE),
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
    target = os.path.join(root, "resources", "glint.pdf")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    data = build_pdf()
    with open(target, "wb") as handle:
        handle.write(data)
    print("已生成 %s（%d 字节）" % (os.path.relpath(target, root), len(data)))


if __name__ == "__main__":
    sys.exit(main())
