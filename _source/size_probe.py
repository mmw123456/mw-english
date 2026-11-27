# -*- coding: utf-8 -*-
"""按不同规模裁剪 ECDICT，实测 SQLite 体积；并分析 820 词的前缀/词根分布。"""
import csv
import json
import os
import re
import sqlite3
import sys
from collections import Counter

csv.field_size_limit(sys.maxsize)

EXAM_TAGS = {"zk", "gk", "cet4", "cet6", "ky", "ielts", "toefl", "gre"}
rows = []
with open("ecdict.csv", encoding="utf-8", newline="") as f:
    for r in csv.DictReader(f):
        if (r.get("translation") or "").strip():
            rows.append(r)


def frq(r):
    try:
        return int(r.get("frq") or 0)
    except ValueError:
        return 0


tagged = [r for r in rows if set((r.get("tag") or "").split()) & EXAM_TAGS]
ranked = sorted([r for r in rows if frq(r) > 0], key=frq)
final = json.load(open("words_final.json", encoding="utf-8"))
must = {e["word"].lower(): e for e in final}

for n in (30000, 50000, 80000, 150000, 220000):
    sel = {r["word"].lower(): r for r in tagged}
    for r in ranked[:n]:
        sel.setdefault(r["word"].lower(), r)
    # 820 词强制并入（EC 里存在则取 EC 行，不存在则用 PDF 行）
    extra = [k for k in must if k not in sel]
    path = "_probe.sqlite"
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    con.execute("""CREATE TABLE words(word TEXT PRIMARY KEY, phonetic TEXT,
        translation TEXT, pos TEXT, tag TEXT, collins INTEGER, frq INTEGER, exchange TEXT)""")
    con.executemany(
        "INSERT OR IGNORE INTO words VALUES(?,?,?,?,?,?,?,?)",
        [(r["word"], r.get("phonetic", ""), r["translation"], r.get("pos", ""),
          r.get("tag", ""), int(r.get("collins") or 0), frq(r), r.get("exchange", ""))
         for r in sel.values()],
    )
    con.commit()
    con.execute("VACUUM")
    con.close()
    print(f"词频前 {n:>7,} + 考试标签 + 820 强制  => {len(sel):>7,} 词, "
          f"{os.path.getsize(path)/1024/1024:>5.1f} MB, 820 缺口 {len(extra)}")

# 820 词前缀分布（词根表可行性预判）
PREFIX = ["un", "re", "in", "im", "dis", "pre", "pro", "con", "com", "sub", "sur",
          "super", "trans", "ex", "e", "de", "ab", "ad", "per", "inter", "mis",
          "over", "under", "out", "up", "en", "em", "anti", "auto", "bi", "co",
          "counter", "extra", "fore", "hyper", "mono", "non", "post", "semi", "un"]
hit = Counter()
for e in final:
    w = e["word"].lower()
    for p in sorted(PREFIX, key=len, reverse=True):
        if w.startswith(p) and len(w) > len(p) + 2:
            hit[p] += 1
            break
print("\n820 词可识别常见前缀的条数:", sum(hit.values()), "/", len(final))
print("前 15 个前缀:", hit.most_common(15))
