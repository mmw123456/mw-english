"""校验 v0.6.0 四选一的干扰项在真实词库上是否凑得齐、质量如何。

只跑数据，不跑 Flutter：把 Dart 里的 shortGloss / cleanOption / isDerived /
editDistance / 取候选顺序原样搬过来，对 820 词逐词生成一遍选项。

判据（和 app 里的 ChoiceOptions.build 一致）：
  1) 四个选项，正确项只出现一次
  2) 选项互不重复
  3) 干扰项释义不与正确释义重叠（去掉词性/域标签后按分句比较）
  4) 干扰项里不能出现拉丁字母（「xx 的过去式」等于送答案）
"""

import re
import sqlite3
from collections import defaultdict

DB = "assets/db/dict.sqlite"

DOMAIN = re.compile(r"^\[[^\]]{0,6}\]\s*")
POS = re.compile(r"^(n|v|vt|vi|adj|a|ad|adv|prep|conj|pron|num|art|int|aux)\s*\.\s*", re.I)
NOISE = re.compile(r"[\s,，、.。·…（）()\[\]【】/／]")
LATIN = re.compile(r"[A-Za-z]")


def clean_option(raw: str) -> str:
    t = raw.strip()
    while DOMAIN.match(t):
        t = DOMAIN.sub("", t, count=1)
    t = POS.sub("", t, count=1)
    return t.strip()


def short_gloss(raw: str) -> str:
    first = raw.split("\n")[0].strip()
    if not first:
        return ""
    cut = re.split(r"[；;]", first)[0].strip()
    text = clean_option(cut or first)
    return text[:26] + "…" if len(text) > 26 else text


def cores(text: str):
    out = []
    for seg in re.split(r"[,，、；;]", text):
        core = NOISE.sub("", POS.sub("", seg))
        if core:
            out.append(core)
    return out


def overlaps(a: str, b: str) -> bool:
    for x in cores(a):
        for y in cores(b):
            if x in y or y in x:
                return True
    return False


def is_derived(a: str, b: str) -> bool:
    if a == b:
        return True
    short, long_ = (a, b) if len(a) <= len(b) else (b, a)
    return long_.startswith(short) and len(long_) - len(short) <= 4


def distance(a: str, b: str, cap: int = 3) -> int:
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


def build(correct, near_glosses, fallback):
    picked, used = [], {correct}
    for src in (near_glosses, fallback):
        for g in src:
            if len(picked) >= 3:
                break
            g = g.strip()
            if not g or LATIN.search(g):
                continue
            if overlaps(correct, g) or g in used:
                continue
            used.add(g)
            picked.append(g)
    return picked


def near_candidates(key, buckets):
    near = []
    if len(key) < 3:
        return near
    for w, g in buckets.get(key[0], []):
        if w == key or abs(len(w) - len(key)) > 2 or is_derived(key, w):
            continue
        d = distance(key, w)
        if 0 < d <= 3:
            near.append((d, w, g))
    near.sort()
    return near


def main() -> None:
    c = sqlite3.connect(DB)

    buckets = defaultdict(list)
    for word, tr in c.execute("SELECT word, translation FROM words WHERE translation <> ''"):
        w = (word or "").strip().lower()
        if not w or " " in w:
            continue
        g = short_gloss(tr or "")
        if g:
            buckets[w[0]].append((w, g))

    batch = []
    for pdf, ec in c.execute("SELECT meaning_pdf, meaning_ecdict FROM my_words ORDER BY no"):
        g = short_gloss((pdf or "").strip() or (ec or "").strip())
        if g:
            batch.append(g)

    rows = c.execute(
        "SELECT no, word_key, meaning_pdf, meaning_ecdict FROM my_words ORDER BY no"
    ).fetchall()

    fail, empty_meaning, near_hits = [], [], []
    for no, key, pdf, ec in rows:
        correct = short_gloss((pdf or "").strip() or (ec or "").strip())
        if not correct:
            empty_meaning.append((no, key))
            continue

        near = near_candidates(key, buckets)
        near_g = [g for _, _, g in near]
        picked = build(correct, near_g, batch)
        if len(picked) < 3:
            fail.append((no, key, correct, len(picked)))
            continue
        assert (picked + [correct]).count(correct) == 1
        assert len(set(picked + [correct])) == 4
        near_hits.append(sum(1 for g in picked if g in set(near_g)))

    total = len(rows)
    print(f"820 词检查：{total} 条")
    print(f"  释义为空：{len(empty_meaning)} {empty_meaning[:3]}")
    print(f"  选项凑不齐 4 个：{len(fail)} {fail[:3]}")
    print(f"  形近词个数分布：{ {k: near_hits.count(k) for k in sorted(set(near_hits))} }")

    print("\n抽样（正确项 ★，括号里是形近词原文）：")
    for no, key, pdf, ec in rows:
        if no not in (1, 30, 155, 300, 455, 620, 700, 780, 800, 820):
            continue
        correct = short_gloss((pdf or "").strip() or (ec or "").strip())
        near = near_candidates(key, buckets)
        picked = build(correct, [g for _, _, g in near], batch)
        src = [w for _, w, g in near if g in picked]
        print(f"  {no:3d} {key:14s} ★ {correct}")
        print(f"      {' | '.join(picked)}    ← {src}")


if __name__ == "__main__":
    main()
