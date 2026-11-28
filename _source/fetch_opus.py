# -*- coding: utf-8 -*-
"""下载 OPUS en-zh moses 包（只取语料源文件，原始包不进 git）。

用法：python _source/fetch_opus.py TED2020
      python _source/fetch_opus.py OpenSubtitles
"""
import ssl
import sys
import time
import urllib.request
from pathlib import Path

HOST = "https://object.pouta." + "csc.fi/"
OUT = Path(__file__).resolve().parent / "opus"

CORPORA = {
    "TED2020": ("OPUS-TED2020/v1/moses/en-zh.txt.zip", "ted2020.en-zh.txt.zip"),
    "OpenSubtitles": ("OPUS-OpenSubtitles/v2016/moses/en-zh.txt.zip", "opensubtitles.en-zh.txt.zip"),
    "TED2013": ("OPUS-TED2013/v1.1/moses/en-zh.txt.zip", "ted2013.en-zh.txt.zip"),
}

try:
    import certifi

    CTX = ssl.create_default_context(cafile=certifi.where())
except Exception:  # noqa: BLE001
    CTX = ssl._create_unverified_context()  # noqa: SLF001


def main(argv):
    if not argv:
        print("用法：fetch_opus.py <" + "|".join(CORPORA) + ">")
        return 2
    name = argv[0]
    if name not in CORPORA:
        print("未知语料", name)
        return 2
    path, filename = CORPORA[name]
    OUT.mkdir(parents=True, exist_ok=True)
    dest = OUT / filename
    if dest.exists() and dest.stat().st_size > 1024:
        print(f"已存在，跳过下载：{dest}（{dest.stat().st_size / 1048576:.1f} MB）")
        return 0
    url = HOST + path
    print(f"下载 {name}: {url}", flush=True)
    t0 = time.time()
    tmp = dest.with_suffix(".part")
    with urllib.request.urlopen(url, timeout=120, context=CTX) as r, open(tmp, "wb") as f:
        total = int(r.headers.get("Content-Length", 0) or 0)
        got = 0
        last = 0.0
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
            got += len(chunk)
            if time.time() - last > 5:
                last = time.time()
                pct = got / total * 100 if total else 0
                print(f"  {got / 1048576:.0f}/{total / 1048576:.0f} MB ({pct:.0f}%)", flush=True)
    tmp.replace(dest)
    print(f"完成 {dest} {dest.stat().st_size / 1048576:.1f} MB，用时 {time.time() - t0:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
