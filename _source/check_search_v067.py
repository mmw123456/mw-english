"""v0.6.7 中文搜索验收：英文仍只匹配开头，中文按释义包含。

三条主线：
1. 中文能搜到（v0.6.5 遗留的那条）：我的词表查 meaning_pdf / meaning_ecdict，
   离线词典与自加词查 translation
2. 英文不回退：v0.6.2 的前缀规则仍然有效（搜 no 不出 indigenous 那一批）
3. 实现真的分了岔：源码里汉字走释义分支，英文走前缀分支

跑法：python _source/check_search_v067.py
"""

import os
import re
import sqlite3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "app", "assets", "db", "dict.sqlite")
DAO = os.path.join(ROOT, "app", "lib", "data", "dao", "word_dao.dart")

CJK = re.compile(r"[\u4e00-\u9fff]")

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {detail}")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _version_at_least(pub, want):
    m = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)", pub, re.M)
    return bool(m) and tuple(map(int, m.groups())) >= tuple(want)


db = sqlite3.connect(DB)
# user_added_words 是 App 首次启动才建的表，assets 里没有。
# 用 TEMP 表补出来，只为验证 SQL 能执行；不写回词库文件。
db.execute(
    "CREATE TEMP TABLE IF NOT EXISTS user_added_words("
    "word_key TEXT PRIMARY KEY, added_at INTEGER NOT NULL)"
)


def is_cn(q):
    """与 Dart 里 _cjk 同一段码位范围。"""
    return bool(CJK.search(q))


def q_my(q, limit=60):
    """与 searchMyWords 中文分支等价。"""
    return [
        r[0]
        for r in db.execute(
            """
            SELECT word FROM my_words
            WHERE meaning_pdf LIKE ?1 OR meaning_ecdict LIKE ?1
            ORDER BY no ASC
            LIMIT ?2
            """,
            [f"%{q}%", limit],
        )
    ]


def q_dict(q, limit=40):
    """与 searchDictionary 中文分支等价。"""
    return [
        r[0]
        for r in db.execute(
            """
            SELECT word FROM words
            WHERE translation LIKE ?1
            ORDER BY CASE WHEN frq = 0 THEN 999999 ELSE frq END ASC,
                     word ASC
            LIMIT ?2
            """,
            [f"%{q}%", limit],
        )
    ]


def q_prefix_words(q):
    """v0.6.2 的英文前缀分支（中文走这条必然空）。"""
    return [
        r[0]
        for r in db.execute(
            "SELECT word FROM words WHERE word LIKE ?1 LIMIT 40", [f"{q.lower()}%"]
        )
    ]


def q_added(q):
    """自加词表为空时也必须能执行、不报错。"""
    return [
        r[0]
        for r in db.execute(
            """
            SELECT w.word FROM user_added_words u
            JOIN words w ON w.word = u.word_key
            WHERE w.translation LIKE ?1
            ORDER BY u.added_at DESC
            LIMIT 20
            """,
            [f"%{q}%"],
        )
    ]


def cjk_checks():
    print("[中文能搜到]")
    check("'传' 被判为中文查询", is_cn("传"))
    check("'transmit' 不被判为中文查询", not is_cn("transmit"))

    my = q_my("传")
    check("我的词表搜 '传' 有结果", len(my) > 0, f"命中 {len(my)}")
    check("我的词表搜 '传' 命中 transmit", "transmit" in my, str(my[:6]))

    d = q_dict("传送")
    check("离线词典搜 '传送' 有结果", len(d) > 0, f"命中 {len(d)}")
    check("离线词典搜 '传送' 含 transmit/transfer",
          bool({"transmit", "transfer", "carry"} & set(d)), str(d[:8]))

    # 旧实现（word LIKE '传%'）必然空 —— 这就是 v0.6.2 遗留的那条。
    check("中文在英文前缀分支里确实搜不到（旧实现必空）",
          q_prefix_words("传") == [], str(q_prefix_words("传")[:5]))

    check("自加词查中文可执行（空表不报错）", q_added("传") == [])


def english_checks():
    print("[英文不回退]")
    no_hits = set(q_prefix_words("no"))
    for w in ("indigenous", "manoeuvre", "autonomy", "renovate", "gastronomic"):
        check(f"搜 no 不出 {w}", w not in no_hits)
    n_hits = set(q_prefix_words("n"))
    for w in ("transmit", "conscious"):
        check(f"搜 n 不出 {w}", w not in n_hits)
    check("搜 no 仍有前缀命中（不是搜空了）", bool(no_hits), str(sorted(no_hits)[:5]))
    check("搜 n 命中的词都以 n 开头",
          all(w.lower().startswith("n") for w in n_hits),
          str([w for w in n_hits if not w.lower().startswith("n")][:5]))


def order_checks():
    print("[排序]")
    rows = list(db.execute(
        """
        SELECT word, CASE WHEN frq = 0 THEN 999999 ELSE frq END AS f
        FROM words WHERE translation LIKE '%传送%'
        ORDER BY f ASC, word ASC LIMIT 40
        """
    ))
    scores = [r[1] for r in rows]
    check("中文词典结果按词频升序（高频在前）", scores == sorted(scores), str(scores[:8]))


def source_checks():
    print("[实现分岔]")
    src = read(DAO)
    check("DAO 里有汉字判定", "RegExp(r'[\\u4e00-\\u9fff]')" in src)
    check("我的词表查两段释义", "meaning_pdf LIKE ?1 OR meaning_ecdict LIKE ?1" in src)
    check("离线词典查 translation", "WHERE translation LIKE ?1" in src)
    # 英文分支还必须是前缀：三处都保留 `['$q%', q, '$q%', limit]`。
    prefix_args = src.count("['$q%', q, '$q%', limit]")
    check("英文分支仍是前缀（三处都保留 $q%）", prefix_args == 3,
          f"实际 {prefix_args} 处")
    check("英文分支没有把单词列退回包含匹配",
          "word_key LIKE '%" not in src and "word LIKE '%" not in src)
    check("三处搜索都判了中文", src.count("_isChinese(q)") == 3,
          f"实际 {src.count('_isChinese(q)')} 处")


def version_checks():
    print("[版本]")
    pub = read(os.path.join(ROOT, "app", "pubspec.yaml"))
    check("版本号 ≥ 0.6.7（不回退）", _version_at_least(pub, (0, 6, 7)),
          pub.splitlines()[4] if len(pub.splitlines()) > 4 else "")


cjk_checks()
english_checks()
order_checks()
source_checks()
version_checks()

print()
print(f"{passed}/{passed + failed} 通过")
raise SystemExit(0 if failed == 0 else 1)
