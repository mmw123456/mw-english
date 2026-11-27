#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""为 820 词生成近义词，并做入库前过滤。

用法：
    DEEPSEEK_API_KEY=sk-xxx python _source/gen_synonyms.py

Key 只从环境变量读，不写进代码、不写进仓库、不写进日志。

输出：
    data/synonyms.json          —— 过滤后的结果（word -> [{w, dist}]）
    data/synonyms_preview.md    —— 人工核对用的预览表（按未命中/命中分组）

过滤规则（用户定）：
    1. 近义词必须在 43,350 词裁剪词库里存在
    2. 不能等于本词
    3. 同词内去重
    4. 每词最多保留 4 个
"""
import json
import os
import re
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "db", "dict.sqlite")
OUT_JSON = os.path.join(ROOT, "data", "synonyms.json")
OUT_MD = os.path.join(ROOT, "data", "synonyms_preview.md")

API = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-chat"
BATCH = 10
WORKERS = 6
MAX_SYN = 4

PROMPT = """你是英语词汇编辑，为中文母语的大学生整理近义词。

对下面每个单词，给出 2-4 个**单个英文单词**的近义词（不要词组、不要缩写、不要生僻到没人用的词），
并给一句不超过 25 字的中文辨析，说明它和原词的区别（搭配、语域、侧重）。

单词表（每行「单词 | 中文释义」）：
{words}

只输出 JSON，不要解释，格式：
{{"items":[{{"word":"原词","synonyms":[{{"w":"近义词","dist":"辨析"}}]}}]}}
必须覆盖输入的每一个单词；确实没有合适近义词的，synonyms 给空数组。"""


def load_words():
    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT word_key, word, meaning_pdf, meaning_ecdict FROM my_words ORDER BY no"
    ).fetchall()
    con.close()
    out = []
    for key, word, pdf, ec in rows:
        gloss = (pdf or "").replace("\n", " ").strip()
        if len(gloss) > 40:
            gloss = gloss[:40]
        out.append((key, word, gloss))
    return out


def call(payload_words, api_key, attempt=0):
    body = PROMPT.format(
        words="\n".join(f"{w} | {g}" for _, w, g in payload_words)
    )
    req = urllib.request.Request(
        API,
        data=json.dumps(
            {
                "model": MODEL,
                "messages": [{"role": "user", "content": body}],
                "temperature": 0.2,
                "response_format": {"type": "json_object"},
            }
        ).encode(),
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + api_key,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = json.loads(r.read().decode())
        text = data["choices"][0]["message"]["content"]
        return json.loads(text)
    except Exception as e:  # noqa: BLE001
        if attempt < 4:
            time.sleep(2 * (attempt + 1))
            return call(payload_words, api_key, attempt + 1)
        print(f"[warn] 批次失败（{payload_words[0][1]}…）：{e}", file=sys.stderr)
        return {"items": []}


def main():
    api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not api_key:
        print("缺少环境变量 DEEPSEEK_API_KEY", file=sys.stderr)
        return 1

    words = load_words()
    batches = [words[i:i + BATCH] for i in range(0, len(words), BATCH)]
    print(f"共 {len(words)} 词，{len(batches)} 批，{WORKERS} 并发")

    results = {}
    lock = threading.Lock()
    done = [0]

    def work(batch):
        data = call(batch, api_key)
        items = data.get("items") or []
        with lock:
            for it in items:
                w = str(it.get("word", "")).strip().lower()
                if not w:
                    continue
                syns = []
                for s in it.get("synonyms") or []:
                    sw = str(s.get("w", "")).strip().lower()
                    dist = str(s.get("dist", "")).strip()
                    if not sw or not dist:
                        continue
                    syns.append({"w": sw, "dist": dist})
                results[w] = syns
            done[0] += 1
            if done[0] % 10 == 0:
                print(f"  已回 {done[0]}/{len(batches)} 批")

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        list(pool.map(work, batches))

    # ---- 过滤 ----
    con = sqlite3.connect(DB)
    dict_words = {r[0] for r in con.execute("SELECT word FROM words")}
    con.close()

    filtered = {}
    stats = {"raw": 0, "not_in_dict": 0, "self": 0, "dup": 0, "long": 0}
    for key, word, _ in words:
        raw = results.get(key) or results.get(word.lower()) or []
        keep, seen = [], set()
        for s in raw:
            stats["raw"] += 1
            sw = s["w"].lower()
            if sw == key:
                stats["self"] += 1
                continue
            if sw not in dict_words:
                stats["not_in_dict"] += 1
                continue
            if sw in seen:
                stats["dup"] += 1
                continue
            if len(s["dist"]) > 60:
                s["dist"] = s["dist"][:58] + "…"
            seen.add(sw)
            keep.append({"w": sw, "dist": s["dist"]})
            if len(keep) >= MAX_SYN:
                break
        if keep:
            filtered[key] = keep

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(filtered, f, ensure_ascii=False, indent=1)

    # ---- 预览表 ----
    empty = [w for k, w, _ in words if k not in filtered]
    lines = [
        "# 近义词预览（待核对）",
        "",
        f"- 源词：{len(words)}　有近义词：{len(filtered)}　无：{len(empty)}",
        f"- 生成条目 {stats['raw']} 条，过滤掉：不在词库 {stats['not_in_dict']} / "
        f"等于本词 {stats['self']} / 重复 {stats['dup']}",
        f"- 每词上限 {MAX_SYN} 个，近义词必须在 43,350 词裁剪词库内",
        "",
        "## 明细",
        "",
        "| # | 单词 | 近义词 | 辨析 |",
        "|---|---|---|---|",
    ]
    for i, (key, word, _) in enumerate(words, 1):
        syns = filtered.get(key)
        if not syns:
            lines.append(f"| {i} | {word} | — | （无）|")
            continue
        for j, s in enumerate(syns):
            lines.append(
                f"| {i if j == 0 else ''} | {word if j == 0 else ''} | {s['w']} | {s['dist']} |"
            )
    if empty:
        lines += ["", "## 无近义词的词", "", "、".join(empty)]
    lines.append("")
    with open(OUT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(
        f"完成：{len(filtered)}/{len(words)} 词有近义词，无近义词 {len(empty)} 词\n"
        f"过滤：不在词库 {stats['not_in_dict']} / 等于本词 {stats['self']} / 重复 {stats['dup']}\n"
        f"输出：{OUT_JSON}\n预览：{OUT_MD}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
