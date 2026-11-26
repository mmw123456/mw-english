## v0.6.7 · 中文查词（补 v0.6.5）

搜索框一直写着「查词，中英均可」，实际只匹配英文列，输入中文什么都搜不到。这版补上。

### 怎么改

- **英文不变**：仍只匹配单词开头（v0.6.2 的规则），搜 `no` 不会带出 indigenous / manoeuvre / autonomy / renovate / gastronomic。
- **中文走释义包含**：释义一律以词性开头（`vt. 传送…`），按开头匹配等于永远搜不到，所以中文改查释义列。
  - 我的词表：`meaning_pdf` + `meaning_ecdict` 两段都查
  - 离线词典 / 自加词：查 `translation`
- 排序：中文词典结果按词频（常用度）排，没有词频的排后面。

### 验证

- `check_search_v067.py` 25/25，在真词库上跑等价 SQL：搜「传」命中 transmit，搜「传送」命中 transmit / transfer / carry；英文两组回归用例仍按前缀。
- `flutter test` 64 passed；`flutter analyze` 0。

### 还是没做的

- 搜索仍是本地 SQLite 的 `LIKE`，没做拼音、没做模糊纠错。
- 自加词表为空时中文分支只验证了「不报错」，等有自加词再实测。
