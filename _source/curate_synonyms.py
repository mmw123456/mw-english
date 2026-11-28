#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""对「模型硬凑」的近义词做人工定稿。

背景：820 词里有 16 个具体名词/专业词（suicide、persimmon、mercury…）本身就没有
真正意义上的近义词，模型为了凑数给了上义词（persimmon → fruit）或词形变化
（laundry → laundering），这类不能上界面。

处理原则：**宁可没有，不硬凑**（和词根白名单同一条标准）。
- 真近义 → 保留，辨析自己写；
- 上义词 / 相关词 / 词形变化 → 删掉；
- 删完为空 → 该词近义词区块整块不显示。

用法：python _source/curate_synonyms.py
"""
import json
import os
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "db", "dict.sqlite")
SYN_JSON = os.path.join(ROOT, "data", "synonyms.json")
OUT_MD = os.path.join(ROOT, "data", "synonyms_preview.md")

# 人工定稿。空列表 = 这个词不显示近义词区块。
OVERRIDES = {
    "suicide": [],
    "semiconductor": [],
    "persimmon": [],
    "latitude": [],
    "pentatonic": [],
    "nasal": [],
    "influenza": [
        ("flu", "口语简称，influenza 是正式医学说法"),
    ],
    "meditating": [
        ("muse", "文学色彩更浓，指若有所思地沉思"),
        ("ruminate", "强调反复琢磨同一件事"),
        ("contemplate", "更正式，偏「注视并思考」"),
    ],
    "meteor": [
        ("fireball", "特指特别明亮的大流星，meteor 是通称"),
    ],
    "armpit": [
        ("axilla", "解剖学正式说法，医学语境用"),
    ],
    "democracy": [
        ("republic", "共和政体，强调无君主；democracy 强调人民主权"),
    ],
    "oval": [
        ("elliptical", "严格椭圆，数学语境；oval 更口语、偏蛋形"),
        ("oblong", "长椭圆形，比 oval 更狭长"),
    ],
    "laundry": [
        ("launderette", "英式说法，自助洗衣店"),
        ("laundromat", "美式说法，自助洗衣店"),
    ],
    "mercury": [
        ("quicksilver", "汞的旧称，文学色彩浓"),
    ],
    "continental": [
        ("mainland", "大陆的、本土的，多修饰地理名词"),
        ("inland", "内陆的，强调远离海岸"),
    ],
    "molecular": [
        ("atomic", "原子的，层级更小，常与 molecular 对比使用"),
    ],
}


def main():
    if not os.path.exists(SYN_JSON):
        print("缺少 data/synonyms.json，先跑 gen_synonyms.py", file=sys.stderr)
        return 1

    data = json.load(open(SYN_JSON, encoding="utf-8"))
    for key, items in OVERRIDES.items():
        if items:
            data[key] = [{"w": w, "dist": d} for w, d in items]
        else:
            data.pop(key, None)

    with open(SYN_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)

    con = sqlite3.connect(DB)
    words = con.execute("SELECT word_key, word FROM my_words ORDER BY no").fetchall()
    con.close()

    empty = [w for k, w in words if not data.get(k)]
    lines = [
        "# 近义词预览（已人工定稿）",
        "",
        f"- 源词：{len(words)}　有近义词：{len(data)}　无（区块不显示）：{len(empty)}",
        f"- 总条目：{sum(len(v) for v in data.values())}",
        "- 每词最多 4 个；近义词必须在 43,350 词裁剪词库内",
        f"- 人工定稿 {len(OVERRIDES)} 词（具体名词/专业词，模型原答案有上义词或词形变化）",
        "",
        "## 明细",
        "",
        "| # | 单词 | 近义词 | 辨析 |",
        "|---|---|---|---|",
    ]
    for i, (key, word) in enumerate(words, 1):
        syns = data.get(key)
        if not syns:
            lines.append(f"| {i} | {word} | — | （无，区块不显示）|")
            continue
        for j, s in enumerate(syns):
            lines.append(
                f"| {i if j == 0 else ''} | {word if j == 0 else ''} | {s['w']} | {s['dist']} |"
            )
    if empty:
        lines += ["", "## 无近义词的词", "", "、".join(empty)]
    lines.append("")
    with open(OUT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"定稿完成：{len(data)} 词有近义词，{len(empty)} 词无（{'、'.join(empty)}）")
    print(f"总条目 {sum(len(v) for v in data.values())}，预览：{OUT_MD}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
