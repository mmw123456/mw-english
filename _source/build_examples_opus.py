# -*- coding: utf-8 -*-
"""v0.12.0 例句源第二轮：OPUS（TED2020 / OpenSubtitles）覆盖率实测。

只测覆盖，不接 App。筛选口径与 Tatoeba 那轮一致（见 build_examples.py 文件头）：
  1. 每句 4–20 词，完整句（英文有句末标点）
  2. 除目标词外，每个词的 ECDICT frq <= 5000，或该词本身在 820 词里（专有名词另计）
  3. 必须有中文译文（OPUS 是 1:1 对齐，取同行）
  4. 只留词书本义：中文译文命中词书中文义项（>=2 字）
  5. 每词最多 3 条，短句优先

与 Tatoeba 那轮的两处差异（均为口径修正，会在报告里写明）：
  a. 中文先转简体再比义项（Tatoeba 轮是拿繁体原文比简体义项，会把繁体行误杀）
  b. 中文译文不强制句末标点（字幕语料普遍不带句号），但优先选带标点的

用法：python _source/build_examples_opus.py TED2020
"""
import json
import os
import re
import sys
import time
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

from build_examples import (
    BAD_WORDS,
    FRQ_LIMIT,
    MAX_PER_WORD,
    MAX_TOKENS,
    MIN_TOKENS,
    SENSITIVE,
    lemma_of,
    load_ecdict,
    load_words,
    parse_gloss_senses,
    sentence_ok,
    split_contractions,
    tokenize,
    too_similar,
)

try:
    import zhconv
except ImportError:
    zhconv = None

SRC = Path(__file__).resolve().parent
OPUS = SRC / "opus"

# 语料 -> (zip 文件, 语言对前缀, 出处署名, 许可)
CORPORA = {
    "TED2020": (
        "ted2020.en-zh.txt.zip",
        "TED2020.en-zh",
        "TED2020 (via OPUS)",
        "TED Talks Usage Policy（非商用，需署名）",
    ),
    "OpenSubtitles": (
        "opensubtitles.en-zh.txt.zip",
        "OpenSubtitles.en-zh",
        "OpenSubtitles v2016 (via OPUS)",
        "OPUS 标注：开放字幕，需署名，具体以 opus.nlpl.eu/OpenSubtitles.php 为准",
    ),
}

ZH_END = re.compile(r"[。！？!?…]$")
CJK = re.compile(r"[\u4e00-\u9fff]")
CANTONESE = re.compile(r"[嘅喺係咗佢哋啲嚟冇咁]")
POOL_CAP = 80  # 每词候选池上限（只留最短的），防止 OpenSubtitles 撑爆内存
# 默认丢掉粤语译文；设 OPUS_KEEP_CANTONESE=1 可关掉该过滤（用于对比口径）
DROP_CANTONESE = os.environ.get("OPUS_KEEP_CANTONESE") != "1"


def build_forms(words, form2lem):
    wset = {w.lower() for _, w, _ in words}
    forms = defaultdict(set)
    for _, w, _ in words:
        lw = w.lower()
        if " " not in lw:
            forms[lw].add(lw)
    for form, lem in form2lem.items():
        if lem in wset:
            forms[lem].add(form)
    forms_index = {}
    for w, fs in forms.items():
        for f in fs:
            forms_index.setdefault(f, set()).add(w)
    return forms, forms_index


def run(name):
    fn, prefix, source, license_ = CORPORA[name]
    zip_path = OPUS / fn
    if not zip_path.exists():
        raise SystemExit(f"缺文件：{zip_path}，先跑 fetch_opus.py {name}")

    t0 = time.time()
    words = load_words()
    wset = {w.lower() for _, w, _ in words}
    senses = {w.lower(): parse_gloss_senses(m) for _, w, m in words}
    frq, form2lem = load_ecdict()
    forms, forms_index = build_forms(words, form2lem)
    print(f"[{name}] 820 词，义项可用 {sum(1 for v in senses.values() if v)}，"
          f"耗时 {time.time() - t0:.0f}s", flush=True)

    zf = zipfile.ZipFile(zip_path)
    en_f = zf.open(f"{prefix}.en")
    zh_f = zf.open(f"{prefix}.zh")

    pools = defaultdict(list)
    dropped = Counter()
    offenders = Counter()
    pairs = 0
    en_cand = 0
    strict_zh_hits = 0
    cantonese_rows = 0

    for raw_en, raw_zh in zip(en_f, zh_f):
        pairs += 1
        text = raw_en.decode("utf-8", "replace").strip()
        zraw = raw_zh.decode("utf-8", "replace").strip()
        if not text or not zraw:
            dropped["empty"] += 1
            continue
        if CANTONESE.search(zraw):
            cantonese_rows += 1
        if not sentence_ok(text):
            dropped["not_sentence"] += 1
            continue
        toks = tokenize(text)
        if not (MIN_TOKENS <= len(toks) <= MAX_TOKENS):
            dropped["bad_len"] += 1
            continue
        low = {t.lower().replace("\u2019", "'") for t in toks}
        hits = set()
        for t in low:
            if t in forms_index:
                hits |= forms_index[t]
        if not hits:
            continue
        en_cand += 1
        if low & BAD_WORDS or low & SENSITIVE:
            dropped["bad_or_sensitive"] += 1
            continue
        z = zhconv.convert(zraw, "zh-cn") if zhconv is not None else zraw
        if not CJK.search(z) or len(z) > 90:
            dropped["zh_unusable"] += 1
            continue
        if CANTONESE.search(z):
            # zhconv 只做繁简，不做粤语→普通话；带粤语虚词的译文对普通话学习者是错的
            if DROP_CANTONESE:
                dropped["cantonese"] += 1
                continue
            dropped["cantonese_kept"] += 1
        z_end = bool(ZH_END.search(z))
        if z_end:
            strict_zh_hits += 1

        for w in hits:
            own = forms.get(w, {w})
            hard_strict = False
            hard = False
            for tok in toks:  # 用原大小写判断专有名词
                key = tok.lower().replace("\u2019", "'")
                if key in own:
                    continue
                if re.fullmatch(r"[\d.,%]+", tok):
                    continue
                is_name = tok[0].isupper() and not tok.isupper() and len(tok) > 1
                for piece in split_contractions(tok).replace("-", " ").split():
                    lem = lemma_of(piece, form2lem)
                    if not lem or lem in wset:
                        continue
                    f = frq.get(lem, 0)
                    if f == 0 or f > FRQ_LIMIT:
                        hard_strict = True
                        if not is_name:
                            hard = True
                        offenders[lem if f else lem + "(frq=0)"] += 1
                        break
                if hard:
                    break
            if hard:
                dropped["too_hard"] += 1
                continue
            if not any(sen in z for sen in senses.get(w, [])):
                dropped["sense_mismatch"] += 1
                continue
            # 收紧口径（字幕语料去噪）：中文带句末标点、中文无拉丁字母（未译残留）、
            # 英文不是对话残片（开头横线 / 句中横线 / 省略号）、中英长度比正常
            tight = (
                z_end
                and not re.search(r"[A-Za-z]", z)
                and not text.lstrip().startswith("-")
                and " - " not in text
                and "..." not in text
                and "…" not in text
                and 0.5 <= len(z) / max(1, len(toks)) <= 3.0
            )
            item = (0 if z_end else 1, len(toks), len(text), text, z)
            pool = pools[w]
            if len(pool) < POOL_CAP:
                pool.append((item, hard_strict, tight))
            else:
                worst = max(x[0] for x in pool)
                if item < worst:
                    pool.remove(max(pool, key=lambda x: x[0]))
                    pool.append((item, hard_strict, tight))
        if pairs % 1000000 == 0:
            print(f"  已扫 {pairs // 1000000}M 对，{time.time() - t0:.0f}s", flush=True)

    print(f"[{name}] 对齐句对 {pairs}；含目标词的候选 {en_cand}；"
          f"有候选的词 {len(pools)}；耗时 {time.time() - t0:.0f}s", flush=True)

    out = {}
    out_strict = {}
    out_tight = {}
    for _, word, _ in words:
        w = word.lower()
        pool = pools.get(w)
        if not pool:
            continue
        for bucket, only_strict, only_tight in (
            (out_strict, True, False),
            (out_tight, False, True),
            (out, False, False),
        ):
            src = sorted(
                x[0]
                for x in pool
                if (x[1] or not only_strict) and (x[2] or not only_tight)
            )
            picked, seen, picked_toks = [], set(), []
            for item in src:
                _, _, _, text, z = item
                key = re.sub(r"\W+", "", text.lower())
                if key in seen:
                    continue
                tk = tokenize(text)
                if any(too_similar(tk, pt) for pt in picked_toks):
                    continue
                seen.add(key)
                picked_toks.append(tk)
                picked.append(item)
                if len(picked) >= MAX_PER_WORD:
                    break
            if not picked:
                continue
            bucket[word] = [
                {"en": text, "zh": z, "source": source, "license": license_}
                for _, _, _, text, z in picked
            ]

    dist = Counter(len(v) for v in out.values())
    stats = {
        "corpus": name,
        "license": license_,
        "pairs_total": pairs,
        "pairs_with_target_word": en_cand,
        "cantonese_like_rows": cantonese_rows,
        "words_total": len(words),
        "words_with_examples": len(out),
        "words_with_2plus": sum(1 for v in out.values() if len(v) >= 2),
        "words_with_3": dist.get(3, 0),
        "words_with_2": dist.get(2, 0),
        "words_with_1": dist.get(1, 0),
        "words_with_0": len(words) - len(out),
        "sentences_total": sum(len(v) for v in out.values()),
        "sentences_with_zh": sum(len(v) for v in out.values()),
        "zh_with_final_punct": strict_zh_hits,
        "strict_no_name_exception": {
            "words_with_examples": len(out_strict),
            "words_with_2plus": sum(1 for v in out_strict.values() if len(v) >= 2),
            "sentences_total": sum(len(v) for v in out_strict.values()),
        },
        "tight": {
            "words_with_examples": len(out_tight),
            "words_with_2plus": sum(1 for v in out_tight.values() if len(v) >= 2),
            "sentences_total": sum(len(v) for v in out_tight.values()),
        },
        "dropped": dict(dropped),
        "top_offenders": offenders.most_common(15),
        "elapsed_sec": round(time.time() - t0, 1),
    }
    suffix = "" if DROP_CANTONESE else "_raw"
    dest = SRC / f"examples_820_{name.lower()}{suffix}.json"
    payload = {
        "source": source,
        "license": license_,
        "url": "https://opus.nlpl.eu",
        "fetched": "2026-11-27",
        "rules": {
            "max_tokens": MAX_TOKENS,
            "min_tokens": MIN_TOKENS,
            "frq_limit": FRQ_LIMIT,
            "per_word_max": MAX_PER_WORD,
            "sense_match": "中文译文命中词书义项（先转简体）",
            "zh_final_punct_required": False,
        },
        "stats": stats,
        "examples": out,
        "examples_tight": out_tight,
    }
    dest.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False, indent=1))
    print(f"写入 {dest}（{dest.stat().st_size / 1024:.0f} KB）")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in CORPORA:
        raise SystemExit("用法：build_examples_opus.py <TED2020|OpenSubtitles>")
    sys.exit(run(sys.argv[1]))
