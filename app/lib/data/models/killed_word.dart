/// 「已斩」列表的一行（v0.8.0）。
///
/// 已斩 = `study_record.killed = 1`：移出学习与复习队列，词库保留。
/// 恢复只是把标记清掉，原来的箱位 / 到期时间不动 —— 所以这里保留 [box]，
/// 恢复后它回到原来的箱，不从头学。
class KilledWord {
  const KilledWord({
    required this.wordKey,
    required this.word,
    required this.phonetic,
    required this.meaning,
    required this.inWorkbook,
    required this.isAdded,
    required this.box,
  });

  final String wordKey;
  final String word;
  final String phonetic;

  /// 释义：820 词优先取单词本原文，自加词取词典 translation。
  final String meaning;

  /// 在 820 词单词本里。
  final bool inWorkbook;

  /// 在自加词里。
  final bool isAdded;

  /// 斩之前的当前箱位（0–6）。恢复后回到这个箱。
  final int box;
}
