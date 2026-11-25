# -*- coding: utf-8 -*-
"""生成最终数据集：820 词 CSV（含 ECDICT 补全）+ 裁好的离线词库 SQLite。"""
import csv
import json
import os
import sqlite3
import sys

csv.field_size_limit(sys.maxsize)

EXAM_TAGS = {"zk", "gk", "cet4", "cet6", "ky", "ielts", "toefl", "gre"}

ec = {}
with open("ecdict.csv", encoding="utf-8", newline="") as f:
    for r in csv.DictReader(f):
        if (r.get("translation") or "").strip():
            ec.setdefault(r["word"].lower(), r)


def frq(r):
    try:
        return int(r.get("frq") or 0)
    except ValueError:
        return 0


final = json.load(open("words_final.json", encoding="utf-8"))

# ---------- 1. 820 词表 ----------
def fix_translation(raw: str, sep: str) -> str:
    """ECDICT 用字面 \\n 分隔义项，转成统一分隔符。"""
    s = (raw or "").replace("\\n", sep).replace("\r", "")
    return s.strip()


for e in final:
    row = ec.get(e["word"].lower())
    e["phonetic"] = (row or {}).get("phonetic", "") or e.get("ecdict_phonetic", "")
    e["ecdict_meaning"] = fix_translation((row or {}).get("translation", ""), " / ")
    e["tag"] = (row or {}).get("tag", "")
    e["collins"] = (row or {}).get("collins", "")
    e["pos"] = (row or {}).get("pos", "")

with open("../data/words_820.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f)
    w.writerow(["no", "word", "phonetic", "meaning_pdf", "pdf_truncated",
                "meaning_ecdict_full", "pos", "tag", "collins"])
    for e in final:
        w.writerow([e["no"], e["word"], e["phonetic"], e["meaning"],
                    "Y" if e.get("truncated") else "", e["ecdict_meaning"],
                    e["pos"], e["tag"], e["collins"]])

print("820 词表 ->", os.path.abspath("../data/words_820.csv"))
print("  有音标:", sum(1 for e in final if e["phonetic"]), "/ 820")
print("  有 ECDICT 完整释义:", sum(1 for e in final if e["ecdict_meaning"]), "/ 820")

# ---------- 2. 离线词库 ----------
tagged = [r for r in ec.values() if set((r.get("tag") or "").split()) & EXAM_TAGS]
ranked = sorted([r for r in ec.values() if frq(r) > 0], key=frq)

sel = {r["word"].lower(): r for r in tagged}
for r in ranked:
    sel.setdefault(r["word"].lower(), r)

db = "../assets/db/dict.sqlite"
os.makedirs(os.path.dirname(db), exist_ok=True)
if os.path.exists(db):
    os.remove(db)
con = sqlite3.connect(db)
con.execute("""CREATE TABLE words(
    word TEXT PRIMARY KEY,
    phonetic TEXT, translation TEXT, pos TEXT, tag TEXT,
    collins INTEGER, frq INTEGER, exchange TEXT)""")
con.executemany(
    "INSERT OR IGNORE INTO words VALUES(?,?,?,?,?,?,?,?)",
    [(r["word"], r.get("phonetic", ""), fix_translation(r["translation"], "\n"), r.get("pos", ""),
      r.get("tag", ""), int(r.get("collins") or 0), frq(r), r.get("exchange", ""))
     for r in sel.values()],
)
# 820 词强制入库：EC 全库有释义则用 EC，全库也没有才退回 PDF 释义
missing_ec, missing_pdf = [], []
for e in final:
    k = e["word"].lower()
    if k in sel:
        continue
    row = ec.get(k)
    if row:
        trans = fix_translation(row["translation"], "\n")
        phon = row.get("phonetic", "") or e.get("phonetic", "")
        tag = row.get("tag", "") or "user820"
        missing_ec.append(e["word"])
    else:
        trans = e["meaning"]
        phon = e.get("phonetic", "")
        tag = "user820"
        missing_pdf.append(e["word"])
    con.execute("INSERT OR REPLACE INTO words VALUES(?,?,?,?,?,?,?,?)",
                (k, phon, trans, e.get("pos", ""), tag, 0, 0, ""))
con.execute("CREATE INDEX idx_word ON words(word)")
con.commit()
con.execute("VACUUM")
total = con.execute("SELECT COUNT(*) FROM words").fetchone()[0]
con.close()

print("\n离线词库 ->", os.path.abspath(db))
print(f"  词条 {total:,}, 体积 {os.path.getsize(db)/1024/1024:.1f} MB")
print(f"  裁剪库缺、强制并入且用 EC 释义: {len(missing_ec)} {missing_ec}")
print(f"  裁剪库缺、强制并入且用 PDF 释义: {len(missing_pdf)} {missing_pdf}")
