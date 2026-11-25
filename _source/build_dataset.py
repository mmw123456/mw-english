# -*- coding: utf-8 -*-
"""生成最终数据集：820 词 CSV（含 ECDICT 补全）+ 裁好的离线词库 SQLite。"""
import csv
import json
import os
import sqlite3
import sys

from roots import ROOTS

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

# ---------- 3. 用户词表（820 条，含单词本原文释义） ----------
# words 表是 43,350 词的通用词典，820 词混在里面无法区分；
# 单独建 my_words 保留顺序、原文释义与截断标记，App 直接读这张表。
con.execute("""CREATE TABLE my_words(
    no INTEGER PRIMARY KEY,
    word TEXT NOT NULL,
    word_key TEXT NOT NULL,
    phonetic TEXT,
    meaning_pdf TEXT,
    pdf_truncated INTEGER NOT NULL DEFAULT 0,
    meaning_ecdict TEXT,
    pos TEXT,
    tag TEXT,
    collins INTEGER)""")
con.executemany(
    "INSERT INTO my_words VALUES(?,?,?,?,?,?,?,?,?,?)",
    [(int(e["no"]), e["word"], e["word"].lower(), e.get("phonetic", ""),
      e["meaning"], 1 if e.get("truncated") else 0, e.get("ecdict_meaning", ""),
      e.get("pos", ""), e.get("tag", ""), int(e.get("collins") or 0))
     for e in final],
)
con.execute("CREATE INDEX idx_my_words_word ON my_words(word_key)")

# ---------- 4. 词根表（高频前缀/词根，只覆盖能拆的词） ----------
con.execute("""CREATE TABLE roots(
    root TEXT PRIMARY KEY,
    meaning TEXT NOT NULL,
    kind TEXT)""")
con.executemany("INSERT INTO roots VALUES(?,?,?)", ROOTS)

con.commit()
con.execute("VACUUM")
total = con.execute("SELECT COUNT(*) FROM words").fetchone()[0]
my_total = con.execute("SELECT COUNT(*) FROM my_words").fetchone()[0]
root_total = con.execute("SELECT COUNT(*) FROM roots").fetchone()[0]
con.close()

print("\n离线词库 ->", os.path.abspath(db))
print(f"  words    {total:,} 条")
print(f"  my_words {my_total} 条")
print(f"  roots    {root_total} 条")
print(f"  体积 {os.path.getsize(db)/1024/1024:.2f} MB")
print(f"  裁剪库缺、强制并入且用 EC 释义: {len(missing_ec)} {missing_ec}")
print(f"  裁剪库缺、强制并入且用 PDF 释义: {len(missing_pdf)} {missing_pdf}")
