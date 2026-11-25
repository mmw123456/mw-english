# -*- coding: utf-8 -*-
"""woff2 -> ttf，输出到 Flutter assets/fonts。

说明：fontsource 的 chinese-simplified 分片已包含全部 ASCII（实测 216 个 latin
字符全在其中），所以无需合并 latin 分片。
"""
import os

from fontTools.ttLib import TTFont

OUT = r"D:\AI项目工程\BackWord-App\app\assets\fonts"
os.makedirs(OUT, exist_ok=True)

for w, name in (("400", "Regular"), ("700", "Bold")):
    f = TTFont(f"noto-chinese-simplified-{w}.woff2")
    f.flavor = None
    dst = os.path.join(OUT, f"NotoSansSC-{name}.ttf")
    f.save(dst)
    cm = f.getBestCmap()
    size = os.path.getsize(dst) / 1024 / 1024
    print(f"{name}: 字符数 {len(cm)}, {size:.1f} MB -> {dst}")
    print(f"  字体名 {f['name'].getDebugName(1)} / {f['name'].getDebugName(2)}")
    # 抽查常用字覆盖
    sample = "的一是不了人我在有他这为之大来以个中上们到说国和地也子时道出而要于就下得可你年生"
    miss = [c for c in sample if ord(c) not in cm]
    print(f"  常用字抽查缺失: {len(miss)} {''.join(miss)}")
