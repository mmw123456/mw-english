## v0.6.3 预览版：学习卡片页换 Material Design 3

**这是预览版，只改了学习卡片这一屏。** 词库、详情、我的、Tab 外壳、全局主题都没动，
先装上看看效果，看完再决定要不要全量换。

### 改了什么

- 这一屏套上 `useMaterial3: true`，配色由 `ColorScheme.fromSeed` 从现有那支冷白强调色
  （`#C9CED8`）生成，深色。
- 卡片三级深浅不再手写色值，改用 ColorScheme 自带的三档：
  页面底 `surfaceContainerLow`（#1C1B1C）→ 单词区块 `surfaceContainer`（#201F20）→
  选项 `surfaceContainerHigh`（#2A2A2A）。
- 选中态用 `primaryContainer`（#C9CED8，深色文字 #525860）；点错用 `errorContainer`。
- 圆角、字号、按钮高度、按压水波全吃 M3 默认：卡片 12dp、按钮胶囊形、
  单词 `displaySmall`（36）、释义 `titleMedium`（16）、标签 `labelLarge`（14）。
- 单词区块从「裸文字」变成一张 M3 卡；「发音」从自制小胶囊改成 M3 的 tonal 按钮。
- 「不认识」按钮去掉手写的高度/描边/圆角，用 M3 outlined 按钮默认样式。

### 一个需要你看一眼的地方

`ColorScheme.fromSeed` 默认变体（tonalSpot）会把这支低饱和冷白拉成饱和天蓝
（primary `#A0CAFD`、primaryContainer `#194975`），跟「别另挑艳色」冲突，
所以用了 `fidelity` 变体 —— 保留种子本身色相，primary 是近白 `#E5EAF4`，
选中态正好落在原来的强调色上。

想换成标准 M3 的蓝色系，改一行 `dynamicSchemeVariant` 即可。

### 没动的

- 四选一 2×2、选项顺序 A/B/C/D、点对 500ms 自动走、点错留卡继续选、
  「不认识」记错与进详情、Leitner 调度、当日重测 —— 全部与 v0.6.2 一致。
- 其他页面仍是原主题（`AppTheme.dark` 一行没改）。
- M3 Expressive（更大圆角、弹性按压）这次不动。

### 验收

- `flutter analyze` 0 issue；`flutter test` 52 passed（新增 8 条主题约束用例：
  M3/深色/种子色不被拉艳/三级深浅递增/选中态与未选中态亮度差/字号为 M3 默认/
  字体仍是 NotoSansSC/学习页读到 M3、外壳仍是旧主题）
- `check_m3_v063.py` 28/28；其中「影响面」用 git 核对：`lib/` 下只改了学习页 +
  新主题文件，数据层、`app.dart`、外壳 Tab 都没动
- `check_v062.py` 26/26 回归通过（四条 v0.6.2 行为仍在）
- APK `versionName=0.6.3` / `versionCode=2009`
- 未在真机验证：实际观感（深色下三档深浅是否够分、选中态够不够显眼、
  字阶跳变大不大）、按压水波手感 —— 这版就是给你看这些的
