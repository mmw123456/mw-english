#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""给「近义词不足 2 个」和「没有近义词」的词补一次生成。

gen_synonyms.py 已跑完 820 词，其中 12 个只剩 1 个、4 个为空——都是因为
候选词不在 43,350 裁剪词库里被过滤掉了。这次只针对这些词，明确要求给
「常见度高的」近义词，给 4 个候选，好让过滤后还能剩下 2-4 个。

用法：
    DEEPSEEK_API_KEY=sk-xxx python _source/topup_synonyms.py

Key 只从环境变量读，不写进代码、不写进仓库、不写进日志。
"""
import json
import os
import sqlite3
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "db", "dict.sqlite")
SYN_JSON = os.path.join(ROOT, "data", "synonyms.json")
OUT_MD = os.path.join(ROOT, "data", "synonyms_preview.md")

API = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-chat"
BATCH = 8
MAX_SYN = 4

PROMPT = """你是英语词汇编辑。下面这些单词的近义词，之前的候选里有相当一部分是生僻词，不能用。

请为每个单词给出 4 个**最常用的**单个英文单词作近义词（必须是四六级/考研常见词，
不要词组、不要生僻词、不要词形变化），每个配一句不超过 25 字的中文辨析。

单词表（每行「单词 | 中文释义」）：
{words}

只输出 JSON，不要解释，格式：
{{"items":[{{"word":"原词","synonyms":[{{"w":"近义词","dist":"辨析"}}]}}]}}
必须覆盖输入的每一个单词。"""


def load_targets():
    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT word_key, word, meaning_pdf FROM my_words ORDER BY no"
    ).fetchall()
    con.close()
    existing = json.load(open(SYN_JSON, encoding="utf-8")) if os.path.exists(SYN_JSON) else {}
    targets = []
    for key, word, pdf in rows:
        got = existing.get(key) or []
        if len(got) >= 2:
            continue
        gloss = (pdf or "").replace("\n", " ").strip()
        targets.append((key, word, gloss[:40], got))
    return existing, targets


def call(batch, api_key, attempt=0):
    body = PROMPT.format(words="\n".join(f"{w} | {g}" for _, w, g, _ in batch))
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
        return json.loads(data["choices"][0]["message"]["content"])
    except Exception as e:  # noqa: BLE001
        if attempt < 4:
            time.sleep(2 * (attempt + 1))
            return call(batch, api_key, attempt + 1)
        print(f"[warn] 批次失败：{e}", file=sys.stderr)
        return {"items": []}


def main():
    api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not api_key:
        print("缺少环境变量 DEEPSEEK_API_KEY", file=sys.stderr)
        return 1

    existing, targets = load_targets()
    print(f"需要补的词：{len(targets)} 个 —— " + "、".join(w for _, w, _, _ in targets))
    if not targets:
        return 0

    con = sqlite3.connect(DB)
    dict_words = {r[0] for r in con.execute("SELECT word FROM words")}
    con.close()

    batches = [targets[i:i + BATCH] for i in range(0, len(targets), BATCH)]
    added = 0
    for idx, batch in enumerate(batches, 1):
        data = call(batch, api_key)
        got = {
            str(it.get("word", "")).strip().lower(): it.get("synonyms") or []
            for it in (data.get("items") or [])
        }
        for key, word, _, old in batch:
            merged = list(old)
            seen = {s["w"] for s in old}
            for s in got.get(key) or got.get(word.lower()) or []:
                sw = str(s.get("w", "")).strip().lower()
                dist = str(s.get("dist", "")).strip()
                if not sw or not dist or sw == key or sw in seen:
                    continue
                if sw not in dict_words:
                    continue
                merged.append({"w": sw, "dist": dist[:58]})
                seen.add(sw)
                if len(merged) >= MAX_SYN:
                    break
            if merged:
                existing[key] = merged
                added += 1
        print(f"  批次 {idx}/{len(batches)} 完成")
        time.sleep(0.6)

    with open(SYN_JSON, "w", encoding="utf-8") as f:
        json.dump(existing, f, ensure_ascii=False, indent=1)

    # 重出预览表
    con = sqlite3.connect(DB)
    words = con.execute("SELECT word_key, word FROM my_words ORDER BY no").fetchall()
    con.close()
    empty = [w for k, w in words if not existing.get(k)]
    thin = [w for k, w in words if 0 < len(existing.get(k) or []) < 2]
    lines = [
        "# 近义词预览（待核对）",
        "",
        f"- 源词：{len(words)}　有近义词：{len(existing)}　无：{len(empty)}　不足 2 个：{len(thin)}",
        f"- 每词上限 {MAX_SYN} 个，近义词必须在 43,350 词裁剪词库内",
        f"- 总条目：{sum(len(v) for v in existing.values())}",
        "",
        "## 明细",
        "",
        "| # | 单词 | 近义词 | 辨析 |",
        "|---|---|---|---|",
    ]
    for i, (key, word) in enumerate(words, 1):
        syns = existing.get(key)
        if not syns:
            lines.append(f"| {i} | {word} | — | （无）|")
            continue
        for j, s in enumerate(syns):
            lines.append(
                f"| {i if j == 0 else ''} | {word if j == 0 else ''} | {s['w']} | {s['dist']} |"
            )
    if empty:
        lines += ["", "## 无近义词的词（区块不显示）", "", "、".join(empty)]
    if thin:
        lines += ["", "## 只有 1 个近义词的词", "", "、".join(thin)]
    lines.append("")
    with open(OUT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"补齐 {added} 词；预览已更新：{OUT_MD}")
    print(f"仍为空：{len(empty)}　仍不足 2 个：{len(thin)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
