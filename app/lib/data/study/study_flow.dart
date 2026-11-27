/// 一题四选一的作答状态机。
///
/// 规则（2026-11-25 v0.6.0）：
/// - 点错：该选项变红禁用，**留在本卡继续选**，答对前不揭示正确答案
/// - 首次点错就按 Leitner 记错；之后选对不再改判，也不再记一次
/// - 点对：变绿，500ms 后离开
///
/// 这里是纯状态，不碰数据库也不碰 UI，单测直接跑。
library;

/// 一次点击的结果。
enum CardTap {
  /// 点的是已经禁用 / 已经答完的选项，什么也没发生。
  ignored,

  /// 点错了，这个选项作废。
  wrong,

  /// 第一次点就对。
  correctFirstTry,

  /// 错过后才点对。
  correctAfterWrong,
}

/// 选项在界面上的四种状态。
enum OptionState {
  /// 还没点过。
  neutral,

  /// 点错了，已禁用。
  wrong,

  /// 点对了。
  correct,

  /// 已经答完，剩下的选项变暗。
  dimmed,
}

/// 一张卡的作答进度。
class CardProgress {
  /// 点错过的选项下标。
  final Set<int> wrongPicks = <int>{};

  /// 是否已经把「答错」记进调度。整个会话里一张卡最多记一次。
  bool recordedWrong = false;

  /// 是否已经答对（答对后本卡不再接受点击）。
  bool resolved = false;

  /// 答对的那个选项下标。
  int? correctPick;

  bool get firstTry => !recordedWrong;

  /// 点第 [index] 个选项（正确项是 [answerIndex]）。
  CardTap tap(int index, int answerIndex) {
    if (resolved) return CardTap.ignored;
    if (wrongPicks.contains(index)) return CardTap.ignored;

    if (index == answerIndex) {
      resolved = true;
      correctPick = index;
      return recordedWrong ? CardTap.correctAfterWrong : CardTap.correctFirstTry;
    }

    wrongPicks.add(index);
    recordedWrong = true;
    return CardTap.wrong;
  }

  OptionState stateOf(int index) {
    if (correctPick == index) return OptionState.correct;
    if (wrongPicks.contains(index)) return OptionState.wrong;
    if (resolved) return OptionState.dimmed;
    return OptionState.neutral;
  }

  /// 「不认识」按钮（v0.6.2）：等同首次点错，整张卡按答错处理。
  ///
  /// 已经点错过选项的卡再点「不认识」，这里不重复标记错 —— 调用方据此
  /// 只跳详情页、不再落库。返回 true 表示这次是首次记错。
  bool markUnknown() {
    if (resolved || recordedWrong) return false;
    recordedWrong = true;
    return true;
  }
}

/// 答对之后该去哪。
enum CardExit {
  /// 直接下一张卡。
  nextCard,

  /// 先进这个词的详情整页，出来再下一张。
  detail,
}

/// 答对之后该去哪（v0.6.6 改）。
///
/// 只有「先点错、再选对」才进详情页：那种情况确实需要看一眼完整释义。
/// 第一次就答对（新词、复习都一样）直接下一张卡，不再为新词强插详情页。
/// 「不认识」不走这里 —— 它自己直接跳详情。
CardExit exitAfterCorrect({required bool hadWrong}) {
  return hadWrong ? CardExit.detail : CardExit.nextCard;
}
