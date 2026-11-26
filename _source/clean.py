# -*- coding: utf-8 -*-
"""清洗 PDF 抽取结果：修复中文被换行拆断产生的空格，输出 words_clean.json。"""
import json
import re

CJK = r"\u4e00-\u9fa5\u3000-\u303f\uff00-\uffef"

with open("words_raw.json", encoding="utf-8") as f:
    entries = json.load(f)


def clean_meaning(text: str) -> str:
    s = text
    # 1. 中文/全角标点之间的空白（换行拆断）直接删掉
    s = re.sub(rf"(?<=[{CJK}])\s+(?=[{CJK}])", "", s)
    # 2. 全角标点后多余空格
    s = re.sub(r"(?<=[，；、。：（）【】])\s+", "", s)
    # 3. 连续空格归一
    s = re.sub(r"[ \t]{2,}", " ", s)
    return s.strip()


def clean_word(text: str) -> str:
    return text.strip().strip(".,;:").strip()


for e in entries:
    e["word"] = clean_word(e["word"])
    e["meaning"] = clean_meaning(e["meaning"])

# 记录截断标记：以 … 或 ... 结尾表示原文被截断
for e in entries:
    e["truncated"] = e["meaning"].rstrip().endswith(("…", "..."))

with open("words_clean.json", "w", encoding="utf-8") as f:
    json.dump(entries, f, ensure_ascii=False, indent=1)

fixed = [e for e in entries if e["no"] in (3, 34, 820)]
print("--- 清洗对照 ---")
for e in fixed:
    print(e["no"], "|", e["word"], "|", e["meaning"])

print("\n仍含中文内空格的行数:",
      sum(1 for e in entries if re.search(rf"[{CJK}]\s+[{CJK}]", e["meaning"])))
print("截断条目:", sum(e["truncated"] for e in entries), "/", len(entries))
print("释义最短长度:", min(len(e["meaning"]) for e in entries))
print("单词含空格(词组)条数:", sum(1 for e in entries if " " in e["word"]))
print("单词含大写:", sum(1 for e in entries if e["word"] != e["word"].lower()))
