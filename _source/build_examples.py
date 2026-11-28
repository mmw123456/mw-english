# -*- coding: utf-8 -*-
"""v0.12.0 例句落地：从 Tatoeba 官方数据包筛 820 词的例句（只落地数据，不动 App）。

数据源（一次性下载，原始包不进 git）：
  _source/tatoeba/eng_sentences_detailed.tsv.bz2
  _source/tatoeba/cmn_sentences_detailed.tsv.bz2
  _source/tatoeba/eng-cmn_links.tsv.bz2

输出：_source/examples_820.json（过滤后的结果，进 App 的只有这份）

筛选口径（用户 2026-11-27 定）：
  1. 每句 4–20 词，必须是完整句（有句末标点）
  2. 除目标词外，每个词的 ECDICT frq <= 5000，或该词本身在 820 词里
  3. 必须有中文译文（英中直链）
  4. 只留词书本义：中文译文命中词书中文义项（>=2 字）
  5. 每词最多 3 条，短句优先
"""
import bz2
import csv
import json
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path

try:
    import zhconv
except ImportError:  # 繁简转换是可选的：没有就原样保留
    zhconv = None

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "_source"
TAT = SRC / "tatoeba"
DB = ROOT / "app" / "assets" / "db" / "dict.sqlite"

MAX_TOKENS = 20
MIN_TOKENS = 4
MIN_PER_WORD_WANT = 2
MAX_PER_WORD = 3
FRQ_LIMIT = 5000

POS_PREFIX = re.compile(
    r"^(?:vt|vi|v|n|adj|adv|ad|a|prep|conj|pron|art|num|int|aux|abbr)\s*[.．]\s*",
    re.I,
)
TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z'\u2019-]*")
CJK_RE = re.compile(r"[\u4e00-\u9fff]")
CONTRACTIONS = [
    ("can't", "can not"), ("won't", "will not"), ("shan't", "shall not"),
    ("n't", " not"), ("'re", " are"), ("'ve", " have"), ("'ll", " will"),
    ("'m", " am"), ("'d", " would"), ("'s", " is"),
]
BAD_WORDS = {
    "fuck", "fucking", "shit", "bitch", "damn", "ass", "asshole", "bastard",
    "crap", "piss", "dick", "whore", "slut", "nigger", "nigga", "rape",
}
# 学习类 App 的例句不做政治 / 种族 / 性 / 自伤内容（不属用户口径，属内容安全兜底）
SENSITIVE = {
    "anti-chinese", "anti-american", "communist", "taiwan", "tibet", "israel",
    "palestin", "jewish", "muslim", "islam", "abortion", "gay", "lesbian",
    "porn", "suicide", "terrorist", "isis", "nazi", "hitler",
}

# ECDICT 的 exchange 缺这几个高频功能词的归并（are / an / does 会查成 frq=0 或 doe）
FUNCTION_LEMMA = {
    "am": "be", "is": "be", "are": "be", "was": "be", "were": "be",
    "been": "be", "being": "be", "an": "a", "does": "do", "did": "do",
    "done": "do", "has": "have", "had": "have", "having": "have",
    "could": "can", "would": "will", "should": "shall", "might": "may",
}


def load_words():
    con = sqlite3.connect(DB)
    rows = con.execute(
        "select no, word, meaning_pdf from my_words order by no"
    ).fetchall()
    con.close()
    return [(no, w, (m or "").strip()) for no, w, m in rows]


def parse_gloss_senses(meaning):
    """把词书中文释义拆成义项串，去掉词性前缀与括号补充语。"""
    s = meaning.replace("…", "").replace("...", "")
    s = re.sub(r"[（(][^）)]*[）)]", "", s)
    parts = re.split(r"[；;，,、/]", s)
    senses = []
    for p in parts:
        p = POS_PREFIX.sub("", p.strip())
        p = p.strip(" 　·:：-—")
        p = re.sub(r"(的|地|得|了)$", "", p)
        if len(p) >= 2 and CJK_RE.search(p):
            senses.append(p)
    # 去重保序
    seen, out = set(), []
    for p in senses:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def load_ecdict():
    """frq 词频表 + 变形→原形表。

    注意 `0:` 字段是「本词的原形」，不是本词的变形：
    `said` 行是 `0:say/1:pd/p:said/d:said/3:saids`，把 `0:` 当变形会把
    `say` 映射成 `said`（v0.12.0 第一版踩过，导致 said / is 全按原形查不到词频）。
    """
    frq = {}
    form2lem = {}
    path = SRC / "ecdict.csv"
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            w = row["word"].lower().strip()
            if not w:
                continue
            try:
                frq[w] = int(row["frq"] or 0)
            except ValueError:
                frq[w] = 0
            ex = row.get("exchange") or ""
            for part in ex.split("/"):
                if ":" not in part:
                    continue
                k, v = part.split(":", 1)
                v = v.strip().lower()
                if not v or v == w:
                    continue
                if k == "0":
                    # 本行是变形，v 才是原形
                    form2lem.setdefault(w, v)
                else:
                    form2lem.setdefault(v, w)
    return frq, form2lem


def lemma_of(tok, form2lem):
    t = tok.lower().strip("'-")
    if not t:
        return ""
    if t in FUNCTION_LEMMA:
        return FUNCTION_LEMMA[t]
    if t in form2lem:
        return form2lem[t]
    if t.endswith("'s"):
        t = t[:-2]
    for suf, rep in (("ies", "y"), ("ied", "y"), ("ing", ""), ("ed", ""), ("es", ""), ("s", "")):
        if t.endswith(suf) and len(t) > len(suf) + 2:
            cand = t[: -len(suf)] + rep
            if cand in form2lem:
                return form2lem[cand]
    return t


def split_contractions(text):
    t = text.lower().replace("\u2019", "'")
    for a, b in CONTRACTIONS:
        t = t.replace(a, b)
    return t


def tokenize(text):
    return TOKEN_RE.findall(text)


def sentence_ok(text):
    s = text.strip()
    if not s or len(s) > 160:
        return False
    if not re.search(r"[.!?][\"')\]]?$", s):
        return False
    if "http" in s or "@" in s:
        return False
    return True


def pick_zh(links, zh_text, senses):
    """从一条英文句子的多个中文译文里挑一条：先过义项，再取最短。"""
    best = None
    for zid in links:
        z = zh_text.get(zid)
        if not z:
            continue
        z = z.strip()
        if not z or not CJK_RE.search(z) or len(z) > 90:
            continue
        if not re.search(r"[。！？!?…]$", z):
            continue  # 译文没有句末标点，界面上会像半句话
        if not any(sen in z for sen in senses):
            continue
        if best is None or len(z) < len(best[1]):
            best = (zid, z)
    return best


def too_similar(a_toks, b_toks):
    """两句词集重合度太高就算同一条（防止 coward 那种三句一个意思）。"""
    a = {t.lower() for t in a_toks}
    b = {t.lower() for t in b_toks}
    if not a or not b:
        return False
    return len(a & b) / len(a | b) >= 0.6


def main():
    words = load_words()
    wset = {w.lower() for _, w, _ in words}
    senses = {w.lower(): parse_gloss_senses(m) for _, w, m in words}
    frq, form2lem = load_ecdict()
    print(f"820 词：{len(words)}；释义可拆出义项的词：{sum(1 for v in senses.values() if v)}", flush=True)

    # 每条词的全部可命中形式（原形 + 变形）
    forms = defaultdict(set)
    for _, w, _ in words:
        lw = w.lower()
        if " " in lw:
            continue
        forms[lw].add(lw)
    for form, lem in form2lem.items():
        if lem in wset:
            forms[lem].add(form)

    # 1) 英中链接：英文 id -> 中文 id 列表
    links = defaultdict(list)
    with bz2.open(TAT / "eng-cmn_links.tsv.bz2", "rt", encoding="utf-8") as f:
        for line in f:
            a, _, b = line.rstrip("\n").partition("\t")
            if a and b:
                links[a].append(b)
    print(f"英中直链：{sum(len(v) for v in links.values())} 对，覆盖英文句 {len(links)} 条", flush=True)

    # 2) 中文句
    zh_text = {}
    with bz2.open(TAT / "cmn_sentences_detailed.tsv.bz2", "rt", encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) >= 3:
                zh_text[p[0]] = p[2]
    print(f"中文句：{len(zh_text)} 条", flush=True)

    # 3) 扫英文句，先按「命中哪个词」粗筛
    cand = defaultdict(list)  # word -> [(en_id, text, toks)]
    scanned = 0
    forms_index = {}
    for w, fs in forms.items():
        for fm in fs:
            forms_index.setdefault(fm, set()).add(w)
    with bz2.open(TAT / "eng_sentences_detailed.tsv.bz2", "rt", encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 3 or p[0] not in links:
                continue
            scanned += 1
            text = p[2]
            if not sentence_ok(text):
                continue
            toks = tokenize(text)
            if not (MIN_TOKENS <= len(toks) <= MAX_TOKENS):
                continue
            low = {t.lower().replace("\u2019", "'") for t in toks}
            hit_words = set()
            for t in low:
                if t in forms_index:
                    hit_words |= forms_index[t]
            if not hit_words:
                continue
            cand_by_word = hit_words
            for w in cand_by_word:
                cand[w].append((p[0], text, toks))
    print(f"扫描英中句 {scanned} 条；初筛后有候选的词 {len(cand)} 个，候选句 {sum(len(v) for v in cand.values())} 条", flush=True)

    # 4) 难度 + 义项 + 排序
    dropped = Counter()
    dropped_strict = Counter()
    offenders = Counter()
    hard_strict_sentences = 0
    out = {}
    out_strict = {}
    for _, word, _ in words:
        w = word.lower()
        pool = cand.get(w, [])
        if not pool:
            dropped["no_sentence"] += 1
            continue
        own_forms = {f for f in forms.get(w, {w})}
        keep, keep_strict = [], []
        for en_id, text, toks in pool:
            hard_strict = False
            hard_lenient = False
            for tok in toks:
                if tok.lower().replace("\u2019", "'") in own_forms:
                    continue
                if re.fullmatch(r"[\d.,%]+", tok):
                    continue  # 数字不算生词
                # 句中/句首大写且不是全大写缩写 → 视为专有名词（Tom / Sunday 这类）
                is_name = tok[0].isupper() and not tok.isupper() and len(tok) > 1
                for piece in split_contractions(tok).replace("-", " ").split():
                    lem = lemma_of(piece, form2lem)
                    if not lem or lem in wset:
                        continue
                    f = frq.get(lem, 0)
                    if f == 0 or f > FRQ_LIMIT:
                        hard_strict = True
                        if not is_name:
                            hard_lenient = True
                        offenders[lem if f else lem + "(frq=0)"] += 1
                        break
                if hard_lenient:
                    break
            if hard_lenient:
                dropped["too_hard"] += 1
                continue
            if hard_strict:
                hard_strict_sentences += 1  # 只统计：靠专有名词例外才留下的句子
            low_toks = {x.lower().replace("\u2019", "'") for x in toks}
            if low_toks & BAD_WORDS or low_toks & SENSITIVE:
                dropped["bad_or_sensitive"] += 1
                continue
            chosen = pick_zh(links.get(en_id, []), zh_text, senses.get(w, []))
            if not chosen:
                dropped["no_zh_or_sense"] += 1
                continue
            zid, z = chosen
            if zhconv is not None:
                z = zhconv.convert(z, "zh-cn")
            item = (len(toks), len(text), en_id, text.strip(), zid, z)
            if not hard_strict:
                keep_strict.append(item)
            keep.append(item)
        for bucket, src in ((out_strict, keep_strict), (out, keep)):
            if not src:
                dropped["all_filtered_strict" if bucket is out_strict else "all_filtered"] += 1
                continue
            src = sorted(src)
            picked, seen, picked_toks = [], set(), []
            for item in src:
                key = re.sub(r"\W+", "", item[3].lower())
                if key in seen:
                    continue
                toks = tokenize(item[3])
                if any(too_similar(toks, pt) for pt in picked_toks):
                    continue
                seen.add(key)
                picked_toks.append(toks)
                picked.append(item)
                if len(picked) >= MAX_PER_WORD:
                    break
            bucket[word] = [
                {
                    "en": t,
                    "zh": z,
                    "source": "Tatoeba",
                    "license": "CC-BY 2.0 FR",
                    "en_id": int(en_id),
                    "zh_id": int(zid),
                }
                for _, _, en_id, t, zid, z in picked
            ]

    # 5) 统计与落盘
    dist = Counter(len(v) for v in out.values())
    total_sent = sum(len(v) for v in out.values())
    stats = {
        "words_total": len(words),
        "words_with_examples": len(out),
        "words_with_2plus": sum(1 for v in out.values() if len(v) >= 2),
        "words_with_3": dist.get(3, 0),
        "words_with_2": dist.get(2, 0),
        "words_with_1": dist.get(1, 0),
        "words_with_0": len(words) - len(out),
        "sentences_total": total_sent,
        "sentences_with_zh": total_sent,
        "strict_no_name_exception": {
            "words_with_examples": len(out_strict),
            "words_with_2plus": sum(1 for v in out_strict.values() if len(v) >= 2),
            "sentences_total": sum(len(v) for v in out_strict.values()),
            "sentences_kept_only_by_name_exception": hard_strict_sentences,
        },
        "dropped": dict(dropped),
        "top_offenders": offenders.most_common(15),
    }
    payload = {
        "source": "Tatoeba",
        "license": "CC-BY 2.0 FR",
        "url": "https://tatoeba.org",
        "fetched": "2026-11-27",
        "rules": {
            "max_tokens": MAX_TOKENS,
            "min_tokens": MIN_TOKENS,
            "frq_limit": FRQ_LIMIT,
            "per_word_max": MAX_PER_WORD,
            "sense_match": "中文译文命中词书义项",
        },
        "stats": stats,
        "examples": out,
    }
    dest = SRC / "examples_820.json"
    dest.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False, indent=1))
    print(f"写入 {dest}（{dest.stat().st_size / 1024:.0f} KB）")


if __name__ == "__main__":
    sys.exit(main())
