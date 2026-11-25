# MW English

离线背单词 Android App。自建 820 词词表 + 43,350 词离线词典 + Leitner 分箱复习。

纯本地运行，无登录、无网络依赖。用 Flutter 写，Android 优先，后续可扩 iOS。

## 当前进度

| 阶段 | 状态 |
|---|---|
| 阶段 0：方案确认 + 数据准备 | 完成 |
| 阶段 1：构建环境搭建 + 可跑通 APK | 完成 |
| 阶段 2（P0）：学习闭环 | 未开始 |

P0 目标只做一件事：能背单词。骨架、主题、SQLite、卡片、三题型、Leitner 调度、真机实测。
AI 文章、查词、PDF 导入、统计、拼写留到 P1 之后。

## 目录

```
app/                        Flutter 工程
  lib/main.dart             入口：状态栏样式 + 启动
  lib/app/app.dart          MaterialApp
  lib/app/theme/            深色极简主题（颜色 + ThemeData）
  lib/app/shell/            4 Tab 容器，IndexedStack 保状态
  lib/features/study/       学习页
  lib/features/words/       词库页
  lib/features/reading/     阅读页
  lib/features/profile/     我的页
  assets/fonts/             NotoSansSC Regular/Bold 官方 OTF（各 16–17 MB）
  assets/db/                dict.sqlite 副本，供打包
  android/                  包名 com.mwenglish.app / minSdk 24 / targetSdk 36
assets/db/dict.sqlite       离线词典，43,350 词 / 5.5 MB
data/words_820.csv          820 词终表（序号、单词、音标、PDF 释义、ECDICT 释义、词根）
data/words_820_preview.html 可搜索的数据核对页
_source/                    数据处理脚本
   parse_pdf.py             PDF 抽词
   clean.py                 释义清洗
   match.py                 ECDICT 覆盖率核对
   repair.py                修 PDF 断词
   build_dataset.py         生成 CSV + dict.sqlite
   api_push.py              网络受限时的推送脚本（见下）
   build_release.sh         一键出 release APK（自动绕开中文路径）
   fonts/convert.py         woff2 → ttf（旧方案，已改用官方 OTF）
项目日志.md                  决策记录、环境版本、踩坑记录
```

## 字体

用 **Noto Sans CJK SC 官方 OTF 全量版**，不做子集化。

| 项 | 值 |
|---|---|
| 文件 | `NotoSansSC-Regular.otf` / `NotoSansSC-Bold.otf` |
| 字符数 | 44,810（CJK 统一汉字 20,976，含扩展 A） |
| 单字重体积 | 16–17 MB |
| 轮廓格式 | CFF |

来源：npm 包 `@fontpkg/noto-sans-cjk-sc`（内部就是官方 noto-cjk 的 OTF）。
本机 GitHub raw 全不通，Google Fonts 只有分片 woff2（7,898 字符），故走 npm registry。

选全量而非子集的原因：子集只覆盖到 GB2312/GBK 常用字，释义里出现生僻字就会缺字。
体积差 30 MB，对背单词 App 不值得为此冒缺字风险。


## 数据来源

- **820 词表**：用户自备 PDF（收藏单词网页打印版，20 页，含文字层），提取后清洗。原始 PDF 不入库。
- **词典**： [ECDICT](https://github.com/skywind3000/ECDICT)。筛选规则为「有词频或有考试标签」，得 43,350 词。
- **8 个词** ECDICT 查不到或不在裁剪档内，已强制并入：`duple` `graver` `utile` `once (and) for all` `in retrospect` `meditating` `diapers` `plagued`。

数据口径说明：

- 820 条全部有释义；819 条能从 ECDICT 拿到完整释义，唯一缺口是 `once (and) for all`（ECDICT 全库未收录该词组），用 PDF 释义兜底。
- 音标覆盖 815/820。
- PDF 释义被「…」截断 126 条，用 ECDICT 补全，预览页标黄。

重建词库：

```bash
# 需要先下载 ECDICT 到 _source/ecdict.csv（约 63 MB）
curl -L -o _source/ecdict.csv https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv
python _source/build_dataset.py
```

## 构建

### 环境版本（已验证出包）

| 组件 | 版本 |
|---|---|
| Flutter | 3.50.1 stable（Dart 3.14.0） |
| JDK（编译用） | Temurin 21.0.13.1+2 |
| Android SDK | platform 36 / build-tools 37.0.0 / platform-tools 37.0.3 |
| NDK | 28.2.13676358 |
| AGP / Gradle / Kotlin | 9.3.1 / 9.5.0 / 2.4.20 |

### 出包

```bash
cd app
flutter pub get
flutter build apk --release --split-per-abi
# 产物：build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### 国内网络配置

依赖全部走镜像，否则 `maven.google.com` 直连超时：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

`app/android/settings.gradle.kts` 与 `app/android/build.gradle.kts` 里的仓库已改为阿里云镜像，
`gradle-wrapper.properties` 指向腾讯 Gradle 镜像。

## 四个必须知道的坑

1. **AGP 拒绝中文路径**。项目位于含中文的目录时，Gradle 直接失败。已在 `gradle.properties` 加
   `android.overridePathCheck=true` 绕过 Gradle 侧检查。

2. **AOT 编译器不认中文路径**。`gen_snapshot` 按 ANSI 读路径，中文变乱码，release 构建报
   `Dart snapshot generator failed with exit code 255` + `Unable to read file: D:\AI????\...`。
   **debug 能过，release 必挂**。解法：把工程放到纯英文路径下构建（例如 `D:\build\mw_english`），
   或用 junction 之外的方式真正迁移目录（junction 无效，Dart 会解析成真实中文路径）。

3. **NDK 是强制的**。注释掉 `ndkVersion` 没用，Flutter Gradle 插件会自己补上并要求下载 2.1 GB 的 NDK。

4. **`flutter --version` 会骗人**。SDK 解压不完整（缺 `packages/flutter_tools`）时它照常返回版本号。
   判据只有 `flutter doctor`。

## 推送（网络受限环境）

本机到 `github.com` 主站不通（代理对主站返回 502，SSH 22/443 均超时），但 `api.github.com` 可达。
因此 `git push` 失败时改用 REST API：

```bash
python _source/api_push.py
```

它会读取当前 HEAD 的完整文件树，通过 `git/blobs` + `git/trees` + `git/commits` 重建一个单 commit
并更新分支。代价是**远程不留本地提交历史**，且本地与远程没有共同祖先，网络恢复后需要重新对齐。

## 许可

词典数据来自 ECDICT（MIT）。字体为 Noto Sans SC（SIL OFL 1.1）。
