# -*- coding: utf-8 -*-
"""检查词根表对 820 词的实际覆盖率，判断规则松紧。"""
import json
import re
from roots import ROOTS

PREFIX = sorted([r for r in ROOTS if r[2] == "prefix"], key=lambda x: -len(x[0]))
ROOT = sorted([r for r in ROOTS if r[2] == "root"], key=lambda x: -len(x[0]))

final = json.load(open("words_final.json", encoding="utf-8"))


def split(word: str):
    """返回 [(kind, root, meaning)] 或 None。

    规则（宁缺勿滥，只有前缀不算拆解）：
    - 只允许剥一个前缀，剥掉后残余长度 >= 4
    - 剥完前缀后，剩余部分必须以某个词根开头，残余长度 >= 3
    - 至少命中 1 个词根；只有一个前缀、说不出词干含义的，判为拆不出
    - 整个词就是词根本身（词根占比 > 70%）时不拆，等于没信息量
    """
    w = word.lower()
    if not re.fullmatch(r"[a-z]{4,}", w):
        return None  # 词组、带连字符、过短的词不拆

    def match_root(tail: str):
        for root, meaning, _ in ROOT:
            if tail.startswith(root) and len(tail) - len(root) >= 3:
                return root, meaning
        return None

    # 方案 A：前缀 + 词根
    for prefix, p_meaning, _ in PREFIX:
        if w.startswith(prefix) and len(w) - len(prefix) >= 4:
            got = match_root(w[len(prefix):])
            if got:
                root, r_meaning = got
                covered = len(prefix) + len(root)
                if covered > len(w) * 0.7:
                    return None
                return [("prefix", prefix, p_meaning), ("root", root, r_meaning)]

    # 方案 B：词根直接开头（无前缀）
    got = match_root(w)
    if got:
        root, r_meaning = got
        if len(root) > len(w) * 0.7:
            return None
        return [("root", root, r_meaning)]

    return None


ok = 0
samples = []
for e in final:
    h = split(e["word"])
    if h:
        ok += 1
        if len(samples) < 25:
            samples.append((e["word"], " + ".join(f"{r}({m})" for _, r, m in h)))

print(f"820 词中可拆词根：{ok} 条（{ok/820*100:.1f}%）")
print(f"词根表规模：前缀 {len(PREFIX)} / 词根 {len(ROOT)} / 合计 {len(ROOTS)}")
print("\n样例：")
for w, s in samples:
    print(f"  {w:24s} {s}")
