#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""v0.6.1 两处改动的静态验收。

跑法：python _source/check_layout_v061.py

只做源码级断言 —— 布局效果本机无设备验不了，但「改没改到」可以确定：
1. 详情页不再有上滑触发，且 ListView 还在（内容照常滚动）
2. 学习页选项走 2×2 网格，不再是一个 for 循环竖着排
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DETAIL = os.path.join(ROOT, "app", "lib", "features", "words", "word_detail_page.dart")
STUDY = os.path.join(ROOT, "app", "lib", "features", "study", "study_session_page.dart")

checks = []


def check(name, ok, detail=""):
    checks.append((name, ok, detail))


def read(path):
    with io.open(path, encoding="utf-8") as f:
        return f.read()


detail = read(DETAIL)
study = read(STUDY)

# —— 改动 1：详情页 ——
check("详情页没有 OverscrollNotification", "OverscrollNotification" not in detail)
check("详情页不再监听 overscroll 值", "n.overscroll" not in detail)
check("「或上滑进入下一张卡」提示已删", "或上滑进入下一张卡" not in detail)
# 注释里写「v0.6.1 去掉了上滑」是可以的，界面文案里不许再有
code_lines = [l for l in detail.splitlines() if not l.strip().startswith("//")]
check("界面正文里没有「上滑」", all("上滑" not in l for l in code_lines))
check("详情页仍是 ListView（内容可滚动）", "return ListView(" in detail)
check("详情页保留 AlwaysScrollableScrollPhysics", "AlwaysScrollableScrollPhysics" in detail)
check("详情页仍有「下一个」按钮", "child: const Text('下一个')" in detail)
check("「下一个」仍调 _requestNext", "onPressed: _requestNext" in detail)
check("_requestNext 仍只做 pop（返回键行为不动）", "Navigator.of(context).pop();" in detail)
check("_leaving 去重标记还在", "_leaving" in detail)

# —— 改动 2：学习页 2×2 ——
check("学习页有 _optionGrid", "_optionGrid(" in study)
check("学习页用 IntrinsicHeight 让同行等高", "IntrinsicHeight(" in study)
check("每行两个 Expanded 平分", study.count("Expanded(child: _optionTile(i, card.options[i]))") == 1)
check("选项格最小高度 76", "BoxConstraints(minHeight: 76)" in study)
check("旧的竖向 for 循环已删", "for (var i = 0; i < card.options.length; i++) ...[" not in study)
check("选项顺序仍按 i 递增（A/B/C/D 不变）",
      "String.fromCharCode(65 + i)" in study)
check("答对/答错逻辑没动", "case OptionState.correct:" in study and "case OptionState.wrong:" in study)

# —— 版本 ——
pubspec = read(os.path.join(ROOT, "app", "pubspec.yaml"))
check("pubspec 版本 0.6.1+7", "version: 0.6.1+7" in pubspec)

fails = 0
print("v0.6.1 布局验收\n" + "-" * 46)
for name, ok, extra in checks:
    print("%s %s%s" % ("[PASS]" if ok else "[FAIL]", name, ("  " + extra) if extra else ""))
    if not ok:
        fails += 1
print("-" * 46)
print("%d/%d 通过" % (len(checks) - fails, len(checks)))
sys.exit(1 if fails else 0)
