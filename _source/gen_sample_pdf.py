#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成测试用的小 PDF（`app/test/fixtures/sample_words.pdf`）。

为什么不用真词表 PDF 当测试样本：`_source/*.pdf` 是用户私有资料、已在 .gitignore
里，换台机器 / 新克隆就跑不了测试。这里手写一份 1KB 的纯 ASCII PDF（不压缩），
内容刻意覆盖解析规则：编号行、短语、只有词没有释义的行、空行、页码行。

跑法：python _source/gen_sample_pdf.py
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "app", "test", "fixtures", "sample_words.pdf")

# 每页一组行，故意混排版：
# - 编号行（`1. abandon`）
# - 短语（`take advantage of`，不能拆开）
# - 只有词没有释义（`abandon` 重复一次，测文件内去重）
# - 空行、页码行（表头/页码要整行跳过，不算「没认出来」）
PAGES = [
    [
        "1. abandon v. give up completely",
        "2. take advantage of v. make use of",
        "3. competent adj. having enough skill",
        "abandon",
        "",
        "- 1",
        "4. deliberate adj. done on purpose",
    ],
    [
        "5. immune adj. not affected",
        "6. violate v. break a rule",
        "- 2",
    ],
]

# 页码说明：pdfium 抽出来是 `\r\n` 分隔，测试要验证切行切对了。
FONT_OBJ = 3  # 1 catalog, 2 pages, 3 font, 之后每页占两个对象


def _stream(lines):
    content = ["BT", "/F1 12 Tf", "50 780 Td", "16 TL"]
    for line in lines:
        esc = line.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")
        content.append(f"({esc}) Tj T*")
    content.append("ET")
    return "\n".join(content).encode("ascii")


def build():
    n = len(PAGES)
    # 对象编号：1 catalog / 2 pages / 3 font / 每页 4+2i 是 Page、5+2i 是 Contents
    page_objs = [4 + 2 * i for i in range(n)]
    kids = " ".join(f"{o} 0 R" for o in page_objs)

    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        f"<< /Type /Pages /Kids [{kids}] /Count {n} >>".encode(),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    ]
    for i, lines in enumerate(PAGES):
        stream = _stream(lines)
        contents_obj = page_objs[i] + 1
        objs.append(
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
            f"/Resources << /Font << /F1 {FONT_OBJ} 0 R >> >> "
            f"/Contents {contents_obj} 0 R >>".encode()
        )
        objs.append(
            b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream"
        )

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, body in enumerate(objs, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"

    xref_at = len(out)
    out += f"xref\n0 {len(objs) + 1}\n".encode()
    out += b"0000000000 65535 f \n"
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += (
        f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref_at}\n%%EOF\n"
    ).encode()
    return bytes(out)


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    data = build()
    with open(OUT, "wb") as f:
        f.write(data)
    print(f"写入 {OUT}  {len(data):,} 字节，{len(PAGES)} 页，"
          f"{sum(len(p) for p in PAGES)} 行")


if __name__ == "__main__":
    main()
