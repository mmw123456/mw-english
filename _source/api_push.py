#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
通过 GitHub REST API 推送当前 HEAD 的快照。

用途：本机网络到 github.com 主站不通（git push 失败），但 api.github.com 可达时，
用这个脚本把 HEAD 的完整文件树推到远端分支。会重建一个单 commit，不带本地历史。

用法：
    python api_push.py                          # 推到 origin 的 main
    python api_push.py --message "自定义说明"
    python api_push.py --branch dev

依赖：gh CLI 已登录（用于取 token），Python 3.8+，无第三方库。
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error

PROXY = os.environ.get("API_PUSH_PROXY") or os.environ.get("https_proxy") or os.environ.get("HTTPS_PROXY")


def run_git(*args, binary=False):
    out = subprocess.run(["git"] + list(args), capture_output=True, check=True)
    return out.stdout if binary else out.stdout.decode("utf-8", "replace")


def get_token():
    tok = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if tok:
        return tok.strip()
    return subprocess.run(["gh", "auth", "token"], capture_output=True, check=True).stdout.decode().strip()


def parse_remote(url):
    """从 https://github.com/owner/repo(.git) 解析 owner/repo"""
    u = url.strip()
    if u.startswith("git@github.com:"):
        u = u[len("git@github.com:"):]
    elif "github.com/" in u:
        u = u.split("github.com/", 1)[1]
    return u.replace(".git", "").strip("/")


class Api:
    def __init__(self, token):
        self.token = token
        handlers = [urllib.request.ProxyHandler({"https": PROXY, "http": PROXY})] if PROXY else []
        self.opener = urllib.request.build_opener(*handlers)

    def call(self, method, path, payload=None, retries=4):
        url = "https://api.github.com" + path
        data = json.dumps(payload).encode() if payload is not None else None
        for attempt in range(retries):
            req = urllib.request.Request(url, data=data, method=method)
            req.add_header("Authorization", "Bearer " + self.token)
            req.add_header("Accept", "application/vnd.github+json")
            req.add_header("X-GitHub-Api-Version", "2022-11-28")
            req.add_header("User-Agent", "api-push-script")
            if data:
                req.add_header("Content-Type", "application/json")
            try:
                with self.opener.open(req, timeout=90) as r:
                    body = r.read()
                    return json.loads(body) if body else {}
            except urllib.error.HTTPError as e:
                detail = e.read().decode("utf-8", "replace")[:400]
                # 5xx / 429 重试，4xx 直接失败
                if e.code >= 500 or e.code == 429:
                    if attempt == retries - 1:
                        raise RuntimeError(f"{method} {path} -> {e.code}: {detail}")
                    time.sleep(2 ** attempt)
                    continue
                raise RuntimeError(f"{method} {path} -> {e.code}: {detail}")
            except Exception as e:
                if attempt == retries - 1:
                    raise
                time.sleep(2 ** attempt)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--remote", default="origin")
    ap.add_argument("--branch", default=None)
    ap.add_argument("--message", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    remote_url = run_git("remote", "get-url", args.remote).strip()
    full = parse_remote(remote_url)
    owner, repo = full.split("/", 1)

    branch = args.branch or run_git("rev-parse", "--abbrev-ref", "HEAD").strip()
    message = args.message or run_git("log", "-1", "--pretty=%B").strip()
    head = run_git("rev-parse", "HEAD").strip()[:7]

    print(f"仓库   : {owner}/{repo}")
    print(f"分支   : {branch}")
    print(f"本地HEAD: {head}")

    # 列出 HEAD 全部文件（path \0 mode \0 sha \0 ...）
    raw = run_git("ls-tree", "-r", "-z", "HEAD", binary=True)
    entries = []
    for chunk in raw.split(b"\x00"):
        if not chunk.strip():
            continue
        meta, path = chunk.split(b"\t", 1)
        mode, otype, sha = meta.decode().split()
        entries.append((mode, otype, sha, path.decode("utf-8")))
    entries.sort(key=lambda e: e[3])
    print(f"文件数 : {len(entries)}")

    api = Api(get_token())

    # 0) 空仓库无法创建 blob，先用 Contents API 塞一个占位文件触发初始 commit
    try:
        api.call("GET", f"/repos/{owner}/{repo}/git/ref/heads/{branch}")
        print("远程   : 分支已存在")
    except RuntimeError as e:
        if "-> 404" not in str(e) and "-> 409" not in str(e):
            raise
        print("远程   : 空仓库，创建初始 commit")
        api.call("PUT", f"/repos/{owner}/{repo}/contents/.api-push-init", {
            "message": "chore: init",
            "content": base64.b64encode(b"init\n").decode("ascii"),
            "branch": branch,
        })

    # 1) 上传 blob
    tree_items = []
    total_bytes = 0
    for i, (mode, otype, sha, path) in enumerate(entries, 1):
        if otype != "blob":
            print(f"  跳过非 blob: {path} ({otype})")
            continue
        content = run_git("cat-file", "blob", sha, binary=True)
        total_bytes += len(content)
        if len(content) > 95 * 1024 * 1024:
            raise RuntimeError(f"文件超过 95MB，GitHub 拒绝：{path}")
        if args.dry_run:
            tree_items.append({"path": path, "mode": mode, "type": "blob", "sha": sha})
            continue
        blob = api.call("POST", f"/repos/{owner}/{repo}/git/blobs", {
            "content": base64.b64encode(content).decode("ascii"),
            "encoding": "base64",
        })
        tree_items.append({"path": path, "mode": mode, "type": "blob", "sha": blob["sha"]})
        print(f"  [{i}/{len(entries)}] {path}  {len(content):,} B")

    print(f"总字节 : {total_bytes:,} ({total_bytes/1024/1024:.1f} MB)")
    if args.dry_run:
        print("dry-run，未写入远程")
        return

    # 2) 建 tree
    tree = api.call("POST", f"/repos/{owner}/{repo}/git/trees", {
        "tree": tree_items,
    })
    print(f"tree   : {tree['sha']}")

    # 3) 建 commit（无 parents，作初始提交）
    commit = api.call("POST", f"/repos/{owner}/{repo}/git/commits", {
        "message": message,
        "tree": tree["sha"],
    })
    print(f"commit : {commit['sha']}")

    # 4) 更新或创建分支引用
    try:
        ref = api.call("GET", f"/repos/{owner}/{repo}/git/ref/heads/{branch}")
        api.call("PATCH", f"/repos/{owner}/{repo}/git/refs/heads/{branch}", {
            "sha": commit["sha"], "force": True,
        })
        print(f"分支   : 已更新 {branch}")
    except RuntimeError as e:
        if "-> 404" not in str(e):
            raise
        api.call("POST", f"/repos/{owner}/{repo}/git/refs", {
            "ref": f"refs/heads/{branch}", "sha": commit["sha"],
        })
        print(f"分支   : 已创建 {branch}")

    print(f"\n完成 -> https://github.com/{owner}/{repo}/tree/{branch}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n失败: {e}", file=sys.stderr)
        sys.exit(1)
