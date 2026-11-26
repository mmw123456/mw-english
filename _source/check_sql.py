# -*- coding: utf-8 -*-
"""在真实词库上跑一遍 App 里的 SQL，确认语法与结果都正常。

DAO 里的 SQL 是手写的，Flutter 静态分析查不出 SQL 错误，
只能在真机跑才发现。这里提前用 Python 跑同一批语句。
"""
import sqlite3
import time

con = sqlite3.connect("../app/assets/db/dict.sqlite")
con.row_factory = sqlite3.Row

# 模拟 App 首次启动补建用户表
con.executescript("""
CREATE TABLE IF NOT EXISTS study_record(
  word_key TEXT PRIMARY KEY, box INTEGER NOT NULL DEFAULT 0,
  due_at INTEGER NOT NULL, streak INTEGER NOT NULL DEFAULT 0,
  correct_count INTEGER NOT NULL DEFAULT 0, wrong_count INTEGER NOT NULL DEFAULT 0,
  first_seen_at INTEGER NOT NULL, last_seen_at INTEGER,
  starred INTEGER NOT NULL DEFAULT 0, killed INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS idx_record_due ON study_record(killed, due_at);
CREATE TABLE IF NOT EXISTS study_log(
  id INTEGER PRIMARY KEY AUTOINCREMENT, word_key TEXT NOT NULL,
  at INTEGER NOT NULL, correct INTEGER NOT NULL, question_type TEXT);
CREATE INDEX IF NOT EXISTS idx_log_at ON study_log(at);
CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
""")

fail = 0


def run(name, sql, args=()):
    global fail
    t0 = time.perf_counter()
    try:
        rows = con.execute(sql, args).fetchall()
        ms = (time.perf_counter() - t0) * 1000
        first = dict(rows[0]) if rows else None
        preview = ""
        if first:
            preview = str(first)[:110]
        print(f"  OK  {name:22s} {len(rows):>5} 行 {ms:7.2f} ms  {preview}")
        return rows
    except Exception as e:
        fail += 1
        print(f"  FAIL {name:22s} {e}")
        return []


print("=== 计数 ===")
run("countMyWords", "SELECT COUNT(*) AS c FROM my_words")
run("countDictionary", "SELECT COUNT(*) AS c FROM words")

print("\n=== loadMyWords（首页 200 条） ===")
run("loadMyWords", "SELECT * FROM my_words ORDER BY no ASC LIMIT 200 OFFSET 0")

print("\n=== searchMyWords ===")
for q in ("tra", "transmit", "insult", "once"):
    run(f"my:{q}", """
      SELECT * FROM my_words
      WHERE word_key LIKE ?1
      ORDER BY CASE WHEN word_key = ?2 THEN 0 WHEN word_key LIKE ?3 THEN 1 ELSE 2 END, no ASC
      LIMIT ?4
    """, (f"%{q}%", q, f"{q}%", 60))

print("\n=== searchDictionary ===")
for q in ("abandon", "trans", "zenith"):
    run(f"dict:{q}", """
      SELECT * FROM words
      WHERE word LIKE ?1
      ORDER BY CASE WHEN word = ?2 THEN 0 WHEN word LIKE ?3 THEN 1 ELSE 2 END,
               CASE WHEN frq = 0 THEN 999999 ELSE frq END ASC
      LIMIT ?4
    """, (f"%{q}%", q, f"{q}%", 40))

print("\n=== lookup 精确查 ===")
for w in ("abandon", "once (and) for all", "flip"):
    run(f"lookup:{w[:12]}", "SELECT * FROM words WHERE word = ? LIMIT 1", (w.lower(),))

print("\n=== todayStats ===")
now = int(time.time() * 1000)
day_start = now - (now % 86400000)
run("newLearned", "SELECT COUNT(*) FROM study_record WHERE first_seen_at >= ? AND first_seen_at < ?",
    (day_start, day_start + 86400000))
run("dueReview", "SELECT COUNT(*) FROM study_record WHERE killed = 0 AND box > 0 AND due_at <= ?", (now,))
run("wrongToday", "SELECT COUNT(*) FROM study_log WHERE correct = 0 AND at >= ? AND at < ?",
    (day_start, day_start + 86400000))
run("totalLearned", "SELECT COUNT(*) FROM study_record")
run("mastered", "SELECT COUNT(*) FROM study_record WHERE killed = 0 AND box >= 5")
run("killedCount", "SELECT COUNT(*) FROM study_record WHERE killed = 1")
run("starredCount", "SELECT COUNT(*) FROM study_record WHERE starred = 1")

print("\n=== studyDayNumber ===")
run("studyDayNumber", "SELECT MIN(first_seen_at) AS m FROM study_record")

print("\n=== 写入一条学习记录再查（模拟第 4 步） ===")
try:
    con.execute("""INSERT OR REPLACE INTO study_record
        (word_key, box, due_at, streak, correct_count, wrong_count, first_seen_at)
        VALUES (?,?,?,?,?,?,?)""", ("transmit", 1, now + 86400000, 1, 1, 0, now))
    con.execute("INSERT INTO study_log (word_key, at, correct, question_type) VALUES (?,?,?,?)",
                ("transmit", now, 0, "recall"))
    con.commit()
    run("totalLearned(有数据)", "SELECT COUNT(*) FROM study_record")
    run("wrongToday(有数据)", "SELECT COUNT(*) FROM study_log WHERE correct = 0 AND at >= ?",
        (day_start,))
    con.execute("DELETE FROM study_record")
    con.execute("DELETE FROM study_log")
    con.commit()
    print("  清理完成，词库恢复空用户表")
except Exception as e:
    fail += 1
    print(f"  FAIL 写入测试: {e}")

print("\n" + ("全部通过" if fail == 0 else f"{fail} 条失败"))
