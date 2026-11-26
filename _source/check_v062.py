"""校验 v0.6.2 四处改动：前缀搜索 / 添加时间排序 / 「不认识」/ 遮盖点按切换。

分两类检查：
  1) 数据层：直接对真词库跑 Dart 里那条 SQL 的等价语句，验证「只匹配开头」和
     「添加时间 = 按序号倒序」在真实数据上成立。
  2) 源码层：把几条容易写反的规则钉死（三处 LIKE 不许再出现 %q%；排序必须
     是原序→随机→添加时间→原序；遮盖必须能删也能加；「不认识」答对后隐藏）。

只读，不改任何文件。用法：python _source/check_v062.py
"""

import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
APP = os.path.join(ROOT, "app")
DB = os.path.join(APP, "assets", "db", "dict.sqlite")

PASS = 0
FAIL = 0


def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}" + (f"  -> {detail}" if detail else ""))


def read(rel):
    with open(os.path.join(APP, rel), encoding="utf-8") as f:
        return f.read()


# ---- 数据层 -------------------------------------------------------------

def prefix_search_checks(c):
    """三处搜索都是 LIKE 'q%'，等价于 word LIKE '?%'。"""
    # searchMyWords 的 where 条件
    def my_hits(q):
        return [
            r[0]
            for r in c.execute(
                """
                SELECT word_key FROM my_words
                WHERE word_key LIKE ?1
                ORDER BY CASE WHEN word_key = ?2 THEN 0
                              WHEN word_key LIKE ?3 THEN 1
                              ELSE 2 END, no ASC
                """,
                [q + "%", q, q + "%"],
            )
        ]

    def added_hits(q):
        return [
            r[0]
            for r in c.execute(
                """
                SELECT u.word_key FROM user_added_words u
                JOIN words w ON w.word = u.word_key
                WHERE u.word_key LIKE ?1
                ORDER BY CASE WHEN u.word_key = ?2 THEN 0
                              WHEN u.word_key LIKE ?3 THEN 1
                              ELSE 2 END, u.added_at DESC
                """,
                [q + "%", q, q + "%"],
            )
        ]

    def dict_hits(q):
        return [
            r[0]
            for r in c.execute(
                """
                SELECT word FROM words
                WHERE word LIKE ?1
                ORDER BY CASE WHEN word = ?2 THEN 0
                              WHEN word LIKE ?3 THEN 1
                              ELSE 2 END,
                         CASE WHEN frq = 0 THEN 999999 ELSE frq END ASC
                """,
                [q + "%", q, q + "%"],
            )
        ]

    hits_no = my_hits("no")
    banned_no = ["indigenous", "manoeuvre", "autonomy", "renovate", "gastronomic"]
    left = [w for w in banned_no if w in hits_no]
    check('搜 "no" 不再命中中间含 no 的词', not left, f"仍出现 {left}")
    check('搜 "no" 仍有前缀命中', len(hits_no) > 0, f"命中 {hits_no}")

    hits_n = my_hits("n")
    banned_n = ["transmit", "conscious"]
    left_n = [w for w in banned_n if w in hits_n]
    check('搜 "n" 不再命中中间含 n 的词', not left_n, f"仍出现 {left_n}")
    check('搜 "n" 仍有前缀命中', len(hits_n) > 0, f"命中 {len(hits_n)} 个")

    # 精确命中仍排最前
    exact = my_hits("norm")
    check("精确命中排第一（norm）", bool(exact) and exact[0] == "norm", f"首项 {exact[:3]}")

    d = dict_hits("no")
    check('词典搜 "no" 首项是 no', bool(d) and d[0] == "no", f"首项 {d[:3]}")
    check(
        '词典搜 "no" 全是 no 开头',
        all(w.lower().startswith("no") for w in d),
        f"例外 {[w for w in d if not w.lower().startswith('no')][:5]}",
    )
    has_added = (
        c.execute(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='user_added_words'"
        ).fetchone()[0]
        > 0
    )
    if has_added:
        check("自加词前缀查询可执行", isinstance(added_hits("no"), list))
    else:
        # 自加词表是 App 首次启动时补建的，assets 里的词典库没有；查询语句本身
        # 与 searchMyWords 同构，已在源码层核对。
        print("  SKIP  自加词前缀查询（assets 库无 user_added_words，运行时建表）")


def order_checks(c):
    asc = c.execute("SELECT no, word_key FROM my_words ORDER BY no ASC LIMIT 1").fetchone()
    desc = c.execute("SELECT no, word_key FROM my_words ORDER BY no DESC LIMIT 1").fetchone()
    check("原序首行 = 1 号 transmit", asc[0] == 1 and asc[1] == "transmit", f"{asc}")
    check("添加时间首行 = 820 号", desc[0] == 820, f"{desc}")
    cnt = c.execute("SELECT COUNT(*) FROM my_words").fetchone()[0]
    check("820 词序号连续 1..820", cnt == 820 and desc[0] == 820, f"count={cnt}")


# ---- 源码层 -------------------------------------------------------------

def dao_checks(src):
    sql_sites = re.findall(r"\['([^']*)', q, '\$q%', limit\]", src)
    check("三处搜索参数只剩前缀写法", len(sql_sites) == 3 and all(s == "$q%" for s in sql_sites), f"{sql_sites}")
    check("word_dao 里不再有 %q%", "%$q%" not in src)


def study_checks(src, flow):
    check("卡片里有「不认识」按钮", "不认识" in src)
    # 按钮只在未答对时显示
    idx = src.find("_tapUnknown")
    check("「不认识」在答对后隐藏", "if (!_progress.resolved) ...[" in src, "")
    check("「不认识」按下标错并落库", "_dao.answer(card: card, correct: false)" in src)
    check("「不认识」去详情页", "_openDetailThenNext(card)" in src)
    check("首次记错计数 +1", "_firstWrong++" in src)
    check(
        "已记过错不重复记（状态机返回 false）",
        "if (_progress.markUnknown())" in src and "if (resolved || recordedWrong) return false;" in flow,
    )


def words_checks(src):
    check(
        "排序是三态循环",
        "original => _OrderMode.random" in src
        and "random => _OrderMode.addedAt" in src
        and "addedAt => _OrderMode.original" in src,
    )
    check("按钮文案含「添加时间」", "'添加时间'" in src)
    check("添加时间按序号倒序", "_byAddedAt = words.reversed.toList()" in src)
    check("添加时间下自加词排最前", "final addedFirst = _order == _OrderMode.addedAt;" in src)
    check(
        "遮盖点按：有就删、没有就加",
        "if (!_revealed.remove(key)) _revealed.add(key);" in src,
    )
    check("三个列表都走 _MeaningBlock", src.count("_MeaningBlock(") >= 3)
    check("释义行只在文字上接点击", "behavior: HitTestBehavior.opaque" in src)


def version_checks():
    with open(os.path.join(APP, "pubspec.yaml"), encoding="utf-8") as f:
        pub = f.read()
    # 只要求「不低于 0.6.2」：这个脚本验的是 v0.6.2 那四条的行为，
    # 后面的版本继续沿用，不该被版本号卡住。
    m = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)", pub, re.M)
    ok = bool(m) and tuple(int(x) for x in m.groups()[:3]) >= (0, 6, 2)
    check("版本号 ≥ 0.6.2", ok, pub.splitlines()[4] if pub else "")


def main():
    if not os.path.exists(DB):
        print(f"找不到词库：{DB}")
        return 1
    c = sqlite3.connect(DB)
    print("数据层")
    prefix_search_checks(c)
    order_checks(c)

    print("源码层")
    dao_checks(read("lib/data/dao/word_dao.dart"))
    study_checks(
        read("lib/features/study/study_session_page.dart"),
        read("lib/data/study/study_flow.dart"),
    )
    words_checks(read("lib/features/words/words_page.dart"))
    version_checks()

    print(f"\n{PASS} PASS / {FAIL} FAIL")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
