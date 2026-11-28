# -*- coding: utf-8 -*-
"""v0.12.0 例句人工校订。

输入：_source/examples_820.json（Tatoeba 自动筛出的 192 词 / 329 句）
输出：_source/examples_820_curated.json（校订后 + 改动清单）

校订口径（用户 2026-11-27 定）：
  - 译文有病的改掉或删掉
  - 义项对不上的那条不要
  - 每词 2–3 条，不够就显有的条数，没有就「暂无例句」
  - 只改字词级错误（错字、多字、语序），不重写整句；要重写就删

`take` 词条在 dict.sqlite 里是错的（第 257 条 word='take'、释义却是
`advantage of phr. …`），本版合并成 `take advantage of`，所以这里把
take 名下的例句改挂到新 key 上。
"""
import json
import sys
from collections import Counter
from pathlib import Path

SRC = Path(__file__).resolve().parent
IN = SRC / "examples_820.json"
OUT = SRC / "examples_820_curated.json"

# 词条合并：旧 key -> 新 key（与 dict.sqlite 第 257 条的修正同步）
REKEY = {"take": "take advantage of"}

# 删：重复句、译文错到无法小改、内容不适合学习 App（堕胎 / 自杀 / 宗教民族敏感）
DELETE = {
    26,   # accuse：与 25 几乎同句（Why do you / Why are you）
    41,   # abortion：话题不适合学习例句
    68,   # attempt：自杀
    77,   # offend：与 78 重复，且「冒犯她的」错字
    108,  # explicitly：涉平台内容管制，不适合
    118,  # humid：两句合一（Another on the other hand 漏译）
    145,  # exceed：省略号 + 口语填充，不适合当例句
    150,  # hardware：两句合一
    154,  # property：两句合一，抽象长句
    157,  # referee：principle of advantage 术语生僻，句长 19 词
    203,  # coward：与 201/202 重复
    218,  # democracy：与 217 同句改写
    219,  # democracy：与 217 同句改写
    229,  # native：人名未译（Felicja / Katowice）
    235,  # flour：句长 + 译文啰嗦，已有 234
    260,  # bullet：原文语义含糊
    268,  # ceiling：与 267 只差单复数
    278,  # rot：与 277 同义重复
    290,  # mend：与 289 只差一个词
    313,  # continent：「转移的大洲」机翻错译
    316,  # ally：与 315 同句改写
    317,  # barn：「画了谷仓」歧义（paint 可指粉刷）
    326,  # prevalent：涉宗教/恐怖主义关联，敏感
}

# 改：只动错字、多字、语序、明显错译，不新增信息
FIX = {
    35: "法国现任代表是谁？",                                    # 年级/法方 → 法国
    46: "恐怖的场面让他浑身发抖。",                              # 「让了他颤抖」
    56: "他隔了很久才作答。",                                    # 「他间隔了很久」
    59: "只有一些学生理解那个方面。",                            # 「只有几个学生懂」
    61: "我们必须考虑这个项目的财务方面。",                      # 财政 → 财务
    67: "汤姆没有试图回答。",                                    # 「不企图回应」
    72: "增加教育投入将刺激经济增长。",                          # 「更多投资在教育的钱」
    75: "我们正计划改进生产流程。",                              # 「算计着改革」
    113: "你应该学会克制自己。",                                 # 原文 restrain yourself
    131: "她充分利用在伦敦逗留的时间来提高英语。",              # 原文是「逗留期间」
    132: "她帮我收拾行李箱。",                                   # 「打包我的手提箱」
    147: "没有意志力是最大的障碍。",                             # will = 意志
    159: "这艘船没有配备雷达。",                                 # 「没有雷达装备」
    175: "没有什么能阻挡我对自由的向往。",                       # 逗号断句
    178: "温度计显示十度。",                                     # 「指向十度」
    186: "大阪是日本的商业中心。",                               # 大坂 → 大阪
    192: "她不得不接受自己的命运。",                             # 「她该接受」
    197: "因为超级联赛中所有球队都很强，净胜球通常很小。",       # 甲级 → 超级
    230: "本地中国人和外国人一起改变着上海的文化。",             # 原文与译文不符
    233: "我们在教堂见的面。",                                   # 「我们在教堂里遇到」
    238: "放张唱片到音响上。",                                   # 「往立体声音响上放一枚唱片」
    240: "吉姆害怕体力劳动。",                                   # 「怕了体力劳动了」
    241: "劳动不仅是一种需要，也是一种快乐。",                   # 「而还是一种愉快」
    247: "汤姆把玛丽当奴隶一样对待。",                           # 冗余
    249: "她信任他是件鲁莽的事。",                               # 「比较鲁莽的相信了他」
    255: "难民从全国各地涌入。",                                 # 「从整个国家涌来」
    259: "那只狗像子弹一样冲了出去。",                           # 「像子弹飞走了」
    270: "赤手空拳抓野兔并不容易。",                             # 空手赤拳 → 赤手空拳
    276: "她鄙视那个男孩。",                                     # She → 他
    281: "编程语言 Java 用途很广。",                             # 「非常多用途的」
    291: "修一下厨房的水龙头。",                                 # 祈使句补语气
    292: "三个男人在门廊上等你。",                               # 「在门廊上在等你」
    293: "恐怖的场面让他浑身发抖。",                             # 同 46
    296: "也许这只是巧合。",                                     # 「一场巧合」
    301: "埃翁多语是喀麦隆埃翁多部落所说的语言。",               # 客麦隆 → 喀麦隆
}


def main():
    raw = json.loads(IN.read_text(encoding="utf-8"))
    examples = raw["examples"]

    idx = 0
    out = {}
    edits = []
    dropped = []
    for word, items in examples.items():
        key = REKEY.get(word, word)
        kept = []
        for s in items:
            idx += 1
            if idx in DELETE:
                dropped.append({"id": idx, "word": word, "en": s["en"], "zh": s["zh"]})
                continue
            zh = FIX.get(idx, s["zh"])
            if idx in FIX:
                edits.append(
                    {"id": idx, "word": word, "en": s["en"], "zh_old": s["zh"], "zh_new": zh}
                )
            kept.append(
                {
                    "en": s["en"],
                    "zh": zh,
                    "source": "Tatoeba",
                    "license": "CC-BY 2.0 FR",
                    "en_id": s["en_id"],
                    "zh_id": s["zh_id"],
                }
            )
        if kept:
            out[key] = kept

    assert idx == 329, idx
    assert len(edits) == len(FIX), (len(edits), len(FIX))
    assert len(dropped) == len(DELETE), (len(dropped), len(DELETE))

    dist = Counter(len(v) for v in out.values())
    stats = {
        "words_with_examples": len(out),
        "words_removed_by_review": 192 - len(out),
        "sentences": sum(len(v) for v in out.values()),
        "sentences_deleted": len(dropped),
        "sentences_edited": len(edits),
        "dist": {str(k): dist.get(k, 0) for k in (1, 2, 3)},
    }
    payload = {
        "source": "Tatoeba",
        "license": "CC-BY 2.0 FR",
        "url": "https://tatoeba.org",
        "reviewed": "2026-11-27 人工逐条过一遍（329 句）",
        "stats": stats,
        "examples": out,
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False, indent=1))
    print(f"写入 {OUT}（{OUT.stat().st_size / 1024:.0f} KB）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
