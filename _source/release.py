#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""建 GitHub Release 并上传 APK 附件。

本机到 github.com 主站不通，`gh release create` 会卡在上传；这里直接走 API
（api.github.com 可达），附件走 uploads.github.com。

用法：
    python _source/release.py --tag v0.4.0 --name "v0.4.0 词条详情整页" --notes-file notes.md
    python _source/release.py --tag v0.4.0 --skip-create   # 只补传附件

Token 取 `gh auth token`，或环境变量 GITHUB_TOKEN / GH_TOKEN。
"""
import argparse
import json
import mimetypes
import os
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "mmw123456/mw-english"
APK_DIR = os.path.join(ROOT, "app", "build", "app", "outputs", "flutter-apk")
APKS = [
    "app-arm64-v8a-release.apk",
    "app-armeabi-v7a-release.apk",
    "app-x86_64-release.apk",
]


def token():
    tok = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if tok:
        return tok.strip()
    return subprocess.run(["gh", "auth", "token"], capture_output=True, check=True).stdout.decode().strip()


def api(tok, method, url, payload=None, raw=None, content_type="application/json"):
    data = None
    if raw is not None:
        data = raw
    elif payload is not None:
        data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + tok)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            body = r.read().decode()
            return r.status, (json.loads(body) if body.strip() else {})
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:500]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--name", default=None)
    ap.add_argument("--notes-file", default=None)
    ap.add_argument("--skip-create", action="store_true")
    args = ap.parse_args()

    tok = token()
    base = f"https://api.github.com/repos/{REPO}/releases"

    release = None
    if not args.skip_create:
        notes = ""
        if args.notes_file and os.path.exists(args.notes_file):
            notes = open(args.notes_file, encoding="utf-8").read()
        status, body = api(tok, "POST", base, {
            "tag_name": args.tag,
            "target_commitish": "main",
            "name": args.name or args.tag,
            "body": notes,
            "draft": False,
            "prerelease": False,
        })
        print(f"建 release：HTTP {status}")
        if status not in (200, 201):
            print(body)
            if status != 422:
                return 1
        release = body if status in (200, 201) else None

    if release is None:
        status, releases = api(tok, "GET", base + "?per_page=20")
        for r in releases if isinstance(releases, list) else []:
            if r.get("tag_name") == args.tag:
                release = r
                break
    if not release:
        print("找不到 release")
        return 1

    upload_url = release["upload_url"].split("{")[0]
    existing = {a["name"] for a in release.get("assets", [])}

    for name in APKS:
        path = os.path.join(APK_DIR, name)
        if not os.path.exists(path):
            print(f"  跳过（文件不存在）：{name}")
            continue
        if name in existing:
            print(f"  已存在，跳过：{name}")
            continue
        size = os.path.getsize(path)
        ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"
        with open(path, "rb") as fh:
            raw = fh.read()
        status, body = api(
            tok, "POST", f"{upload_url}?name={name}", raw=raw, content_type=ctype
        )
        state = body.get("state") if isinstance(body, dict) else ""
        print(f"  上传 {name}（{size/1024/1024:.1f} MB）：HTTP {status} state={state}")
        if status not in (200, 201):
            print("   ", str(body)[:300])

    status, rel = api(tok, "GET", base + "/tags/" + args.tag)
    if status == 200:
        print(f"\n{rel['html_url']}")
        for a in rel.get("assets", []):
            print(f"  {a['name']}  {a['size']/1024/1024:.1f} MB  {a['state']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
