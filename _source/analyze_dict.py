# -*- coding: utf-8 -*-
"""分析 ECDICT 裁剪方案，估算 SQLite 体积。"""
import csv
import os
import sqlite3
import sys

csv.field_size_limit(sys.maxsize)

EXAM_TAGS = {"zk", "gk", "cet4", "cet6", "ky", "ielts", "toefl", "gre"}
rows = []
with open("ecdict.csv", encoding="utf-8", newline="") as f:
    for r in csv.DictReader(f):
        if not (r.get("translation") or "").strip():
            continue
        rows.append(r)

print("有中文释义的词条:", len(rows))

tagged = [r for r in rows if set((r.get("tag") or "").split()) & EXAM_TAGS]
print("带考试标签(zk/gk/cet4/cet6/ky/ielts/toefl/gre):", len(tagged))

def frqkey(r):
    try:
        v = int(r.get("frq") or 0)
    except ValueError:
        v = 0
    return v

ranked = [r for r in rows if frqkey(r) > 0]
ranked.sort(key=frqkey)
print("有词频(frq>0)的词条:", len(ranked))

for n in (20000, 30000, 40000):
    print(f"  词频前 {n}:", len(ranked[:n]))

# 方案：考试标签词 ∪ 词频前 30000
sel = {r["word"].lower(): r for r in tagged}
for r in ranked[:30000]:
    sel.setdefault(r["word"].lower(), r)
print("方案 A 合并后词条数:", len(sel))

# 建库量体积
for name, subset in (("A", sel),):
    path = f"_probe_{name}.sqlite"
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    con.execute("""CREATE TABLE words(
        word TEXT PRIMARY KEY, phonetic TEXT, translation TEXT,
        pos TEXT, tag TEXT, collins INTEGER, frq INTEGER, exchange TEXT)""")
    con.executemany(
        "INSERT OR IGNORE INTO words VALUES(?,?,?,?,?,?,?,?)",
        [(r["word"], r.get("phonetic", ""), r["translation"], r.get("pos", ""),
          r.get("tag", ""), int(r.get("collins") or 0), frqkey(r), r.get("exchange", ""))
         for r in subset.values()],
    )
    con.execute("CREATE INDEX idx_frq ON words(frq)")
    con.commit()
    con.execute("VACUUM")
    con.close()
    size = os.path.getsize(path)
    print(f"方案 {name}: {len(subset)} 词, {size/1024/1024:.1f} MB")

# 820 词是否都在方案 A 里
import json
final = json.load(open("words_final.json", encoding="utf-8"))
miss = [e["word"] for e in final if e["word"].lower() not in sel]
print("820 词未落入方案 A:", len(miss), miss[:10])
