"""v0.7.0 验收：全 App 换浅色纸底液态玻璃（学习卡片页的预览定稿）。

四条主线：
1. 主题合并：liquid_glass 提成全局 AppTheme.light（Brightness.light），
   M3 预览主题与它的测试已删除，全局无 AppTheme.dark 引用
2. 纸底与字色：纸 #F3F2EE、墨 #0B0C10、次要墨 70%、三级墨 62%，
   正文与次要字在纸上 / 纸面卡上均 ≥4.5:1；旧深色值一个不剩
3. 各页：首页纸面卡 + 玻璃胶囊按钮、词库玻璃搜索框（列表行不上玻璃）、
   详情纸面卡区块 + 玻璃控件、我的/阅读换纸、Tab 栏悬浮玻璃条
4. 影响面：数据层、android、app_defaults 零改动（本版本来就该动页面）

跑法：python _source/check_theme_v070.py
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
TEST = os.path.join(APP, "test")

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


def exists(*parts):
    return os.path.exists(os.path.join(*parts))


def git(*args):
    return subprocess.run(
        ["git", "-c", "core.quotepath=false", *args],
        cwd=ROOT, capture_output=True, text=True,
    ).stdout


# ---- 颜色：sRGB 逐通道 alpha 合成 + WCAG 对比 ----

def rgb(hex_color):
    h = hex_color.lstrip("#")
    if len(h) == 8:  # AARRGGBB
        h = h[2:]
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def over(fg_hex, bg_rgb, alpha=None):
    fg = rgb(fg_hex)
    a = alpha if alpha is not None else (
        int(fg_hex.lstrip("#")[0:2], 16) / 255
        if len(fg_hex.lstrip("#")) == 8 else 1.0
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


THEME = os.path.join(LIB, "app", "theme", "app_theme.dart")
COLORS = os.path.join(LIB, "app", "theme", "app_colors.dart")
GLASS = os.path.join(LIB, "app", "theme", "liquid_glass.dart")
APP_DART = os.path.join(LIB, "app", "app.dart")
SHELL = os.path.join(LIB, "app", "shell", "home_shell.dart")
STUDY = os.path.join(LIB, "features", "study", "study_page.dart")
SESSION = os.path.join(LIB, "features", "study", "study_session_page.dart")
WORDS = os.path.join(LIB, "features", "words", "words_page.dart")
DETAIL = os.path.join(LIB, "features", "words", "word_detail_page.dart")
PROFILE = os.path.join(LIB, "features", "profile", "profile_page.dart")
READING = os.path.join(LIB, "features", "reading", "reading_page.dart")

theme = read(THEME)
colors = read(COLORS)
glass = read(GLASS)
app_dart = read(APP_DART)
shell = read(SHELL)
study = read(STUDY)
session = read(SESSION)
words = read(WORDS)
detail = read(DETAIL)
profile = read(PROFILE)
reading = read(READING)

PAPER = "#F3F2EE"
INK = "#0B0C10"
CARD = "#FAF9F5"


def theme_checks():
    print("[主题合并：预览定稿]")
    check("全局只剩 light（AppTheme.light）",
          "static final ThemeData light" in theme and "static ThemeData get dark" not in theme)
    check("主题 brightness 是 light",
          "brightness: Brightness.light" in theme)
    check("app.dart 用 AppTheme.light", "theme: AppTheme.light" in app_dart)
    check("M3 预览主题文件已删",
          not exists(LIB, "app", "theme", "study_preview_theme.dart"))
    check("M3 预览的专属测试已删",
          not exists(TEST, "theme_m3_test.dart"))
    check("液态玻璃文件不再是「preview」命名",
          exists(LIB, "app", "theme", "liquid_glass.dart") and
          not exists(LIB, "app", "theme", "liquid_glass_preview_theme.dart"))

    hits = git("grep", "-n", "-E", r"AppTheme\.dark|LiquidGlassPreviewTheme|StudyPreviewTheme", "--", "app/lib", "app/test")
    check("全局无 AppTheme.dark / 预览主题引用", hits.strip() == "", hits.strip()[:300])

    check("学习页不再自己套 Theme（全局已生效）",
          "LiquidGlassPreviewTheme" not in session and "Theme(\n      data:" not in session)


def palette_checks():
    print("[纸底与字色]")
    check("纸仍是 #F3F2EE", "paper = Color(0xFFF3F2EE)" in glass)
    check("墨仍是 #0B0C10", "ink = Color(0xFF0B0C10)" in glass)
    check("次要墨 70%", "textSecondary = Color(0xB30B0C10)" in glass)
    check("三级墨 62%（拉开一档）", "textTertiary = Color(0x9E0B0C10)" in colors)
    check("纸面卡比纸亮一点", "surface = Color(0xFFFAF9F5)" in colors)

    old_dark = [
        ("近黑底", "0B0B0C"),
        ("深色面", "161618"),
        ("次级深面", "1E1E21"),
        ("浅色主字", "F2F2F4"),
        ("灰色次字", "8E8E96"),
        ("深灰三级字", "55555C"),
        ("冷白强调", "C9CED8"),
        ("深色分隔线", "242428"),
    ]
    hits = git("grep", "-n", "-i", "-E", "|".join(v for _, v in old_dark), "--", "app/lib")
    check("旧深色值一个不剩", hits.strip() == "", hits.strip()[:300])

    paper = rgb(PAPER)
    card = rgb(CARD)
    for name, bg in (("纸", paper), ("纸面卡", card)):
        p = contrast(rgb(INK), bg)
        s = contrast(over("#B30B0C10", bg), bg)
        t = contrast(over("#9E0B0C10", bg), bg)
        check(f"{name}上正文 {p:.2f}:1 ≥ 4.5", p >= 4.5)
        check(f"{name}上次要字 {s:.2f}:1 ≥ 4.5", s >= 4.5)
        check(f"{name}上三级字 {t:.2f}:1 ≥ 4.5", t >= 4.5)

    # 氛围还在学习页最浓的 25% 上压字：墨与次要字都得达标。
    worst = 99.0
    for c in ("#FF5A1F", "#FF2E7E", "#2BD9A0", "#8B5CFF", "#2E4BFF"):
        bg = over(c, paper, 0.25)
        bg = over("#FFFFFF", bg, 0.02)
        worst = min(worst, contrast(rgb(INK), bg), contrast(over("#B30B0C10", bg), bg))
    check(f"氛围峰值上最差 {worst:.2f}:1 ≥ 4.5", worst >= 4.5)


def page_checks():
    print("[各页换纸]")
    # 首页
    check("首页主按钮是玻璃胶囊（两个）", study.count("_GlassButton(") >= 2 or
          (study.count("GlassSurface(") >= 2 and "_GlassButton" in study))
    check("首页任务卡 / 数字卡是纸面卡，不上玻璃",
          "_TodayCard" in study and "AppColors.surface" in study and
          "GlassSurface" not in study.split("class _TodayCard")[1].split("class _LapseNotice")[0])
    check("首页列表底部给悬浮 Tab 栏留位置", "fromLTRB(20, 8, 20, 96)" in study)

    # 词库
    search_block = words.split("class _SearchField")[1].split("/// 词表排序")[0]
    check("词库搜索框是玻璃胶囊", "GlassSurface(" in search_block and "radius: 999" in search_block)
    rows = words.split("class _WordRow")[1].split("class _MeaningBlock")[0]
    check("词库列表行仍压纸、不上玻璃", "GlassSurface" not in rows and "AppColors.surface" not in rows)

    # 详情
    check("详情区块是纸面卡", "_paperCard" in detail and "decoration: _paperCard" in detail)
    check("详情星标 / 发音 / 加词表都是玻璃",
          detail.count("GlassSurface(") >= 3)
    check("详情遮盖逻辑没动",
          "revealChinese" in detail and "_maskedFor(" in detail and "_reveal(" in detail)

    # 我的 / 阅读
    check("我的页底走主题（不再写死深色）", "AppColors" in profile)
    check("阅读页底走主题（不再写死深色）", "AppColors" in reading)

    # Tab 栏
    check("Tab 栏是悬浮玻璃条", "GlassSurface(" in shell and "radius: 28" in shell)
    check("内容从玻璃条底下穿过去", "extendBody: true" in shell)
    check("Tab 图标文字用墨系",
          "LiquidGlass.ink" in shell and "LiquidGlass.textSecondary" in shell)
    check("选中态加深 tint（36% 白）",
          "LiquidGlass.tintSelected" in shell)

    # 氛围只留在学习页
    # 只数页面里的用法（定义本身在 liquid_glass.dart）。
    hits = git("grep", "-l", "LiquidGlassBackdrop", "--", "app/lib/features")
    files = [line.strip() for line in hits.splitlines() if line.strip()]
    check("氛围渐变只在学习卡片页",
          files == ["app/lib/features/study/study_session_page.dart"], str(files))


def impact_checks():
    print("[影响面：数据层零改动]")
    changed = set()
    for line in git("diff", "--name-only", "HEAD").splitlines():
        if line.strip():
            changed.add(line.strip())
    for line in git("ls-files", "--others", "--exclude-standard").splitlines():
        if line.strip():
            changed.add(line.strip())

    data_hits = [p for p in changed if p.startswith("app/lib/data/")]
    check("数据层零改动", data_hits == [], str(data_hits))

    native_hits = [p for p in changed if p.startswith("app/android/")]
    check("android 配置零改动", native_hits == [], str(native_hits))

    allowed_prefixes = (
        "app/lib/app/", "app/lib/features/", "app/test/",
        "app/pubspec.yaml", "_source/", "项目日志.md",
    )
    outside = [p for p in changed if not p.startswith(allowed_prefixes)]
    check("改动面都在主题 / 页面 / 测试 / 文档里", outside == [], str(outside))

    check("app_defaults 零改动",
          "app/lib/app/app_defaults.dart" not in changed)


def version_checks():
    print("[版本与产物]")
    pub = read(os.path.join(APP, "pubspec.yaml"))
    check("版本号 0.7.0+15", "version: 0.7.0+15" in pub)
    check("我的页版本号跟着走", "0.7.0 (2015)" in profile)


def main():
    theme_checks()
    palette_checks()
    page_checks()
    impact_checks()
    version_checks()
    print()
    print(f"{passed} 通过, {failed} 失败")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
