"""v0.6.8 验收：学习卡片页换浅色纸底，仍是液态玻璃。

三条主线：
1. 底色与字色：纸 #F3F2EE + 墨 #0B0C10，次要字 #6B6E78，对比度达标
2. 玻璃参数：白 tint 4–6%、迎光 1px 亮边、0 10 32 / .20 投影，选中加深
3. 影响面与行为：只改学习页 + 玻璃主题；2×2 / 500ms / 点错留卡 / 不认识 / 弹簧全在

跑法：python _source/check_glass_v068.py
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = "a9a10b6"  # v0.6.7 提交

THEME = os.path.join(ROOT, "app", "lib", "app", "theme", "liquid_glass_preview_theme.dart")
PAGE = os.path.join(ROOT, "app", "lib", "features", "study", "study_session_page.dart")

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


def git(*args):
    return subprocess.run(
        ["git", "-c", "core.quotepath=false", *args],
        cwd=ROOT, capture_output=True, text=True,
    ).stdout


def lum(hex_color):
    h = hex_color.lstrip("#")
    rgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]

    def f(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * f(rgb[0]) + 0.7152 * f(rgb[1]) + 0.0722 * f(rgb[2])


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


theme = read(THEME)
page = read(PAGE)


def color_checks():
    print("[纸底与字色]")
    check("纸底色值是 #F3F2EE", "paper = Color(0xFFF3F2EE)" in theme)
    check("墨色值仍是 #0B0C10", "ink = Color(0xFF0B0C10)" in theme)
    check("正文色指向墨", "textPrimary = ink" in theme)
    check("次要字是 #6B6E78", "textSecondary = Color(0xFF6B6E78)" in theme)
    check("主题亮度改为 light", "brightness: Brightness.light" in theme)
    check("scaffold 底色用纸", "scaffoldBackgroundColor: LiquidGlass.paper" in theme)
    check("顶栏底色用纸、前景用墨",
          "backgroundColor: LiquidGlass.paper" in theme and
          "foregroundColor: LiquidGlass.ink" in theme)
    check("顶栏标题 16 / w700 / 墨",
          "titleTextStyle" in theme and "fontSize: 16" in theme and
          "color: LiquidGlass.ink" in theme)
    check("学习页 scaffold 底色用纸", "backgroundColor: LiquidGlass.paper" in page)
    check("学习页不再拿墨当底色", "backgroundColor: LiquidGlass.ink" not in page)
    check("进度条轨道不再手写深色", "Color(0xFF23242A)" not in page)

    ratio_ink = contrast("#0B0C10", "#F3F2EE")
    ratio_sec = contrast("#6B6E78", "#F3F2EE")
    check(f"墨在纸上 {ratio_ink:.1f}:1 ≥ 4.5", ratio_ink >= 4.5)
    check(f"次要字在纸上 {ratio_sec:.2f}:1 ≥ 4.5", ratio_sec >= 4.5)


def glass_checks():
    print("[玻璃参数]")
    tint = re.search(r"static const double tint = ([\d.]+);", theme)
    check("白 tint 仍在 4%–6%", tint and 0.04 <= float(tint.group(1)) <= 0.06,
          tint.group(1) if tint else "没找到")
    check("选中 tint 仍是 36%", "tintSelected = 0.36" in theme)
    check("bevel 仍是 26", "bevel = 26" in theme)
    shadow = re.search(
        r"shadow = <BoxShadow>\[\s*BoxShadow\(\s*color: Color\(0x([0-9A-Fa-f]{8})\),"
        r"\s*offset: Offset\(0, 10\),\s*blurRadius: 32",
        theme,
    )
    ok = False
    alpha = None
    if shadow:
        alpha = int(shadow.group(1)[:2], 16) / 255
        ok = abs(alpha - 0.20) <= 0.01
    check("常态投影 0 10 32 / .20", ok, f"alpha={alpha}" if alpha else "没匹配到")
    check("选中态有更深的投影", "shadowSelected" in theme and
          "shadow = LiquidGlass.shadowSelected" in page)
    check("迎光亮边仍是方向渐变（不是整圈白边）", "_BevelPainter" in theme and
          "LinearGradient" in theme and "stroke" in theme)
    check("玻璃仍无色（点错才上粉）", "tintColor ?? Colors.white" in theme)
    check("氛围五色都在",
          all(c in theme for c in ("0xFFFF5A1F", "0xFFFF2E7E", "0xFF2BD9A0",
                                   "0xFF8B5CFF", "0xFF2E4BFF")))
    check("氛围层底色是纸", "ColoredBox(color: LiquidGlass.paper)" in theme)


def behavior_checks():
    print("[行为原样]")
    check("2×2 四宫格还在", "_optionGrid" in page and "IntrinsicHeight" in page)
    check("A/B/C/D 还在", "String.fromCharCode(65 + widget.index)" in page)
    check("500ms 自动走还在", "milliseconds: 500" in page)
    check("点错留卡还在", "if (tap == CardTap.wrong) {" in page and
          "return;" in page)
    check("「不认识」还在", "_tapUnknown" in page and "不认识" in page)
    check("答对直走在数据层纯函数里", "exitAfterCorrect" in page)
    check("弹簧参数没动", "mass: 0.8" in theme and "stiffness: 300" in theme and
          "damping: 24" in theme)
    check("按压比例没动", "pressScale = 0.96" in theme)
    check("入场 stagger 没动", "50 + i * 35" in page)
    check("触觉没动", "HapticFeedback" in page)


def scope_checks():
    print("[影响面]")
    changed = git("diff", "--name-only", BASE).splitlines()
    untracked = git("ls-files", "--others", "--exclude-standard").splitlines()
    files = [f for f in changed + untracked if f]

    allowed = {
        "app/lib/app/theme/liquid_glass_preview_theme.dart",
        "app/lib/features/study/study_session_page.dart",
        "app/pubspec.yaml",
        "app/pubspec.lock",
        "app/test/liquid_glass_test.dart",
        "_source/check_glass_v068.py",
        "_source/check_glass_v066.py",
        "_source/release_notes_v068.md",
        "项目日志.md",
    }
    bad = [f for f in files if f not in allowed]
    check("lib/ 只改学习页 + 玻璃主题", not any(
        f.startswith("app/lib/") and f not in allowed for f in files),
        str([f for f in files if f.startswith("app/lib/")]))
    check("数据层零改动", not any(f.startswith("app/lib/data/") for f in files))
    check("app.dart / 外壳零改动",
          "app/lib/app/app.dart" not in files and
          not any("features/home" in f or "features/words" in f or
                  "features/profile" in f for f in files))
    check("全局主题零改动", "app/lib/app/theme/app_theme.dart" not in files and
          "app/lib/app/theme/app_colors.dart" not in files)
    check("M3 预览主题保留未动", "app/lib/app/theme/study_preview_theme.dart" not in files)
    if bad:
        print("    越界文件：" + ", ".join(bad))


def version_checks():
    print("[版本]")
    pub = read(os.path.join(ROOT, "app", "pubspec.yaml"))
    check("版本号 0.6.8+13", "version: 0.6.8+13" in pub)
    check("没有倒挂回 0.6.5/0.6.6", "0.6.5+" not in pub and "0.6.6+" not in pub)


color_checks()
glass_checks()
behavior_checks()
scope_checks()
version_checks()

print()
print(f"{passed}/{passed + failed} 通过")
raise SystemExit(0 if failed == 0 else 1)
