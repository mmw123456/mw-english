"""v0.7.1 验收：真折射 shader + 底部内边距。

五条主线：
1. shader 文件真的存在、能编译、首个 uniform 是 vec2 + 有 sampler
2. Dart 侧参数符合 014 规则 01/02：边缘位移只在 bevel 圈、中心放大 4.5%、
   色散 6%、bevel 三档 12/26/44
3. GlassSurface 用 ImageFilter.shader + BackdropFilter 实现，加载失败
   静默回落（catchError / try-catch，无 assert）
4. 底部内边距 = 96 + 系统安全区，四个 Tab 页统一走 ShellPadding
5. 影响面：数据层 / 应用入口 / 主题 / android / 学习会话页零改动；
   玻璃调用点不用逐页接线（折射写在共用 GlassSurface 里）

跑法：python _source/check_glass_v071.py
"""

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
BASE = "2de0086"  # v0.7.0 提交

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


def read(*parts):
    with open(os.path.join(*parts), encoding="utf-8") as f:
        return f.read()


def git(*args):
    return subprocess.run(
        ["git", "-c", "core.quotepath=false", *args],
        cwd=ROOT, capture_output=True, text=True,
    ).stdout


def diff_lines(path):
    """返回 (删除行, 新增行)，去掉 diff 头与空行。"""
    out = git("diff", "-U0", BASE, "--", path)
    minus, plus = [], []
    for line in out.splitlines():
        if line.startswith(("---", "+++", "@@")):
            continue
        if line.startswith("-"):
            minus.append(line[1:].strip())
        elif line.startswith("+"):
            plus.append(line[1:].strip())
    return [l for l in minus if l], [l for l in plus if l]


print("== 1. shader 文件 ==")

frag_path = os.path.join(APP, "shaders", "liquid_glass.frag")
check("shader 文件存在", os.path.exists(frag_path), frag_path)
frag = read(APP, "shaders", "liquid_glass.frag") if os.path.exists(frag_path) else ""

check("pubspec 声明了 shader", "shaders/liquid_glass.frag" in read(APP, "pubspec.yaml"))
check("首个 uniform 是 vec2（ImageFilter.shader 硬要求）",
      re.search(r"uniform\s+vec2\s+uSize\s*;", frag) is not None)
check("有 sampler2D（能采到背后的东西）",
      re.search(r"uniform\s+sampler2D\s+uBackdrop\s*;", frag) is not None)
for u in ("uRadius", "uBevel", "uMagnify", "uDispersion"):
    check(f"有 uniform {u}", re.search(rf"uniform\s+float\s+{u}\s*;", frag) is not None)
check("位移系数 kEdgeBend = 0.62", "const float kEdgeBend = 0.62;" in frag)
check("GLES 后端翻转 y 轴", "#ifdef IMPELLER_TARGET_OPENGLES" in frag
      and re.search(r"uv\.y\s*=\s*1\.0\s*-\s*uv\.y", frag) is not None)
check("R/G/B 分三次采样（色散）", len(re.findall(r"texture\(uBackdrop", frag)) == 3)

print("== 2. 014 规则 01 / 02 参数 ==")

glass = read(LIB, "app", "theme", "liquid_glass.dart")
check("bevel 三档 12 / 26 / 44",
      all(f"static const double bevel{k} = {v};" in glass
          for k, v in (("List", 12), ("Button", 26), ("Sheet", 44))))
m = re.search(r"static const double magnify = ([\d.]+);", glass)
check("中心放大在 3–6%",
      m is not None and 1.03 <= float(m.group(1)) <= 1.06,
      m.group(1) if m else "缺 magnify")
check("色散 6%", re.search(r"static const double dispersion = 0\.06;", glass) is not None)
check("按尺寸自动分档（调用点不用逐页接线）", "static double bevelFor(Size size)" in glass)
check("几何纯函数与 shader 同源", "static GlassRefractionSample sample(" in glass)
check("圆角矩形 SDF", "static double _sdRoundRect(" in glass)

print("== 3. 真折射与回落 ==")

check("用 ImageFilter.shader", "ui.ImageFilter.shader(" in glass)
check("用 BackdropFilter 折射背后的画面", "BackdropFilter(filter: refraction" in glass)
check("磨砂作为 inner 先做", "ui.ImageFilter.compose(" in glass)
check("加载失败不抛（catchError）", ".catchError((Object _)" in glass)
check("滤镜构造失败不抛（try-catch）", "} catch (_) {" in glass)
check("非 Impeller 后端短路", "ImageFilter.isShaderFilterSupported" in glass)
check("加载路径没有 assert", "assert(" not in glass)

print("== 4. 底部内边距 ==")

shell = read(LIB, "app", "shell", "shell_padding.dart")
check("基准 96", "static const double bottomBase = 96;" in shell)
check("叠加系统底部安全区", "MediaQuery.viewPaddingOf(context).bottom" in shell)
check("四个 Tab 页都走统一口径",
      all("ShellPadding.scroll(context)" in read(LIB, "features", d, f)
          for d, f in (("study", "study_page.dart"), ("words", "words_page.dart"),
                       ("profile", "profile_page.dart"), ("reading", "reading_page.dart"))))
check("页面里不再写死底部 96",
      all("fromLTRB(20, 8, 20, 96)" not in read(LIB, "features", d, f)
          for d, f in (("study", "study_page.dart"), ("words", "words_page.dart"),
                       ("profile", "profile_page.dart"), ("reading", "reading_page.dart"))))

print("== 5. 影响面 ==")

check("数据层零改动", git("diff", "--name-only", BASE, "--", "app/lib/data").strip() == "")
for frozen in ("app/lib/main.dart", "app/lib/app/app.dart",
               "app/lib/app/theme/app_theme.dart", "app/lib/app/theme/app_colors.dart",
               "app/lib/features/study/study_session_page.dart",
               "app/lib/features/words/word_detail_page.dart", "app/android"):
    check(f"{frozen} 零改动", git("diff", "--name-only", BASE, "--", frozen).strip() == "")

# 四个 Tab 页只允许：import 统一口径 / padding 替换 / 注释 / 版本号
page_allow = [
    re.compile(r"^import '\.\./\.\./app/shell/shell_padding\.dart';$"),
    re.compile(r"^padding: (const EdgeInsets\.fromLTRB\(20, 8, 20, 96\)|ShellPadding\.scroll\(context\)),$"),
    re.compile(r"^// 底部 96.*$"),
    re.compile(r"^const _Tile\(icon: Icons\.article_outlined, title: '版本', value: '0\.7\.[01] \(\d+\)'\),$"),
]
for path in ("app/lib/features/profile/profile_page.dart",
             "app/lib/features/reading/reading_page.dart",
             "app/lib/features/study/study_page.dart",
             "app/lib/features/words/words_page.dart"):
    minus, plus = diff_lines(path)
    bad = [l for l in minus + plus if not any(p.match(l) for p in page_allow)]
    check(f"{os.path.basename(path)} 只改内边距/import/版本号", not bad, str(bad[:3]))

# home_shell：只改文档注释
minus, plus = diff_lines("app/lib/app/shell/home_shell.dart")
bad = [l for l in minus + plus if not l.startswith("///")]
check("home_shell 只改文档注释", not bad, str(bad[:3]))

# pubspec：只允许版本 + shaders 声明
minus, plus = diff_lines("app/pubspec.yaml")
allowed = {
    "version: 0.7.0+15", "version: 0.7.1+16", "shaders:",
    "- shaders/liquid_glass.frag",
}
bad = [l for l in minus + plus
       if l not in allowed and not l.startswith("#")]
check("pubspec 只改版本 + shader 声明", not bad, str(bad[:3]))

untracked = set(git("ls-files", "--others", "--exclude-standard", "--", "app").splitlines())
expect_new = {
    "app/lib/app/shell/shell_padding.dart",
    "app/shaders/liquid_glass.frag",
    "app/test/glass_refraction_test.dart",
}
check("新增文件只有外壳内边距 / shader / 测试",
      untracked == expect_new, str(sorted(untracked - expect_new)))

print("== 6. 版本与测试 ==")

check("pubspec 版本 0.7.1+16", "version: 0.7.1+16" in read(APP, "pubspec.yaml"))
profile = read(LIB, "features", "profile", "profile_page.dart")
check("我的页版本号 0.7.1 (2016)", "'0.7.1 (2016)'" in profile)

test = read(APP, "test", "glass_refraction_test.dart")
for needle, label in (
    ("能编译", "shader 能编译"),
    ("只在 bevel 圈内", "边缘位移只在 bevel 圈"),
    ("中心点位移为 0", "中心无位移"),
    ("加载失败", "加载失败回落"),
    ("底部内边距", "底部内边距"),
):
    check(f"新增测试覆盖：{label}", needle in test)

print()
print(f"{passed} PASS / {failed} FAIL")
raise SystemExit(1 if failed else 0)
