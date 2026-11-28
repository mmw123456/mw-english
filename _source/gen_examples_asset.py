# -*- coding: utf-8 -*-
"""把校订后的例句打成 App 资源：app/assets/data/examples.json。

输入：_source/examples_820_curated.json
输出：app/assets/data/examples.json

每条句子的字段：
  en  英文原句
  hl  同一句，目标词两侧带 `**`（与文章正文同一套标记，UI 只按 `**` 切分）
  zh  中文译文（校订过）
  id  Tatoeba 英文句 id（署名/溯源用）

加粗规则：
  - 单词：词本身 + ECDICT exchange 里的变形（过去式/分词/三单/复数…），
    再加几条常见后缀兜底，取最长命中，全句命中几处标几处。
  - 短语：允许中间插入最多 2 个词（took full advantage of），整段加粗。
  - 一处都没命中就原样输出，并在末尾报告出来人工看。
"""
import csv
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CURATED = ROOT / "_source" / "examples_820_curated.json"
ECDICT = ROOT / "_source" / "ecdict.csv"
OUT = ROOT / "app" / "assets" / "data" / "examples.json"

MARK = "**"
SUFFIX_FALLBACK = ("s", "es", "ed", "d", "ing", "er", "est")
# 短语首词的不规则变形（只列短语里真实会用到的；不够再加）
IRREGULAR = {
    "take": ["took", "taken"],
    "make": ["made"],
    "give": ["gave", "given"],
    "get": ["got", "gotten"],
    "keep": ["kept"],
    "hold": ["held"],
    "bring": ["brought"],
}


def load_forms():
    """word -> 该词在 ECDICT 里登记的变形。"""
    forms = {}
    with open(ECDICT, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            w = row["word"].lower().strip()
            ex = row.get("exchange") or ""
            got = set()
            for part in ex.split("/"):
                if ":" not in part:
                    continue
                code, value = part.split(":", 1)
                value = value.strip().lower()
                if code in {"p", "d", "i", "3", "s", "r", "t"} and value:
                    got.add(value)
            if got:
                forms[w] = got
    return forms


def single_pattern(word, forms):
    cands = {word} | forms.get(word, set())
    # 兜底：去掉词尾 e / y 的常见变化（eliminate → eliminated 已在 exchange 里，
    # 但自加词/短语没有 exchange，仍要能用）
    for suf in SUFFIX_FALLBACK:
        cands.add(word + suf)
    if word.endswith("e"):
        for suf in ("ed", "ing", "es"):
            cands.add(word[:-1] + suf)
    if word.endswith("y"):
        cands.add(word[:-1] + "ies")
        cands.add(word[:-1] + "ied")
    cands = sorted((c for c in cands if c), key=len, reverse=True)
    return re.compile(
        r"\b(?:" + "|".join(re.escape(c) for c in cands) + r")\b", re.IGNORECASE
    )


def phrase_pattern(tokens):
    """第一个词允许变形，中间允许最多 2 个插入词。"""
    head = tokens[0]
    tail = tokens[1:]
    head_variants = [head, head + "s", head + "ed", head + "ing"] + IRREGULAR.get(head, [])
    if head.endswith("e"):
        head_variants += [head[:-1] + "ing", head[:-1] + "ed"]
    head_variants = sorted(set(head_variants), key=len, reverse=True)
    parts = [r"\b(?:" + "|".join(re.escape(h) for h in head_variants) + r")\b"]
    for i, tok in enumerate(tail):
        if i < len(tail) - 1:
            parts.append(r"(?:\s+\w+){0,2}?\s+\b" + re.escape(tok) + r"\b")
        else:
            parts.append(r"\s+\b" + re.escape(tok) + r"\b")
    return re.compile("".join(parts), re.IGNORECASE)


def mark(word, text, forms):
    word = word.lower().strip()
    tokens = word.split()
    pattern = single_pattern(word, forms) if len(tokens) == 1 else phrase_pattern(tokens)
    spans = [m.span() for m in pattern.finditer(text)]
    if not spans:
        return text, False
    # 从后往前插，避免偏移错位
    out = text
    for start, end in reversed(spans):
        out = out[:start] + MARK + out[start:end] + MARK + out[end:]
    return out, True


def main():
    data = json.loads(CURATED.read_text(encoding="utf-8"))
    forms = load_forms()
    words = data["examples"]
    misses = []
    out = {}
    total = 0
    for word, items in words.items():
        rows = []
        for s in items:
            total += 1
            hl, ok = mark(word, s["en"], forms)
            if not ok:
                misses.append((word, s["en"]))
            rows.append({"en": s["en"], "hl": hl, "zh": s["zh"], "id": s["en_id"]})
        out[word] = rows

    payload = {
        "source": "Tatoeba",
        "license": "CC-BY 2.0 FR",
        "url": "https://tatoeba.org",
        "note": "例句来自 Tatoeba，人工校订后入库",
        "words": out,
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    dist = Counter(len(v) for v in out.values())
    print(f"词数 {len(out)}；句数 {total}")
    print(f"分布 {dict(sorted(dist.items()))}")
    print(f"加粗命中失败 {len(misses)} 条")
    for w, en in misses[:10]:
        print("  未命中:", w, "|", en)
    print(f"写入 {OUT}（{OUT.stat().st_size / 1024:.0f} KB）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
