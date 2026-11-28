/// 形近词的判定与距离计算。
///
/// v0.4.0 详情页的「形近词」和 v0.6.0 学习卡片的「干扰项」用的是同一套
/// 算法，抽出来共用一份，避免两处口径跑偏（详情页会显示距离，卡片只取释义，
/// 但「什么算形近」必须是同一个标准）。
library;

/// 判断 b 是不是 a 的变形/派生（互为前缀且长度接近）。
///
/// `eliminate → eliminated`、`sketch → sketchy` 这类是同一个词的变形，
/// 放进形近词里只会误导，当干扰项也会让题变简单。
bool isDerived(String a, String b) {
  if (a == b) return true;
  final short = a.length <= b.length ? a : b;
  final long = a.length <= b.length ? b : a;
  if (!long.startsWith(short)) return false;
  return long.length - short.length <= 4;
}

/// Levenshtein 距离，超过 [cap] 立刻返回 cap + 1（省时间）。
int editDistance(String a, String b, {int cap = 3}) {
  if ((a.length - b.length).abs() > cap) return cap + 1;
  final prev = List<int>.generate(b.length + 1, (i) => i);
  final cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j - 1] + cost;
      if (prev[j] + 1 < v) v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > cap) return cap + 1;
    for (var j = 0; j <= b.length; j++) {
      prev[j] = cur[j];
    }
  }
  return prev[b.length];
}
