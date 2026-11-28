# -*- coding: utf-8 -*-
"""核对 820 词在 ECDICT 中的覆盖率与释义可用性。"""
import csv
import json
import re
import sys

csv.field_size_limit(sys.maxsize)

ec = {}
with open("ecdict.csv", encoding="utf-8", newline="") as f:
    for row in csv.DictReader(f):
        w = (row.get("word") or "").strip()
        if w:
            ec.setdefault(w.lower(), row)

print("ECDICT 词条数:", len(ec))

entries = json.load(open("words_clean.json", encoding="utf-8"))

hit, hit_no_trans, miss = [], [], []
for e in entries:
    key = e["word"].lower()
    base = re.sub(r"\s*\(.*?\)\s*", " ", e["word"]).strip().lower()
    row = ec.get(key) or ec.get(base)
    if row is None:
        miss.append(e)
        continue
    e["ecdict_word"] = row["word"]
    e["ecdict_phonetic"] = row.get("phonetic", "")
    e["ecdict_translation"] = row.get("translation", "")
    e["ecdict_pos"] = row.get("pos", "")
    e["ecdict_tag"] = row.get("tag", "")
    e["ecdict_collins"] = row.get("collins", "")
    if (row.get("translation") or "").strip():
        hit.append(e)
    else:
        hit_no_trans.append(e)

print(f"命中且有中文释义: {len(hit)}")
print(f"命中但 ECDICT 无中文释义: {len(hit_no_trans)}")
print(f"未命中: {len(miss)}")

if hit_no_trans:
    print("\n--- 命中无释义 ---")
    for e in hit_no_trans[:15]:
        print(e["no"], e["word"])

if miss:
    print("\n--- 未命中全部 ---")
    for e in miss:
        print(e["no"], "|", e["word"], "|", e["meaning"][:50])

with open("words_merged.json", "w", encoding="utf-8") as f:
    json.dump(entries, f, ensure_ascii=False, indent=1)

print("\n--- 覆盖率样例：PDF 释义 vs ECDICT 释义 ---")
shown = 0
for e in entries:
    if not e.get("truncated"):
        continue
    print(f"[{e['no']}] {e['word']}")
    print("  PDF :", e["meaning"][:80])
    print("  ECD :", (e.get("ecdict_translation") or "").replace("\n", " / ")[:100])
    shown += 1
    if shown >= 6:
        break
