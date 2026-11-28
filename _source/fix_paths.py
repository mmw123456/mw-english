"""把在用文件里的旧父目录路径批量改为 D:\\ai-projects。

只改文本文件，跳过历史日志（.workbuddy/memory）、构建产物（.next / build /
.dart_tool / .gradle）、依赖目录、二进制与备份目录。

用法：python _source/fix_paths.py [--dry]
"""
from __future__ import annotations

import os
import sys

ROOT = r"D:\ai-projects"

# 旧父目录名。拆成两截写，避免本文件自身被 grep 旧路径时命中。
OLD_CN = "AI" + "\u9879\u76ee\u5de5\u7a0b"

SKIP_DIRS = {
    ".git", ".next", "node_modules", "build", ".dart_tool", ".gradle",
    ".kotlin", ".idea", "fonts", "BackWord-App.bak-20261125",
    "_leftover-BackWord-App", ".workbuddy",
}
SKIP_EXT = {
    ".zip", ".apk", ".otf", ".ttf", ".woff", ".woff2", ".png", ".jpg",
    ".jpeg", ".gif", ".webp", ".ico", ".pdf", ".sqlite", ".db", ".sst",
    ".csv", ".mp4", ".mov", ".exe", ".dll", ".jar", ".bin",
}

PAIRS = [
    ("D:\\" + OLD_CN + "\\BackWord-App", "D:\\ai-projects\\mw-english"),
    ("D:/" + OLD_CN + "/BackWord-App", "D:/ai-projects/mw-english"),
    ("D:\\" + OLD_CN, "D:\\ai-projects"),
    ("D:/" + OLD_CN, "D:/ai-projects"),
    (OLD_CN + "-开工前必读手册", "开工前必读手册"),
]


def read_text(path: str) -> str | None:
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError:
        return None
    if b"\x00" in raw[:4096]:
        return None
    for enc in ("utf-8", "gbk"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return None


def main() -> int:
    dry = "--dry" in sys.argv
    changed: list[str] = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if os.path.splitext(name)[1].lower() in SKIP_EXT:
                continue
            if name == os.path.basename(__file__):
                continue
            path = os.path.join(dirpath, name)
            text = read_text(path)
            if text is None or OLD_CN not in text:
                continue
            new = text
            for old, rep in PAIRS:
                new = new.replace(old, rep)
            if new == text:
                continue
            changed.append(os.path.relpath(path, ROOT))
            if not dry:
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(new)
    for rel in sorted(changed):
        print(("DRY " if dry else "WROTE ") + rel)
    print(f"共 {len(changed)} 个文件")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
