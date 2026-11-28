# -*- coding: utf-8 -*-
"""修 `my_words` 第 257 条：`take` + `advantage of phr. …` → `take advantage of`。

起因：词汇书 PDF 里这个词条的单词列换行成两行（`take` / `advantage of`），
解析脚本把第二行当成了释义开头，于是词条变成 word='take'、释义='advantage of phr. …'。
后果：按 take 查义项时全部对不上，例句筛不出来；词库页也会把一条短语显示成 take。

改法（用户 2026-11-27 定）：合并成一条 `take advantage of`。
  - word / word_key：`take advantage of`
  - meaning_pdf：去掉误并进来的 `advantage of ` 前缀
  - phonetic：PDF 没有短语音标，ECDICT 也没有 → 置空（界面不显示）
  - meaning_ecdict：原值是 ECDICT 里 take 的释义（拿、取…），对短语是错的 → 置空

用法：python _source/fix_take_entry.py [--dry]
"""
import csv
import shutil
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "app" / "assets" / "db" / "dict.sqlite"
CSV = ROOT / "data" / "words_820.csv"

NEW_WORD = "take advantage of"
NEW_MEANING = "phr. 利用；欺骗；利用，占便宜，欺骗；占......的便宜"


def fix_db(dry: bool) -> None:
    con = sqlite3.connect(DB)
    row = con.execute(
        "select no, word, word_key, phonetic, meaning_pdf from my_words where no = 257"
    ).fetchone()
    print("改前：", row)
    if row is None:
        raise SystemExit("没有 no=257 这一条，数据跟预期不符，停下")
    if row[1] == NEW_WORD:
        print("已经是 take advantage of，跳过")
        con.close()
        return
    if row[1] != "take" or not (row[4] or "").startswith("advantage of"):
        raise SystemExit(f"第 257 条不是预期的 take/advantage of，实际 {row[1]!r}，停下")
    if dry:
        print("dry-run，不写库")
        con.close()
        return
    con.execute(
        """update my_words
              set word = ?, word_key = ?, phonetic = '', meaning_pdf = ?, meaning_ecdict = ''
            where no = 257""",
        (NEW_WORD, NEW_WORD, NEW_MEANING),
    )
    con.commit()
    after = con.execute(
        "select no, word, word_key, phonetic, meaning_pdf, meaning_ecdict from my_words where no = 257"
    ).fetchone()
    print("改后：", after)
    total = con.execute("select count(*) from my_words").fetchone()[0]
    print("my_words 总数：", total)
    con.close()


def fix_csv(dry: bool) -> None:
    rows = list(csv.reader(CSV.open(encoding="utf-8-sig")))
    header, body = rows[0], rows[1:]
    hit = [r for r in body if r and r[0] == "257"]
    if not hit:
        print("CSV 里没有 no=257")
        return
    r = hit[0]
    print("CSV 改前：", r[:5])
    if r[1] == NEW_WORD:
        print("CSV 已经是 take advantage of，跳过")
        return
    r[1] = NEW_WORD
    r[3] = NEW_MEANING
    if len(r) > 5:
        r[5] = ""  # meaning_ecdict_full：原值是 take 的释义，对短语是错的
    if dry:
        print("dry-run，不写 CSV")
        return
    with CSV.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(body)
    print("CSV 改后：", r[:5])


def main(argv):
    dry = "--dry" in argv
    if not dry:
        bak = DB.with_suffix(".sqlite.bak")
        shutil.copy2(DB, bak)
        print("备份：", bak)
    fix_db(dry)
    fix_csv(dry)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
