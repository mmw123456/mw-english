import 'dart:math' as math;

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Database, Sqflite;

import '../../app/app_defaults.dart';
import '../db/app_database.dart';
import '../models/study_card.dart';
import '../study/leitner.dart';

/// 今日概况。学习页顶部卡片读这个。
class TodayStats {
  const TodayStats({
    required this.newLearned,
    required this.newTarget,
    required this.dueReview,
    required this.wrongToday,
    required this.totalLearned,
    required this.mastered,
    required this.gapDays,
    required this.reduced,
  });

  /// 今天第一次进入学习的词数。
  final int newLearned;

  /// 今天的新词配额。断档会被削减，所以不一定等于默认的 30。
  final int newTarget;

  /// 到期该复习的词数（含当天重测，不含新词、不含已斩）。
  final int dueReview;

  /// 今天答错的次数。
  final int wrongToday;

  /// 已进入学习流程的总词数。
  final int totalLearned;

  /// 已掌握：箱位到顶（30 天间隔）且未斩。
  final int mastered;

  /// 距上次学习隔了几个自然日。
  final int gapDays;

  /// 今天的新词配额是否被断档削减过。
  final bool reduced;

  static const TodayStats empty = TodayStats(
    newLearned: 0,
    newTarget: AppDefaults.dailyNewWordTarget,
    dueReview: 0,
    wrongToday: 0,
    totalLearned: 0,
    mastered: 0,
    gapDays: 0,
    reduced: false,
  );
}

/// 学习记录的读写 + 会话装配。
///
/// 调度规则本身在 [Leitner] 里（纯函数，可单测），这里只负责
/// 「读记录 → 算 → 写回 → 出卡片」。所有写入都在一个事务里，
/// 中途杀进程不会出现「箱位变了但流水没记」的错账。
class StudyDao {
  const StudyDao();

  /// 今天的起止时间戳（本地时区 00:00 到次日 00:00）。
  static ({int from, int to}) todayRange([DateTime? now]) {
    final n = now ?? DateTime.now();
    final from = DateTime(n.year, n.month, n.day);
    return (
      from: from.millisecondsSinceEpoch,
      to: from.add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
  }

  Future<TodayStats> todayStats() async {
    final db = await AppDatabase.open();
    final range = todayRange();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final newLearned = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM study_record '
              'WHERE started = 1 AND first_seen_at >= ? AND first_seen_at < ?',
              [range.from, range.to],
            )) ??
        0;

    final dueReview = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM study_record '
              'WHERE started = 1 AND killed = 0 AND due_at <= ? '
              'AND (box > 0 OR retest = 1)',
              [nowMs],
            )) ??
        0;

    final wrongToday = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM study_log '
              'WHERE correct = 0 AND at >= ? AND at < ?',
              [range.from, range.to],
            )) ??
        0;

    final totalLearned = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM study_record WHERE started = 1'),
        ) ??
        0;

    final mastered = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM study_record '
              'WHERE started = 1 AND killed = 0 AND box >= ?',
              [Leitner.topBox],
            )) ??
        0;

    final quota = await dailyQuota();

    return TodayStats(
      newLearned: newLearned,
      newTarget: quota.newWords,
      dueReview: dueReview,
      wrongToday: wrongToday,
      totalLearned: totalLearned,
      mastered: mastered,
      gapDays: quota.gapDays,
      reduced: quota.reduced,
    );
  }

  /// 已斩（不再出现）的词数。
  Future<int> killedCount() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery('SELECT COUNT(*) FROM study_record WHERE killed = 1');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 当前是学习的第几天。第一条学习记录那天算第 1 天，没有记录返回 0。
  Future<int> studyDayNumber() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery(
      'SELECT MIN(first_seen_at) AS m FROM study_record '
      'WHERE started = 1 AND first_seen_at > 0',
    );
    final first = rows.first['m'] as int?;
    if (first == null) return 0;
    final start = DateTime.fromMillisecondsSinceEpoch(first);
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    return days + 1;
  }

  /// 星标词数。
  Future<int> starredCount() async {
    final db = await AppDatabase.open();
    final rows = await db.rawQuery('SELECT COUNT(*) FROM study_record WHERE starred = 1');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 上次答题时间。断档判定用它。
  Future<DateTime?> lastStudyAt() async {
    final db = await AppDatabase.open();
    return _lastStudyAt(db);
  }

  static Future<DateTime?> _lastStudyAt(Database db) async {
    final rows = await db.rawQuery('SELECT MAX(at) AS m FROM study_log');
    final last = rows.first['m'] as int?;
    if (last == null || last <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(last);
  }

  /// 今天的配额，**当天第一次算出来就存进 settings**。
  ///
  /// 不存的话会出岔子：断档 5 天回来，第一次算出来是 6 个新词；
  /// 答完第一个词 `lastStudyAt` 就变成今天了，再算一次又变回 30 个。
  /// 存住之后当天配额稳定，第二天换 key 重算。
  Future<DailyQuota> dailyQuota({DateTime? now}) async {
    final db = await AppDatabase.open();
    final n = now ?? DateTime.now();
    final key = 'quota_${n.year}-${_two(n.month)}-${_two(n.day)}';

    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final parts = (rows.first['value'] as String? ?? '').split(',');
      if (parts.length >= 3) {
        final newWords = int.tryParse(parts[0]);
        final cap = int.tryParse(parts[1]);
        final gap = int.tryParse(parts[2]);
        if (newWords != null && cap != null && gap != null) {
          return DailyQuota(
            newWords: newWords,
            reviewCap: cap,
            gapDays: gap,
            reduced: parts.length > 3 && parts[3] == '1',
          );
        }
      }
    }

    final quota = Leitner.quota(lastStudyAt: await _lastStudyAt(db), now: n);
    await db.delete(
      'settings',
      where: "key LIKE 'quota_%' AND key <> ?",
      whereArgs: [key],
    );
    await db.insert(
      'settings',
      {
        'key': key,
        'value': '${quota.newWords},${quota.reviewCap},'
            '${quota.gapDays},${quota.reduced ? 1 : 0}',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return quota;
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';

  /// 装配一次学习会话。
  ///
  /// 顺序：到期复习（含今日重测）→ 新词，按「复习为主、新词穿插」交错。
  /// 断档 ≥ 3 天时复习优先、新词减半，见 [Leitner.quota]。
  Future<StudySession> buildSession({
    bool onlyReview = false,
    DateTime? now,
  }) async {
    final db = await AppDatabase.open();
    final n = now ?? DateTime.now();
    final nowMs = n.millisecondsSinceEpoch;
    final range = todayRange(n);

    final quota = await dailyQuota(now: n);

    final learnedToday = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM study_record '
              'WHERE started = 1 AND first_seen_at >= ? AND first_seen_at < ?',
              [range.from, range.to],
            )) ??
        0;

    final reviewRows = await db.rawQuery(
      '''
      SELECT r.word_key, r.box, r.retest, r.correct_count, r.wrong_count,
             m.word, m.phonetic, m.meaning_pdf, m.meaning_ecdict
      FROM study_record r
      JOIN my_words m ON m.word_key = r.word_key
      WHERE r.started = 1 AND r.killed = 0 AND r.due_at <= ?
        AND (r.box > 0 OR r.retest = 1)
      ORDER BY r.due_at ASC
      LIMIT ?
      ''',
      [nowMs, quota.reviewCap],
    );

    final remainingNew = onlyReview
        ? 0
        : math.max(0, quota.newWords - learnedToday);

    var newRows = <Map<String, Object?>>[];
    if (remainingNew > 0) {
      newRows = await db.rawQuery(
        '''
        SELECT m.word_key, m.word, m.phonetic, m.meaning_pdf, m.meaning_ecdict
        FROM my_words m
        LEFT JOIN study_record r ON r.word_key = m.word_key
        WHERE r.word_key IS NULL OR r.started = 0
        ORDER BY m.no ASC
        LIMIT ?
        ''',
        [remainingNew],
      );
    }

    // 干扰项一次性取一批，别在循环里查库。
    final pool = await db.rawQuery(
      '''
      SELECT word_key, word, meaning_pdf, meaning_ecdict
      FROM my_words
      ORDER BY RANDOM()
      LIMIT 260
      ''',
    );

    final retestCount =
        reviewRows.where((r) => ((r['retest'] as int?) ?? 0) == 1).length;

    final reviews = reviewRows.map((r) {
      final attempts = ((r['correct_count'] as int?) ?? 0) +
          ((r['wrong_count'] as int?) ?? 0);
      return _card(
        row: r,
        box: (r['box'] as int?) ?? 0,
        isNew: false,
        isRetest: ((r['retest'] as int?) ?? 0) == 1,
        attempts: attempts,
        pool: pool,
      );
    }).toList();

    final news = newRows.map((r) {
      return _card(
        row: r,
        box: 0,
        isNew: true,
        isRetest: false,
        attempts: 0,
        pool: pool,
      );
    }).toList();

    final cards = <StudyCard>[];
    if (quota.reviewsFirst) {
      // 断档回来：先把账还完，再上新词。
      cards.addAll(reviews);
      cards.addAll(news);
    } else {
      // 正常情况：每 4 张复习插 1 张新词，避免连着背 100 张旧词。
      var ri = 0;
      var ni = 0;
      while (ri < reviews.length || ni < news.length) {
        for (var k = 0; k < 4 && ri < reviews.length; k++) {
          cards.add(reviews[ri++]);
        }
        if (ni < news.length) cards.add(news[ni++]);
      }
    }

    return StudySession(
      cards: cards,
      quota: quota,
      newCount: news.length,
      reviewCount: reviews.length,
      retestCount: retestCount,
      learnedToday: learnedToday,
    );
  }

  /// 作答并落库。
  ///
  /// 一个事务里同时写 `study_record`（箱位/到期/连对）和 `study_log`（流水）。
  Future<AnswerResult> answer({
    required StudyCard card,
    required bool correct,
    DateTime? now,
  }) async {
    final db = await AppDatabase.open();
    final n = now ?? DateTime.now();
    final nowMs = n.millisecondsSinceEpoch;

    return db.transaction((txn) async {
      final rows = await txn.query(
        'study_record',
        where: 'word_key = ?',
        whereArgs: [card.wordKey],
        limit: 1,
      );
      final row = rows.isEmpty ? null : rows.first;
      final started = row != null && ((row['started'] as int?) ?? 0) == 1;

      final state = row == null
          ? const LeitnerState()
          : LeitnerState(
              box: (row['box'] as int?) ?? 0,
              streak: (row['streak'] as int?) ?? 0,
              peakBox: (row['peak_box'] as int?) ?? 0,
              correctCount: (row['correct_count'] as int?) ?? 0,
              wrongCount: (row['wrong_count'] as int?) ?? 0,
              retest: ((row['retest'] as int?) ?? 0) == 1,
            );

      final outcome = Leitner.apply(
        state,
        correct: correct,
        isFirstAnswer: !started,
      );

      // 到期时间：今天还要再考一次就立刻可出，否则按箱位间隔顺延。
      final dueAt = outcome.dueInDays == 0
          ? nowMs
          : nowMs + Duration(days: outcome.dueInDays).inMilliseconds;

      final values = <String, Object?>{
        'word_key': card.wordKey,
        'box': outcome.box,
        'due_at': dueAt,
        'streak': outcome.streak,
        'correct_count': outcome.correctCount,
        'wrong_count': outcome.wrongCount,
        'last_seen_at': nowMs,
        'retest': outcome.retest ? 1 : 0,
        'peak_box': outcome.peakBox,
        'started': 1,
      };

      if (row == null) {
        values['first_seen_at'] = nowMs;
        values['starred'] = 0;
        values['killed'] = 0;
        await txn.insert('study_record', values);
      } else {
        // 首次真正学习时，把星标留下的 first_seen_at = 0 改成今天。
        if (!started) values['first_seen_at'] = nowMs;
        // 用 update 不能用 replace：replace 会先删行再加行，
        // 没写进 values 的 starred / killed 会被重置成默认值。
        await txn.update(
          'study_record',
          values,
          where: 'word_key = ?',
          whereArgs: [card.wordKey],
        );
      }

      await txn.insert('study_log', {
        'word_key': card.wordKey,
        'at': nowMs,
        'correct': correct ? 1 : 0,
        'question_type': card.type.code,
      });

      return AnswerResult(
        box: outcome.box,
        dueInDays: outcome.dueInDays,
        retest: outcome.retest,
        promoted: outcome.promoted,
        demoted: outcome.demoted,
      );
    });
  }

  /// 装配一张卡：定题型、定选项。
  StudyCard _card({
    required Map<String, Object?> row,
    required int box,
    required bool isNew,
    required bool isRetest,
    required int attempts,
    required List<Map<String, Object?>> pool,
  }) {
    final key = row['word_key'] as String;
    final word = (row['word'] as String?) ?? key;
    final pdf = ((row['meaning_pdf'] as String?) ?? '').trim();
    final ecdict = ((row['meaning_ecdict'] as String?) ?? '').trim();
    final meaning = _shortMeaning(pdf.isNotEmpty ? pdf : ecdict);

    var type = QuestionType.values[(_stableHash(key) + attempts) % 3];
    // 中文释义为空时没法出「中 → 英」。
    if (meaning.isEmpty && type == QuestionType.cnToEn) {
      type = QuestionType.enToCn;
    }

    // 认词卡：第一次见，先认一遍，不考。
    if (isNew) {
      return StudyCard(
        wordKey: key,
        word: word,
        phonetic: ((row['phonetic'] as String?) ?? '').trim(),
        meaning: meaning,
        meaningEcdict: ecdict,
        box: 0,
        isNew: true,
        isRetest: false,
        type: QuestionType.recall,
        options: const [],
        answerIndex: -1,
      );
    }

    if (type == QuestionType.recall || meaning.isEmpty) {
      return StudyCard(
        wordKey: key,
        word: word,
        phonetic: ((row['phonetic'] as String?) ?? '').trim(),
        meaning: meaning,
        meaningEcdict: ecdict,
        box: box,
        isNew: false,
        isRetest: isRetest,
        type: QuestionType.recall,
        options: const [],
        answerIndex: -1,
      );
    }

    final wantMeaning = type == QuestionType.enToCn;
    final correctText = wantMeaning ? meaning : word;
    final others = <String>[];
    for (final p in pool) {
      if (others.length >= 3) break;
      final pk = p['word_key'] as String;
      if (pk == key) continue;
      final text = wantMeaning
          ? _shortMeaning(((p['meaning_pdf'] as String?) ?? '').trim().isNotEmpty
              ? (p['meaning_pdf'] as String)
              : ((p['meaning_ecdict'] as String?) ?? ''))
          : ((p['word'] as String?) ?? pk);
      if (text.isEmpty || text == correctText) continue;
      if (others.contains(text)) continue;
      others.add(text);
    }
    // 干扰项凑不齐就退回回忆卡，宁可少一道选择题，不出 3 个选项的选择题。
    if (others.length < 3) {
      return StudyCard(
        wordKey: key,
        word: word,
        phonetic: ((row['phonetic'] as String?) ?? '').trim(),
        meaning: meaning,
        meaningEcdict: ecdict,
        box: box,
        isNew: false,
        isRetest: isRetest,
        type: QuestionType.recall,
        options: const [],
        answerIndex: -1,
      );
    }

    final options = List<String>.filled(4, '');
    final at = _stableHash('$key#opt') % 4;
    options[at] = correctText;
    var oi = 0;
    for (var i = 0; i < 4; i++) {
      if (i == at) continue;
      options[i] = others[oi++];
    }

    return StudyCard(
      wordKey: key,
      word: word,
      phonetic: ((row['phonetic'] as String?) ?? '').trim(),
      meaning: meaning,
      meaningEcdict: ecdict,
      box: box,
      isNew: false,
      isRetest: isRetest,
      type: type,
      options: options,
      answerIndex: at,
    );
  }

  /// 选项里只放一个义项：太长读起来费劲，取第一个分句。
  static String _shortMeaning(String raw) {
    final first = raw.split('\n').first.trim();
    if (first.isEmpty) return '';
    final cut = first.split(RegExp(r'[；;]')).first.trim();
    final text = cut.isEmpty ? first : cut;
    return text.length > 26 ? '${text.substring(0, 26)}…' : text;
  }

  /// 稳定的字符串散列。不用 String.hashCode —— 那个跨版本不保证一致。
  static int _stableHash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }
}
