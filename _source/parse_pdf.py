# -*- coding: utf-8 -*-
"""从 单词本-820词.pdf 抽取词条，输出 words_raw.json 并做完整性校验。"""
import json
import re

import pymupdf

PDF = "单词本-820词.pdf"
SKIP = {"Classic", "Vocabulary List", "No.", "Word", "Meaning"}

doc = pymupdf.open(PDF)
lines = []
for page in doc:
    lines.extend(page.get_text().split("\n"))

entries = []
cur = None
for raw in lines:
    s = raw.strip()
    if not s:
        continue
    if s in SKIP:
        continue
    if s.startswith("Title:") or s.startswith("Date:"):
        continue
    if re.fullmatch(r"-\s*\d+", s):  # 页脚页码
        continue
    if re.fullmatch(r"\d{1,3}", s):  # 序号行
        cur = {"no": int(s), "word": None, "lines": []}
        entries.append(cur)
        continue
    if cur is None:
        continue
    if cur["word"] is None:
        cur["word"] = s
    else:
        cur["lines"].append(s)

for e in entries:
    e["meaning"] = " ".join(e.pop("lines")).strip()

nos = [e["no"] for e in entries]
seen = set(nos)
missing = [i for i in range(1, 821) if i not in seen]
dups = sorted({n for n in nos if nos.count(n) > 1})
noword = [e["no"] for e in entries if not e["word"]]
nomean = [e["no"] for e in entries if not e["meaning"]]

print("总条数:", len(entries))
print("序号范围:", min(nos), "-", max(nos))
print("缺号数:", len(missing), "->", missing[:40])
print("重号:", dups[:20])
print("无单词:", noword[:20])
print("无释义:", nomean[:20])

words = [e["word"] for e in entries if e["word"]]
print("去重后单词数:", len(set(w.lower() for w in words)))

# 释义是否被截断（含省略号）
trunc = [e["no"] for e in entries if "…" in e["meaning"] or "..." in e["meaning"]]
print("释义被截断的条数:", len(trunc), "占", round(len(trunc) / len(entries) * 100, 1), "%")

with open("words_raw.json", "w", encoding="utf-8") as f:
    json.dump(entries, f, ensure_ascii=False, indent=1)

print("\n--- 前 3 条 / 后 3 条 ---")
for e in entries[:3] + entries[-3:]:
    print(e["no"], "|", e["word"], "|", e["meaning"][:90])
