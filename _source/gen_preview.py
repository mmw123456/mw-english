# -*- coding: utf-8 -*-
"""生成 820 词的可视化预览页（单文件 HTML，内嵌数据）。"""
import csv
import json

with open("../data/words_820.csv", encoding="utf-8-sig", newline="") as f:
    rows = list(csv.DictReader(f))

total = len(rows)
trunc = sum(1 for r in rows if r["pdf_truncated"] == "Y")
phon = sum(1 for r in rows if r["phonetic"].strip())
ec = sum(1 for r in rows if r["meaning_ecdict_full"].strip())

payload = json.dumps(rows, ensure_ascii=False)

html = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>820 词数据核对</title>
<style>
*{box-sizing:border-box}
body{margin:0;background:#f6f7f9;color:#1a1d21;
  font:14px/1.6 -apple-system,"Segoe UI","Microsoft YaHei",sans-serif}
header{position:sticky;top:0;z-index:9;background:#fff;border-bottom:1px solid #e3e6ea;
  padding:14px 20px 12px}
h1{margin:0 0 8px;font-size:17px;font-weight:600}
.stats{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:10px}
.chip{background:#eef1f5;border-radius:6px;padding:3px 9px;font-size:12px;color:#40474f}
.chip b{color:#0b6bcb}
input{width:100%;max-width:420px;padding:8px 11px;border:1px solid #d4d9df;
  border-radius:8px;font-size:14px;outline:none}
input:focus{border-color:#0b6bcb;box-shadow:0 0 0 3px #0b6bcb1a}
main{padding:12px 20px 60px}
table{border-collapse:collapse;width:100%;background:#fff;border-radius:10px;
  overflow:hidden;box-shadow:0 1px 3px #0000000d}
th{background:#f0f3f7;text-align:left;padding:9px 10px;font-size:12px;
  font-weight:600;color:#525a63;position:sticky;top:97px;z-index:5;
  border-bottom:1px solid #e3e6ea}
td{padding:8px 10px;border-bottom:1px solid #f0f2f5;vertical-align:top}
tr:hover td{background:#fafbfc}
.no{color:#8a9199;font-variant-numeric:tabular-nums;width:44px}
.w{font-weight:600;width:140px;word-break:break-word}
.ph{color:#6b7480;font-size:12px;width:110px;font-family:Consolas,monospace}
.pdf{width:30%}
.ec{color:#4a5561;font-size:13px}
.tr td{background:#fffaf0}
.tr:hover td{background:#fff5e0}
.flag{display:inline-block;background:#ffe9b8;color:#8a5a00;border-radius:4px;
  padding:0 5px;font-size:11px;margin-left:5px}
.tag{display:inline-block;background:#eaf2fd;color:#0b5fb0;border-radius:4px;
  padding:0 5px;font-size:11px;margin:0 3px 3px 0}
.miss{color:#c0392b;font-size:12px}
.hidden{display:none}
.empty{padding:40px;text-align:center;color:#8a9199}
</style>
</head>
<body>
<header>
  <h1>820 词数据核对</h1>
  <div class="stats">
    <span class="chip">总条数 <b>__TOTAL__</b></span>
    <span class="chip">有音标 <b>__PHON__</b></span>
    <span class="chip">有 ECDICT 完整释义 <b>__EC__</b></span>
    <span class="chip">PDF 释义被截断 <b>__TRUNC__</b></span>
  </div>
  <input id="q" placeholder="搜单词或释义，例如 prompt / 促使" autocomplete="off">
</header>
<main>
<table>
<thead><tr>
  <th>#</th><th>单词</th><th>音标</th><th>PDF 释义</th><th>ECDICT 完整释义</th><th>标签</th>
</tr></thead>
<tbody id="tb"></tbody>
</table>
<div id="empty" class="empty hidden">没有匹配的词</div>
</main>
<script>
const DATA = __DATA__;
const tb = document.getElementById('tb');
const empty = document.getElementById('empty');
const esc = s => (s||'').replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));

function render(list){
  if(!list.length){ tb.innerHTML=''; empty.classList.remove('hidden'); return; }
  empty.classList.add('hidden');
  tb.innerHTML = list.map(r => {
    const isT = r.pdf_truncated === 'Y';
    const noEc = !r.meaning_ecdict_full.trim();
    const tags = r.tag.trim()
      ? r.tag.trim().split(/\\s+/).filter(Boolean).map(t=>`<span class="tag">${t}</span>`).join('')
      : '<span class="miss">EC 未收录</span>';
    return `<tr class="${isT?'tr':''}">
      <td class="no">${r.no}</td>
      <td class="w">${esc(r.word)}</td>
      <td class="ph">${esc(r.phonetic)}</td>
      <td class="pdf">${esc(r.meaning_pdf)}${isT?'<span class="flag">截断</span>':''}</td>
      <td class="ec">${noEc?'<span class="miss">—</span>':esc(r.meaning_ecdict_full)}</td>
      <td>${tags}</td>
    </tr>`;
  }).join('');
}
render(DATA);

let t;
document.getElementById('q').addEventListener('input', e => {
  clearTimeout(t);
  t = setTimeout(() => {
    const k = e.target.value.trim().toLowerCase();
    if(!k){ render(DATA); return; }
    render(DATA.filter(r =>
      r.word.toLowerCase().includes(k) ||
      r.meaning_pdf.toLowerCase().includes(k) ||
      r.meaning_ecdict_full.toLowerCase().includes(k)));
  }, 120);
});
</script>
</body>
</html>"""

html = (html.replace("__TOTAL__", str(total))
            .replace("__PHON__", str(phon))
            .replace("__EC__", str(ec))
            .replace("__TRUNC__", str(trunc))
            .replace("__DATA__", payload))

out = "../data/words_820_preview.html"
with open(out, "w", encoding="utf-8") as f:
    f.write(html)
print("预览页 ->", out, round(len(html)/1024, 1), "KB")
