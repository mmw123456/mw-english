"""v0.6.9 验收：玻璃洗干净（磨砂/白 tint 归零+氛围变浓+顶部胶囊条）。

四条主线：
1. 玻璃参数：磨砂 0–2px、白 tint 0–2%，选中 36% / 点错粉 / 投影 .20 与 .28 不动
2. 氛围：五色透明度 18%–25%、24s 慢漂移（20–30s 区间）、开「移除动画」时静止
3. 对比：纸上正文 ≥4.5:1，且压在每支氛围色 25% 峰值上仍 ≥4.5:1
4. 顶栏：悬浮胶囊（X + 进度 + 书本）+ 2px 进度线 + 两颗标签胶囊；行为一行不动

跑法：python _source/check_glass_v069.py
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = "c1f7e90"  # v0.6.8 提交

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


# ---- 颜色：按 Flutter 的 sRGB 逐通道 alpha 合成，再算 WCAG 对比 ----

def rgb(hex_color):
    h = hex_color.lstrip("#")
    if len(h) == 8:  # AARRGGBB
        h = h[2:]
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def over(fg_hex, bg_rgb, alpha=None):
    fg = rgb(fg_hex)
    a = alpha if alpha is not None else (
        int(fg_hex.lstrip("#")[0:2], 16) / 255 if len(fg_hex.lstrip("#")) == 8 else 1.0
    )
    return [fg[i] * a + bg_rgb[i] * (1 - a) for i in range(3)]


def lum(c):
    def f(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def hexstr(c):
    return "#" + "".join(f"{round(v):02X}" for v in c)


theme = read(THEME)
page = read(PAGE)

PAPER = "#F3F2EE"
INK = "#0B0C10"
AURA = ["#FF5A1F", "#FF2E7E", "#2BD9A0", "#8B5CFF", "#2E4BFF"]
AURA_TOKENS = ["0xFF" + c[1:] for c in AURA]


def num(pattern, src=theme):
    m = re.search(pattern, src)
    return float(m.group(1)) if m else None


def glass_checks():
    print("[玻璃洗干净]")
    tint = num(r"static const double tint = ([\d.]+);")
    blur = num(r"static const double blur = ([\d.]+);")
    check("白 tint 0–2%（不再整块上底色）",
          tint is not None and 0 <= tint <= 0.02, f"tint={tint}")
    check("磨砂 0–2px（v0.6.8 是 6px）",
          blur is not None and 0 <= blur <= 2, f"blur={blur}")
    check("GlassSurface 默认就是这两个值",
          "this.tintAlpha = LiquidGlass.tint" in theme and
          "this.blur = LiquidGlass.blur" in theme)
    check("磨砂为 0 时不套 BackdropFilter（省 saveLayer）",
          "if (blur > 0.05)" in theme and "BackdropFilter(" in theme)
    check("选中 tint 仍 36%", "tintSelected = 0.36" in theme)
    check("点错仍是那支粉", "wrongPink = Color(0xFFFF2E7E)" in theme)
    check("bevel 仍 26", "bevel = 26" in theme)
    check("弹簧参数没动",
          "mass: 0.8" in theme and "stiffness: 300" in theme and "damping: 24" in theme)
    check("按压比例没动", "pressScale = 0.96" in theme)
    check("投影只画在形状外面（自绘 _GlassShadowPainter，不用 boxShadow）",
          "_GlassShadowPainter" in theme and "boxShadow:" not in theme)
    check("阴影 sigma 换算与 BoxShadow 一致", "0.57735" in theme)
    check("迎光亮边仍是方向渐变（不是整圈白边）",
          "_BevelPainter" in theme and "LinearGradient" in theme)

    shadow = re.search(
        r"shadow = <BoxShadow>\[\s*BoxShadow\(\s*color: Color\(0x([0-9A-Fa-f]{8})\),"
        r"\s*offset: Offset\(0, 10\),\s*blurRadius: 32", theme)
    alpha = int(shadow.group(1)[:2], 16) / 255 if shadow else None
    check("常态投影仍是 0 10 32 / .20",
          alpha is not None and abs(alpha - 0.20) <= 0.01, f"alpha={alpha}")
    sel = re.search(
        r"shadowSelected = <BoxShadow>\[\s*BoxShadow\(\s*color: Color\(0x([0-9A-Fa-f]{8})\),"
        r"\s*offset: Offset\(0, 12\),\s*blurRadius: 34", theme)
    sel_alpha = int(sel.group(1)[:2], 16) / 255 if sel else None
    check("选中投影仍是 0 12 34 / .28",
          sel_alpha is not None and abs(sel_alpha - 0.28) <= 0.01, f"alpha={sel_alpha}")


def aura_checks():
    print("[氛围五色 + 漂移]")
    check("五支色没换", all(c in theme for c in AURA_TOKENS))
    opacities = [float(x) for x in re.findall(r"opacity: (0\.\d+),", theme)]
    check("五团光都写死了透明度", len(opacities) == 5, str(opacities))
    check(f"透明度落在 18%–25%（{opacities}）",
          len(opacities) == 5 and all(0.18 <= o <= 0.25 for o in opacities))

    secs = num(r"auraDrift = Duration\(seconds: (\d+)\)")
    check(f"漂移周期 20–30s（{secs}s）", secs is not None and 20 <= secs <= 30)
    check("来回缓动：repeat(reverse: true) + easeInOutSine",
          "repeat(reverse: true)" in theme and "Curves.easeInOutSine" in theme)
    check("五团各自相位 / 幅度（不是整体在晃）",
          theme.count("phase:") >= 5 and theme.count("drift: const Offset") >= 5)
    check("系统「移除动画」时静止",
          "disableAnimations" in theme and "_c.value = 0" in theme)
    check("氛围层仍是纸底 + 五团（玻璃的底片）",
          "ColoredBox(color: LiquidGlass.paper)" in theme)


def contrast_checks():
    print("[对比度：按最差叠色实测]")
    paper = rgb(PAPER)

    # 次要字是墨 70%（alpha 形式），正文是不透明墨。
    sec_m = re.search(r"textSecondary = Color\(0x([0-9A-F]{2})0B0C10\)", theme)
    sec_a = sec_m.group(1) if sec_m else None
    sec_alpha = int(sec_a, 16) / 255 if sec_a else None
    check("次要字用 alpha 形式跟底走（墨 70%）",
          sec_a is not None and abs(sec_alpha - 0.70) <= 0.02, f"alpha={sec_alpha}")

    primary_paper = contrast(rgb(INK), paper)
    sec_on_paper = contrast(over("#B30B0C10", paper), paper)
    check(f"墨在纸上 {primary_paper:.1f}:1 ≥ 4.5", primary_paper >= 4.5)
    check(f"次要字在纸上 {sec_on_paper:.2f}:1 ≥ 4.5", sec_on_paper >= 4.5)

    worst_p = worst_s = 99.0
    worst_p_name = worst_s_name = ""
    for c in AURA:
        bg = over(c, paper, 0.25)          # 光圈 25% 峰值
        bg = over("#FFFFFF", bg, 0.02)     # 玻璃 2% 白 tint
        rp = contrast(rgb(INK), bg)
        rs = contrast(over("#B30B0C10", bg), bg)
        print(f"        {c} → 底 {hexstr(bg)}  墨 {rp:.2f}:1  次要 {rs:.2f}:1")
        if rp < worst_p:
            worst_p, worst_p_name = rp, c
        if rs < worst_s:
            worst_s, worst_s_name = rs, c
    check(f"墨压在最浓氛围上最差 {worst_p:.2f}:1（{worst_p_name}）≥ 4.5",
          worst_p >= 4.5)
    check(f"次要字压在最浓氛围上最差 {worst_s:.2f}:1（{worst_s_name}）≥ 4.5",
          worst_s >= 4.5)


def header_checks():
    print("[顶部胶囊条]")
    check("学习页不再有 AppBar", "appBar:" not in page and "AppBar(" not in page)
    check("换成悬浮玻璃胶囊 StudyTopCapsule",
          "class StudyTopCapsule" in page and "StudyTopCapsule(" in page)
    check("X 在胶囊里", "_CapsuleButton" in page and "Icons.close_rounded" in page)
    check("书本图标在胶囊里", "Icons.menu_book_outlined" in page)
    check("胶囊是完整胶囊形（radius 999）", "radius: 999" in page)
    check("胶囊浮在纸上：用常态 .20 投影（GlassSurface 默认阴影，未传 shadow）",
          "shadow = LiquidGlass.shadow" in theme)
    check("进度数字是小字（13 / 700）", "fontSize: 13" in page)
    check("2px 进度线 + 按队列填充",
          "class StudyProgressLine" in page and "thickness = 2" in page and
          "widthFactor: value.clamp(0.0, 1.0)" in page)
    check("标签做成胶囊（StudyTagPill）",
          "class StudyTagPill" in page and "StudyTagPill(" in page)
    check("字号层级拉开：状态 13 / 箱数 11",
          "emphasized ? 12 : 9" in page and "fontSize: 11" in page)
    check("左右对齐（Spacer 在中间）",
          "StudyTagPill(label: _badgeLabel(card), emphasized: true)" in page and
          "const Spacer()" in page)
    check("顶部留白加大（进度线到内容 26）", "SizedBox(height: 26)" in page)
    check("纸底状态栏要深色图标", "SystemUiOverlayStyle.dark" in page)


def behavior_checks():
    print("[行为一行不动]")
    check("2×2 四宫格还在", "_optionGrid" in page and "IntrinsicHeight" in page)
    check("A/B/C/D 还在", "String.fromCharCode(65 + widget.index)" in page)
    check("500ms 自动走还在", "milliseconds: 500" in page)
    check("点错留卡还在", "if (tap == CardTap.wrong) {" in page)
    check("「不认识」还在", "_tapUnknown" in page and "不认识" in page)
    check("答对直走在数据层纯函数里", "exitAfterCorrect" in page)
    check("入场 stagger 没动", "50 + i * 35" in page)
    check("触觉没动", "HapticFeedback" in page)
    check("选中态 / 点错态 / 高光逻辑没动",
          "tintAlpha = LiquidGlass.tintSelected" in page and
          "tintColor = LiquidGlass.wrongPink" in page and
          "highlight = 1.6" in page)


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
        "_source/check_glass_v069.py",
        "_source/check_glass_v068.py",
        "_source/check_glass_v066.py",
        "_source/check_glass_v064.py",
        "_source/release_notes_v069.md",
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
    check("版本号 0.6.9+14", "version: 0.6.9+14" in pub)


glass_checks()
aura_checks()
contrast_checks()
header_checks()
behavior_checks()
scope_checks()
version_checks()

print()
print(f"{passed}/{passed + failed} 通过")
raise SystemExit(0 if failed == 0 else 1)
