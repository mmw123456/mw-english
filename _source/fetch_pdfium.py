#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""拉取 pdfium 预编译二进制（v0.9.0 导入功能用）。

为什么不用 pub 上的包：pdfrx / pdfium_flutter 那条链要用 MSVC 编译一个 C 桥接
（`native_toolchain_c`），本机没有 Visual Studio，`flutter test` 根本跑不起来，
PDF 抽取就只能在真机上盲验。反过来直接调 pdfium 的 C API（`FPDFText_*`）不需要
任何编译器，Windows 上也能跑测试 —— 所以这里只取「.so / .dll + 版本号」。

来源：https://github.com/bblanchon/pdfium-binaries（pdfium 本体 BSD-3-Clause）
版本：chromium/8125（PDFium 158.0.8125.0），钉死，不跟随最新。

为什么要走 API 兜底：本机到 github.com 主站不通，`releases/download/...` 直链
拿不到；但 api.github.com 可达，用
    GET /repos/bblanchon/pdfium-binaries/releases/assets/{id}
    Accept: application/octet-stream
能拿到同样的字节（和 pdfium_dart 自己的兜底逻辑同一条路）。

产出：
- `app/android/app/src/main/jniLibs/<abi>/libpdfium.so` —— 打进 APK（进 git）
- `app/.pdfium/win-x64/pdfium.dll` —— 只给 `flutter test` 用（不进 git）
- 同目录 `PDFIUM.txt` 记版本与 sha256，便于复现与核对

用法：
    python _source/fetch_pdfium.py            # 缺什么补什么
    python _source/fetch_pdfium.py --force    # 全部重下
"""

import argparse
import hashlib
import io
import json
import os
import sys
import tarfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
JNI = os.path.join(APP, "android", "app", "src", "main", "jniLibs")
WIN_DIR = os.path.join(APP, ".pdfium", "win-x64")

RELEASE_TAG = "chromium/8125"          # URL 里的 tag（含斜杠，需编码）
RELEASE_VER = "158.0.8125.0"           # VERSION 文件里的 MAJOR.MINOR.BUILD.PATCH
REPO = "bblanchon/pdfium-binaries"

# ABI 目录名 → 资产文件名
ANDROID_ASSETS = {
    "arm64-v8a": "pdfium-android-arm64.tgz",
    "armeabi-v7a": "pdfium-android-arm.tgz",
    "x86_64": "pdfium-android-x64.tgz",
}
WIN_ASSET = "pdfium-win-x64.tgz"

TOKEN = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")


def _headers(accept="application/vnd.github+json"):
    h = {"Accept": accept, "X-GitHub-Api-Version": "2022-11-28",
         "User-Agent": "mw-english-fetch-pdfium"}
    if TOKEN:
        h["Authorization"] = "Bearer " + TOKEN
    return h


def _get(url, accept="application/vnd.github+json"):
    req = urllib.request.Request(url, headers=_headers(accept))
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def _release_assets():
    tag = RELEASE_TAG.replace("/", "%2F")
    raw = _get(f"https://api.github.com/repos/{REPO}/releases/tags/{tag}")
    data = json.loads(raw)
    return {a["name"]: a["id"] for a in data.get("assets", [])}


def download_asset(name, asset_id):
    url = f"https://api.github.com/repos/{REPO}/releases/assets/{asset_id}"
    raw = _get(url, accept="application/octet-stream")
    if raw[:2] != b"\x1f\x8b":
        raise SystemExit(f"{name} 下回来的不是 gzip（前两字节 {raw[:2]!r}），"
                         f"大概是代理返回了 JSON")
    return raw


def extract(raw, member_name):
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as tf:
        for m in tf.getmembers():
            if m.name == member_name:
                f = tf.extractfile(m)
                if f is None:
                    break
                return f.read()
    raise SystemExit(f"包里找不到 {member_name}")


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    assets = _release_assets()
    print(f"release {RELEASE_TAG}（PDFium {RELEASE_VER}）资产 {len(assets)} 个")

    lines = [f"pdfium {RELEASE_VER}", f"release {RELEASE_TAG}",
             f"source https://github.com/{REPO}", ""]
    changed = 0

    for abi, asset in ANDROID_ASSETS.items():
        dst_dir = os.path.join(JNI, abi)
        dst = os.path.join(dst_dir, "libpdfium.so")
        if os.path.exists(dst) and not args.force:
            print(f"  跳过（已存在）{abi}/libpdfium.so")
            lines.append(f"{abi}/libpdfium.so  {os.path.getsize(dst)}  "
                         f"{sha256(open(dst, 'rb').read())}")
            continue
        if asset not in assets:
            raise SystemExit(f"资产列表里没有 {asset}")
        raw = download_asset(asset, assets[asset])
        so = extract(raw, "lib/libpdfium.so")
        os.makedirs(dst_dir, exist_ok=True)
        with open(dst, "wb") as f:
            f.write(so)
        changed += 1
        print(f"  写入 {abi}/libpdfium.so  {len(so):,} 字节")
        lines.append(f"{abi}/libpdfium.so  {len(so)}  {sha256(so)}")

    # Windows 的 dll 只给 flutter test 用，不进 git
    win_dst = os.path.join(WIN_DIR, "pdfium.dll")
    if os.path.exists(win_dst) and not args.force:
        print("  跳过（已存在）win-x64/pdfium.dll")
    else:
        if WIN_ASSET not in assets:
            raise SystemExit(f"资产列表里没有 {WIN_ASSET}")
        raw = download_asset(WIN_ASSET, assets[WIN_ASSET])
        dll = extract(raw, "bin/pdfium.dll")
        os.makedirs(WIN_DIR, exist_ok=True)
        with open(win_dst, "wb") as f:
            f.write(dll)
        changed += 1
        print(f"  写入 win-x64/pdfium.dll  {len(dll):,} 字节（测试用，不进 git）")

    with open(os.path.join(JNI, "PDFIUM.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"\n完成，本次下载 {changed} 个文件")
    if changed == 0:
        print("全部已存在（要重下加 --force）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
