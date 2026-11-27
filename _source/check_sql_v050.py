"""v0.5.0 学习调度 SQL 校验。

在真实词库副本上跑一遍 App 里的 SQL，核对：
1. 新词池只取「没学过」的 820 词，按序号
2. 到期复习只取 due_at <= now 且已开始的词（含当日重测）
3. 单日复习上限 150
4. 学习记录写入后，box / due_at / retest 符合 Leitner 规则
5. 断档配额

用法：python _source/check_sql_v050.py
"""
import os
import shutil
import sqlite3
import tempfile
import time
from datetime import datetime, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "db", "dict.sqlite")

CREATE_RECORD = """
CREATE TABLE IF NOT EXISTS study_record(
  word_key      TEXT PRIMARY KEY,
  box           INTEGER NOT NULL DEFAULT 0,
  due_at        INTEGER NOT NULL,
  streak        INTEGER NOT NULL DEFAULT 0,
  correct_count INTEGER NOT NULL DEFAULT 0,
  wrong_count   INTEGER NOT NULL DEFAULT 0,
  first_seen_at INTEGER NOT NULL,
  last_seen_at  INTEGER,
  starred       INTEGER NOT NULL DEFAULT 0,
  killed        INTEGER NOT NULL DEFAULT 0,
  started       INTEGER NOT NULL DEFAULT 0,
  retest        INTEGER NOT NULL DEFAULT 0,
  peak_box      INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_record_due ON study_record(killed, due_at);
CREATE TABLE IF NOT EXISTS study_log(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word_key TEXT NOT NULL,
  at INTEGER NOT NULL,
  correct INTEGER NOT NULL,
  question_type TEXT
);
CREATE INDEX IF NOT EXISTS idx_log_at ON study_log(at);
CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""

NEW_WORDS = """
SELECT m.word_key, m.word, m.phonetic, m.meaning_pdf, m.meaning_ecdict
FROM my_words m
LEFT JOIN study_record r ON r.word_key = m.word_key
WHERE r.word_key IS NULL OR r.started = 0
ORDER BY m.no ASC
LIMIT ?
"""

DUE_REVIEWS = """
SELECT r.word_key, r.box, r.retest, r.correct_count, r.wrong_count,
       m.word, m.phonetic, m.meaning_pdf, m.meaning_ecdict
FROM study_record r
JOIN my_words m ON m.word_key = r.word_key
WHERE r.started = 1 AND r.killed = 0 AND r.due_at <= ?
  AND (r.box > 0 OR r.retest = 1)
ORDER BY r.due_at ASC
LIMIT ?
"""

COUNT_NEW_TODAY = """
SELECT COUNT(*) FROM study_record
WHERE started = 1 AND first_seen_at >= ? AND first_seen_at < ?
"""

DUE_COUNT = """
SELECT COUNT(*) FROM study_record
WHERE started = 1 AND killed = 0 AND due_at <= ?
  AND (box > 0 OR retest = 1)
"""

ok = 0
fail = 0


def check(name, cond, extra=""):
    global ok, fail
    if cond:
        ok += 1
        print(f"  ok   {name} {extra}")
    else:
        fail += 1
        print(f"  FAIL {name} {extra}")


def main():
    tmpdir = tempfile.mkdtemp(prefix="mw_")
    path = os.path.join(tmpdir, "check.db")
    shutil.copy(SRC, path)
    c = sqlite3.connect(path)
    c.executescript(CREATE_RECORD)

    now = datetime(2026, 11, 25, 20, 0)
    now_ms = int(now.timestamp() * 1000)
    day0 = datetime(2026, 11, 25)
    from_ms = int(day0.timestamp() * 1000)
    to_ms = int((day0 + timedelta(days=1)).timestamp() * 1000)

    print("[1] 新词池")
    t0 = time.time()
    rows = c.execute(NEW_WORDS, (30,)).fetchall()
    dt = (time.time() - t0) * 1000
    check("取到 30 个新词", len(rows) == 30, f"({dt:.1f} ms)")
    check("按序号排（transmit 开头）", rows[0][0] == "transmit", rows[0][0])

    print("[2] 空库没有待复习")
    due = c.execute(DUE_REVIEWS, (now_ms, 150)).fetchall()
    check("新库复习为空", len(due) == 0)

    print("[3] 首次学习：答对 → 1 箱 + 当日重测")
    key = rows[0][0]
    c.execute(
        """INSERT INTO study_record
           (word_key, box, due_at, streak, correct_count, wrong_count,
            first_seen_at, last_seen_at, starred, killed, started, retest, peak_box)
           VALUES (?,1,?,1,1,0,?,?,0,0,1,1,1)""",
        (key, now_ms, now_ms, now_ms),
    )
    c.commit()
    learned = c.execute(COUNT_NEW_TODAY, (from_ms, to_ms)).fetchone()[0]
    check("今日已学新词计 1", learned == 1)
    due = c.execute(DUE_REVIEWS, (now_ms, 150)).fetchall()
    check("当日重测进复习队列", len(due) == 1 and due[0][0] == key)
    check("重测卡箱位是 1", due[0][1] == 1)

    print("[4] 新词池扣掉已学")
    rows = c.execute(NEW_WORDS, (30,)).fetchall()
    check("新词池顺延（第 1 个变成 conscious）", rows[0][0] == "conscious", rows[0][0])
    check("不再含刚学的词", all(r[0] != key for r in rows))

    print("[5] 到期判定：未来 due_at 不出现")
    c.execute(
        "UPDATE study_record SET due_at=?, retest=0 WHERE word_key=?",
        (now_ms + 86400000, key),
    )
    c.commit()
    due = c.execute(DUE_REVIEWS, (now_ms, 150)).fetchall()
    check("明天到期今天不出现", len(due) == 0)

    print("[6] 积压：150 上限生效")
    base = int(datetime(2026, 10, 1).timestamp() * 1000)
    pool = [r[0] for r in c.execute("SELECT word_key FROM my_words LIMIT 200")]
    for i, k in enumerate(pool):
        c.execute(
            """INSERT OR REPLACE INTO study_record
               (word_key, box, due_at, streak, correct_count, wrong_count,
                first_seen_at, last_seen_at, starred, killed, started, retest, peak_box)
               VALUES (?,3,?,3,3,0,?,?,0,0,1,0,3)""",
            (k, base + i * 1000, base, base),
        )
    c.commit()
    total_due = c.execute(DUE_COUNT, (now_ms,)).fetchone()[0]
    picked = c.execute(DUE_REVIEWS, (now_ms, 150)).fetchall()
    check("堆了 >150 条待复习", total_due >= 150, f"(共 {total_due})")
    check("单次最多出 150 张", len(picked) == 150, f"(实际 {len(picked)})")
    check("积压按最早的先出", picked[0][0] == pool[0], picked[0][0])

    print("[7] 复习队列耗时")
    t0 = time.time()
    for _ in range(20):
        c.execute(DUE_REVIEWS, (now_ms, 150)).fetchall()
    dt = (time.time() - t0) * 1000 / 20
    check("单次查询 < 20 ms", dt < 20, f"({dt:.1f} ms)")

    print("[8] 星标空壳不算学过")
    star = c.execute(
        """SELECT m.word_key FROM my_words m
           LEFT JOIN study_record r ON r.word_key = m.word_key
           WHERE r.word_key IS NULL ORDER BY m.no LIMIT 1"""
    ).fetchone()[0]
    c.execute(
        """INSERT INTO study_record
           (word_key, box, due_at, streak, correct_count, wrong_count,
            first_seen_at, last_seen_at, starred, killed, started, retest, peak_box)
           VALUES (?,0,?,0,0,0,0,NULL,1,0,0,0,0)""",
        (star, now_ms),
    )
    c.commit()
    learned = c.execute(COUNT_NEW_TODAY, (from_ms, to_ms)).fetchone()[0]
    check("只加星标不计入今日已学", learned == 1, f"(实际 {learned})")
    rows = c.execute(NEW_WORDS, (30,)).fetchall()
    check("加星的词仍在新词池", any(r[0] == star for r in rows), star)

    print("[9] 索引命中")
    plan = c.execute("EXPLAIN QUERY PLAN " + DUE_REVIEWS, (now_ms, 150)).fetchall()
    txt = " ".join(str(p) for p in plan)
    check("到期查询走 idx_record_due", "idx_record_due" in txt, txt[:120])

    c.close()
    shutil.rmtree(tmpdir, ignore_errors=True)

    print()
    print(f"通过 {ok} / {ok + fail}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
