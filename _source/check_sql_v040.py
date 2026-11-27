#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""在真实词库上验证 v0.4.0 的数据层。

做四件事：
1. 照 App 的 DDL 建 synonyms / user_added_words，灌入 assets/data/synonyms.json
2. 跑详情页用到的每条 SQL，报耗时与条数
3. 用与 Dart 相同的算法算形近词候选（SQL 预筛 + 编辑距离），抽 5 个词看结果
4. 统计 820 词的变形解析结果

用法：python _source/check_sql_v040.py
"""
import json
import os
import shutil
import sqlite3
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DB = os.path.join(ROOT, "assets", "db", "dict.sqlite")
SYN_JSON = os.path.join(ROOT, "app", "assets", "data", "synonyms.json")

DDL = [
    """CREATE TABLE IF NOT EXISTS synonyms(
        word_key TEXT NOT NULL, syn_key TEXT NOT NULL,
        distinction TEXT NOT NULL, rank INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(word_key, syn_key))""",
    "CREATE INDEX IF NOT EXISTS idx_syn_word ON synonyms(word_key)",
    """CREATE TABLE IF NOT EXISTS user_added_words(
        word_key TEXT PRIMARY KEY, added_at INTEGER NOT NULL)""",
]


def distance(a, b, cap=3):
    if abs(len(a) - len(b)) > cap:
        return cap + 1
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        row_min = cur[0]
        for j in range(1, len(b) + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            v = min(prev[j - 1] + cost, prev[j] + 1, cur[j - 1] + 1)
            cur[j] = v
            row_min = min(row_min, v)
        if row_min > cap:
            return cap + 1
        prev = cur
    return prev[len(b)]


def timeit(con, sql, args=(), label=""):
    t = time.perf_counter()
    rows = con.execute(sql, args).fetchall()
    ms = (time.perf_counter() - t) * 1000
    print(f"  {label:<28} {len(rows):>6} 行  {ms:7.2f} ms")
    return rows


def main():
    tmp = os.path.join(tempfile.gettempdir(), "mw_check_v040.db")
    shutil.copyfile(SRC_DB, tmp)
    con = sqlite3.connect(tmp)
    for ddl in DDL:
        con.execute(ddl)

    data = json.load(open(SYN_JSON, encoding="utf-8"))
    batch = []
    for key, items in data.items():
        for rank, s in enumerate(items):
            batch.append((key, s["w"], s["dist"], rank))
    con.executemany(
        "INSERT OR IGNORE INTO synonyms(word_key, syn_key, distinction, rank) VALUES (?,?,?,?)",
        batch,
    )
    con.commit()
    print(f"灌入近义词：{len(batch)} 行 / {len(data)} 词")

    print("\n[详情页 SQL]")
    timeit(
        con,
        "SELECT * FROM my_words WHERE word_key = ? LIMIT 1",
        ("transmit",),
        "my_words 精确查",
    )
    timeit(
        con,
        "SELECT * FROM words WHERE word = ? LIMIT 1",
        ("transmit",),
        "words 精确查",
    )
    timeit(
        con,
        """SELECT s.syn_key, s.distinction, w.translation, w.phonetic
           FROM synonyms s LEFT JOIN words w ON w.word = s.syn_key
           WHERE s.word_key = ? ORDER BY s.rank ASC""",
        ("transmit",),
        "近义词 join",
    )
    con.execute(
        "INSERT OR IGNORE INTO user_added_words(word_key, added_at) VALUES (?, ?)",
        ("abandon", int(time.time() * 1000)),
    )
    timeit(
        con,
        """SELECT w.* FROM user_added_words u JOIN words w ON w.word = u.word_key
           ORDER BY u.added_at DESC LIMIT ?""",
        (300,),
        "自加词列表",
    )
    timeit(
        con,
        "SELECT COUNT(*) FROM my_words WHERE word_key = ?",
        ("abandon",),
        "是否在 820 词内",
    )

    print("\n[形近词]（与 Dart 同一套：首字母 + 长度 ±2 预筛 + 编辑距离 ≤3）")
    for w in ("transmit", "harsh", "eliminate", "invade", "sketch"):
        t = time.perf_counter()
        rows = con.execute(
            """SELECT word, translation, frq FROM words
               WHERE word LIKE ? AND LENGTH(word) BETWEEN ? AND ? AND word <> ?
               LIMIT 4000""",
            (f"{w[0]}%", len(w) - 2, len(w) + 2, w),
        ).fetchall()
        def derived(a, b):
            short, long_ = (a, b) if len(a) <= len(b) else (b, a)
            return long_.startswith(short) and len(long_) - len(short) <= 4

        scored = []
        for word, tr, frq in rows:
            if derived(w, word):
                continue
            d = distance(w, word)
            if 0 < d <= 3:
                scored.append((d, frq if frq else 999999, word, (tr or "").split("\n")[0]))
        scored.sort()
        ms = (time.perf_counter() - t) * 1000
        top = [f"{x[2]}({x[0]})" for x in scored[:5]]
        print(f"  {w:<10} 候选 {len(rows):>4} → {top}  {ms:.1f} ms")

    print("\n[单词变形]（820 词 exchange 解析）")
    rows = con.execute(
        """SELECT m.word_key, w.exchange FROM my_words m
           LEFT JOIN words w ON w.word = m.word_key"""
    ).fetchall()
    labels = {"p": "过去式", "d": "过去分词", "i": "现在分词", "3": "三单", "s": "复数", "r": "比较级", "t": "最高级"}
    with_forms = 0
    counter = {}
    for key, ex in rows:
        parts = []
        for part in (ex or "").split("/"):
            if ":" not in part:
                continue
            code, val = part.split(":", 1)
            if code in labels and val.strip():
                parts.append(labels[code])
                counter[labels[code]] = counter.get(labels[code], 0) + 1
        if parts:
            with_forms += 1
    print(f"  有变形：{with_forms}/820")
    print("  各类型条数：" + "、".join(f"{k} {v}" for k, v in counter.items()))

    print("\n[词根白名单] 见 flutter test（detail_test.dart）")
    con.close()
    os.remove(tmp)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
