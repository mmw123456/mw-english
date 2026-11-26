# -*- coding: utf-8 -*-
"""修复 PDF 断词，生成最终 820 词表 words_final.json。"""
import json
import re

entries = json.load(open("words_merged.json", encoding="utf-8"))

# PDF 排版把单词切断的 3 条：word 尾部缺字母，字母跑到释义开头
MANUAL = {
    312: ("semiconductor", "n. 半导体"),
    393: ("once (and) for all", "phr. 只此一次，彻底地"),
    430: ("compassionate", "adj. 有同情心的；基于同情的"),
}

for e in entries:
    if e["no"] in MANUAL:
        w, m = MANUAL[e["no"]]
        e["word"] = w
        e["meaning"] = m
        e["word_repaired"] = True
        e["ecdict_translation"] = ""
        e["truncated"] = False

with open("words_final.json", "w", encoding="utf-8") as f:
    json.dump(entries, f, ensure_ascii=False, indent=1)

print("修正:", [e["word"] for e in entries if e.get("word_repaired")])
print("总条数:", len(entries))
print("序号连续:", [e["no"] for e in entries] == list(range(1, 821)))
print("词组条数:", sum(1 for e in entries if " " in e["word"]))
print("仍截断:", sum(e.get("truncated") for e in entries))
