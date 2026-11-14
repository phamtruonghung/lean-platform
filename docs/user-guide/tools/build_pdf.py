#!/usr/bin/env python3
"""Build the user guide's PDF from the Markdown chapters in docs/user-guide/.

The Markdown files stay the source of truth (they are what a browser and GitHub
show); this script only assembles them into one printable document:

  * cover page, table of contents, and a list of the ten diagrams;
  * chapter links (`03-bao-tri.md#kho`) rewritten to in-document anchors, so a
    cross-chapter reference still works inside the PDF;
  * every figure promoted to its own **landscape A4 page**, because a 1400 px
    wide diagram shrunk to portrait width is unreadable when printed;
  * running header, page numbers, and print-safe typography (paged media via
    Chrome's CSS page-margin boxes).

Diagrams come from docs/user-guide/images/*.png, which `diagrams/render.js`
produces from the HTML sources. Images are inlined as data URIs: Chrome's
`--print-to-pdf` on a file:// page silently drops relative <img> sources.

Usage:  python3 docs/user-guide/tools/build_pdf.py [--keep-html]
Exit:   0 on success, non-zero when a chapter, an image, or Chrome is missing.
"""

from __future__ import annotations

import argparse
import atexit
import base64
import datetime
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import markdown
except ImportError:  # pragma: no cover - environment problem, not a doc problem
    sys.exit("python3 has no 'markdown' module; install it (pip install markdown) and retry")

UG = Path(__file__).resolve().parent.parent          # docs/user-guide
REPO = UG.parent.parent                              # repo root
IMAGES = UG / "images"
BUILD = UG / "build"
PDF_OUT = UG / "pdf" / "huong-dan-su-dung.pdf"

# (anchor, short title for the TOC, file). Order is the reading order the guide
# itself recommends; README.md is the introduction.
CHAPTERS = [
    ("ch-gioi-thieu", "Giới thiệu — cách dùng tài liệu này", "README.md"),
    ("ch-00", "Toàn cảnh: các Phân hệ nối với nhau thế nào", "00-tong-quan.md"),
    ("ch-01", "Vào cửa và Tài khoản", "01-vao-cua-va-tai-khoan.md"),
    ("ch-02", "Nhân sự", "02-nhan-su.md"),
    ("ch-03", "Bảo trì", "03-bao-tri.md"),
    ("ch-04", "Hành động", "04-hanh-dong.md"),
    ("ch-05", "Chất lượng", "05-chat-luong.md"),
    ("ch-06", "An toàn", "06-an-toan.md"),
    ("ch-07", "Sản xuất", "07-san-xuat.md"),
    ("ch-08", "Phân tích", "08-phan-tich.md"),
    ("ch-09", "Quản trị", "09-quan-tri.md"),
    ("ch-10", "Xưởng — thiết bị dùng chung trên sàn", "10-xuong-may-thiet-bi.md"),
    ("ch-90", "Phụ lục — 84 mã quyền × 6 vai trò", "90-phu-luc-ma-quyen.md"),
]

CHAPTER_ANCHOR = {file: anchor for anchor, _, file in CHAPTERS}

# A 1400 px diagram rendered at 2× is 2800 px wide. That is more than print
# needs and three times the bytes; 2000 px over a 267 mm landscape page is
# ~190 dpi, and a 128-colour palette PNG is a quarter of the size with an
# imperceptible difference on flat-colour line art.
PRINT_IMAGE_WIDTH = 1700
PRINT_IMAGE_COLORS = 128

CSS = """
@page {
  size: A4;
  margin: 20mm 17mm 18mm;
  /* The margin boxes do not inherit the body font — without this the running
     header and page number are set in the browser's default serif. */
  font-family: "Noto Sans", "DejaVu Sans", sans-serif;
  @top-left  { content: "Hướng dẫn sử dụng Nền tảng · lean-platform"; font-size: 7.5pt; color: #94A3B8; }
  @top-right { content: "Bản __DATE__"; font-size: 7.5pt; color: #94A3B8; }
  @bottom-center { content: counter(page); font-size: 8.5pt; color: #64748B; }
}
@page cover {
  margin: 0;
  @top-left { content: none; } @top-right { content: none; } @bottom-center { content: none; }
}
@page land {
  size: A4 landscape;
  margin: 14mm 13mm 12mm;
  font-family: "Noto Sans", "DejaVu Sans", sans-serif;
}

:root {
  --ink: #1E3A8A; --body: #1F2937; --muted: #475569; --soft: #64748B;
  --rule: #DBEAFE; --accent: #1E40AF; --tint: #EFF6FF;
}
* { box-sizing: border-box; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body {
  font-family: "Noto Sans", "DejaVu Sans", sans-serif;
  font-size: 10.2pt; line-height: 1.55; color: var(--body); margin: 0;
}
p { margin: 0 0 7pt; orphans: 2; widows: 2; }

/* ---------- cover ---------- */
.cover { page: cover; height: 297mm; padding: 42mm 26mm 22mm; break-after: page;
         background: #F8FAFC; border-top: 12mm solid #1E3A8A; }
.cover .eyebrow { font-size: 9pt; letter-spacing: .18em; text-transform: uppercase; color: var(--soft); font-weight: 700; }
.cover h1 { font-size: 34pt; line-height: 1.1; color: var(--ink); margin: 10mm 0 4mm; letter-spacing: -.01em; }
.cover .sub { font-size: 13pt; color: var(--muted); max-width: 140mm; }
.cover .rule { height: 1mm; width: 60mm; background: var(--accent); margin: 12mm 0; }
.cover .meta { font-size: 9.5pt; color: var(--muted); }
.cover .meta strong { color: var(--ink); }
.cover .meta p { margin-bottom: 3pt; }
.cover .toc-hint { margin-top: 30mm; font-size: 9pt; color: var(--soft); border-left: 3px solid var(--rule); padding-left: 8pt; }

/* ---------- table of contents ---------- */
.toc { break-before: page; }
.toc h1 { font-size: 20pt; color: var(--ink); border: none; margin-bottom: 10pt; }
.toc ol { list-style: none; padding: 0; margin: 0 0 14pt; }
.toc ol li { margin: 0 0 5pt; font-size: 10.5pt; }
.toc ol li a { color: var(--body); text-decoration: none; }
.toc ol li .n { display: inline-block; min-width: 20mm; color: var(--soft); font-variant-numeric: tabular-nums; }
.toc h2 { font-size: 12pt; color: var(--ink); margin: 16pt 0 8pt; }
.toc ul.figs { list-style: none; padding: 0; margin: 0; }
.toc ul.figs li { margin-bottom: 4pt; font-size: 9.6pt; color: var(--muted); }
.toc ul.figs li .n { display: inline-block; min-width: 20mm; color: var(--soft); }

/* ---------- chapters ---------- */
section.chapter { break-before: page; }
h1 { font-size: 19pt; line-height: 1.2; color: var(--ink); margin: 0 0 4mm;
     padding-bottom: 3mm; border-bottom: 1.5pt solid var(--rule); }
h2 { font-size: 13pt; color: var(--ink); margin: 9mm 0 3mm; break-after: avoid;
     padding-left: 4mm; border-left: 2.5pt solid var(--accent); }
h3 { font-size: 11pt; color: var(--ink); margin: 6mm 0 2mm; break-after: avoid; }
h4 { font-size: 10pt; color: var(--ink); margin: 4mm 0 2mm; break-after: avoid; }

a { color: var(--accent); text-decoration: none; }
strong { color: var(--ink); }
hr { border: none; border-top: .5pt solid var(--rule); margin: 5mm 0; }

ul, ol { margin: 0 0 7pt; padding-left: 6mm; }
li { margin-bottom: 2pt; break-inside: avoid; }
li > ul, li > ol { margin-top: 2pt; }

blockquote {
  margin: 0 0 8pt; padding: 5pt 8pt; background: #F8FAFC;
  border-left: 2.5pt solid var(--accent); color: var(--muted); break-inside: avoid;
}
blockquote p:last-child { margin-bottom: 0; }
blockquote strong { color: var(--ink); }

code { font-family: "DejaVu Sans Mono", monospace; font-size: 8.6pt;
       background: #F1F5F9; padding: .3mm 1.2mm; border-radius: 1mm; }
pre { background: #F8FAFC; border: .5pt solid var(--rule); border-radius: 2mm;
      padding: 3mm; overflow-x: hidden; break-inside: avoid; }
pre code { background: none; padding: 0; font-size: 8.2pt; }

table { width: 100%; border-collapse: collapse; margin: 0 0 8pt; font-size: 8.6pt; }
thead { background: var(--tint); }
th, td { border: .5pt solid var(--rule); padding: 1.6mm 2mm; text-align: left; vertical-align: top; }
th { color: var(--ink); }
tr { break-inside: avoid; }

/* ---------- figures: one landscape page each ---------- */
figure.fig {
  page: land; break-before: page; break-after: page;
  margin: 0; text-align: center;
}
figure.fig img { width: 100%; max-height: 158mm; object-fit: contain; }
figure.fig figcaption {
  margin: 4mm auto 0; max-width: 225mm; font-size: 8.8pt; color: var(--muted); text-align: left;
}
figure.fig figcaption strong { color: var(--ink); }
figure.fig .tag {
  font-size: 8pt; letter-spacing: .16em; text-transform: uppercase;
  color: var(--soft); font-weight: 700; text-align: left; margin-bottom: 2mm;
}
"""


def chrome_binary() -> str:
    """Find a Chromium that runs headless in this container.

    The ms-playwright build works; the snap build aborts on crashpad/ptrace
    inside the LXC, so it is only used when nothing else exists.
    """
    env = os.environ.get("CHROME")
    if env and Path(env).exists():
        return env
    root = Path("/root/.cache/ms-playwright")
    if root.is_dir():
        builds = sorted(
            (d for d in root.iterdir() if re.fullmatch(r"chromium-\d+", d.name)),
            key=lambda d: int(d.name.split("-")[1]),
        )
        for build in reversed(builds):
            candidate = build / "chrome-linux64" / "chrome"
            if candidate.exists():
                return str(candidate)
    for name in ("chromium", "chromium-browser", "google-chrome"):
        found = shutil.which(name)
        if found:
            return found
    sys.exit("no Chromium found: set CHROME=/path/to/chrome")


def print_copy(image: Path, workdir: Path) -> Path:
    """A smaller copy of a diagram for embedding in the PDF.

    Uses ImageMagick when it is installed and falls back to the master PNG, so
    the build works on a host without it — the PDF is just bigger.
    """
    convert = shutil.which("convert")
    if not convert:
        return image
    out = workdir / image.name
    subprocess.run(
        [convert, str(image), "-resize", f"{PRINT_IMAGE_WIDTH}x", "-strip",
         "-colors", str(PRINT_IMAGE_COLORS), f"PNG8:{out}"],
        check=True, capture_output=True,
    )
    return out


def data_uri(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def rewrite_links(html: str) -> str:
    """Point chapter links at the PDF's own anchors."""

    def repl(match: re.Match) -> str:
        target, fragment = match.group("file"), match.group("frag") or ""
        anchor = CHAPTER_ANCHOR.get(target)
        if anchor is None:
            return match.group(0)
        # A fragment would need the same slug rules as GitHub's; the chapter
        # start is always correct, so a deep link loses only the sub-heading.
        return f'href="#{anchor}"'

    return re.sub(
        r'href="(?P<file>(?:\d\d-[a-z0-9-]+|README)\.md)(?P<frag>#[^"]*)?"',
        repl,
        html,
    )


IMG_P = re.compile(r"<p>\s*<img(?P<attrs>[^>]*)src=\"images/(?P<name>[^\"]+)\"[^>]*>\s*</p>", re.I)
ALT_RE = re.compile(r'alt="(?P<alt>[^"]*)"', re.I)
CAPTION_P = re.compile(r"\s*<p>\s*<em>(?P<cap>.*?)</em>\s*</p>", re.I | re.S)
CAPTION_LABEL = re.compile(r"^<strong>(?P<label>.*?)</strong>\s*", re.S)


def promote_figures(html: str, images: dict[str, str]) -> tuple[str, list[tuple[str, str]]]:
    """Turn `![alt](images/x.png)` + an italic caption into a landscape figure.

    Returns the rewritten HTML and a list of (label, caption) pairs for the TOC.
    """
    captions: list[tuple[str, str]] = []
    out: list[str] = []
    pos = 0
    for match in IMG_P.finditer(html):
        name = match.group("name")
        alt_match = ALT_RE.search(match.group("attrs") or "")
        alt = alt_match.group("alt") if alt_match else name
        if name not in images:
            python_warn(f"image {name} is referenced but not rendered; run diagrams/render.js")
            continue
        rest = html[match.end():]
        cap_match = CAPTION_P.match(rest)
        caption = cap_match.group("cap") if cap_match else ""
        end = match.end() + (cap_match.end() if cap_match else 0)
        # `***Sơ đồ 1.** …` — the strong lead repeats the figure's own title, so
        # the tag on the page carries the title (from alt) and the caption keeps
        # only the prose.
        label_match = CAPTION_LABEL.match(caption)
        if label_match:
            caption = caption[label_match.end():].strip()

        num = re.match(r"Sơ đồ \d+", alt)
        index_label = num.group(0) if num else alt
        short_title = re.sub(r"^Sơ đồ \d+ — ", "", alt)

        out.append(html[pos:match.start()])
        out.append(
            '<figure class="fig">'
            f'<div class="tag">{alt}</div>'
            f'<img src="{images[name]}" alt="{alt.replace(chr(34), "&quot;")}">'
            f"<figcaption>{caption}</figcaption>"
            "</figure>"
        )
        captions.append((index_label, short_title))
        pos = end
    out.append(html[pos:])
    return "".join(out), captions


def python_warn(message: str) -> None:
    print(f"warning: {message}", file=sys.stderr)


def chapter_number(anchor: str) -> str:
    m = re.fullmatch(r"ch-(\d\d)", anchor)
    return m.group(1) if m else ""


def build_html() -> tuple[str, str]:
    date = datetime.date.today().isoformat()
    md = markdown.Markdown(extensions=["tables", "fenced_code", "sane_lists", "attr_list"])

    missing = [f for _, _, f in CHAPTERS if not (UG / f).exists()]
    if missing:
        sys.exit(f"missing chapter files: {', '.join(missing)}")

    rendered_images = sorted(p.name for p in IMAGES.glob("*.png"))
    if not rendered_images:
        sys.exit(f"no diagram PNGs in {IMAGES}; run: node docs/user-guide/diagrams/render.js")
    workdir = Path(tempfile.mkdtemp(prefix="ug-print-"))
    atexit.register(shutil.rmtree, workdir, True)   # the downscaled copies are only for this run
    images = {
        name: data_uri(print_copy(IMAGES / name, workdir)) for name in rendered_images
    }

    sections: list[str] = []
    all_captions: list[tuple[str, str, str]] = []
    toc_entries: list[tuple[str, str, str]] = []

    for anchor, short_title, filename in CHAPTERS:
        md.reset()
        body = md.convert((UG / filename).read_text(encoding="utf-8"))
        body = rewrite_links(body)
        body, captions = promote_figures(body, images)
        all_captions.extend((anchor, label, caption) for label, caption in captions)

        heading = re.search(r"<h1>(?P<text>.*?)</h1>", body, re.S)
        title = re.sub(r"<[^>]+>", "", heading.group("text")).strip() if heading else short_title
        if anchor == "ch-gioi-thieu":
            # README.md's own H1 repeats the cover title; the chapter heading in
            # the PDF names the job instead.
            title = "Giới thiệu — cách dùng tài liệu này"
            if heading:
                body = body[: heading.start()] + f'<h1 id="{anchor}">{title}</h1>' + body[heading.end():]
        elif heading:
            body = body[: heading.start()] + f'<h1 id="{anchor}">{heading.group("text")}</h1>' + body[heading.end():]
        sections.append(f'<section class="chapter">{body}</section>')
        toc_entries.append((anchor, title, short_title))

    def toc_title(anchor: str, title: str) -> str:
        """The number column already carries the chapter number."""
        return title if anchor == "ch-gioi-thieu" else re.sub(r"^\d\d\s*·\s*", "", title)

    toc_rows = "\n".join(
        f'<li><a href="#{anchor}"><span class="n">{chapter_number(anchor)}</span>'
        f"{toc_title(anchor, title)}</a></li>"
        for anchor, title, _ in toc_entries
    )
    fig_rows = "\n".join(
        f'<li><span class="n">{index}</span>{short}</li>'
        for _, index, short in all_captions
    )

    cover = f"""
<div class="cover">
  <div class="eyebrow">lean-platform · Nền tảng quản trị nhà máy</div>
  <h1>Hướng dẫn sử dụng<br>Nền tảng</h1>
  <div class="sub">Dành cho người dùng trên sàn máy và người đào tạo họ — không phải cho
  lập trình viên. Mỗi chức năng là một thẻ bốn phần, đúng thứ tự một người đào tạo sẽ nói.</div>
  <div class="rule"></div>
  <div class="meta">
    <p><strong>{len(CHAPTERS)} chương</strong> · <strong>{len(all_captions)} sơ đồ</strong> · mỗi sơ đồ một trang ngang</p>
    <p>Ứng dụng: relats-lean-platform.digitalciapp.com</p>
    <p>Bản sinh ngày {date} từ <code>docs/user-guide/*.md</code> — đừng sửa tệp PDF này, sửa Markdown rồi dựng lại.</p>
  </div>
  <div class="toc-hint">Muốn in: in hai mặt, khổ A4. Các trang sơ đồ nằm ngang và sẽ tự xoay khi in
  — đọc sơ đồ trên giấy dễ hơn trên màn hình.</div>
</div>
"""

    toc = f"""
<div class="toc">
  <h1>Mục lục</h1>
  <ol>{toc_rows}</ol>
  <h2>{len(all_captions)} sơ đồ</h2>
  <ul class="figs">{fig_rows}</ul>
</div>
"""

    html = f"""<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="utf-8">
<title>Hướng dẫn sử dụng Nền tảng — lean-platform</title>
<style>{CSS.replace("__DATE__", date)}</style>
</head>
<body>
{cover}
{toc}
{"".join(sections)}
</body>
</html>
"""
    return html, date


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-html", action="store_true", help="keep build/user-guide.html for inspection")
    args = parser.parse_args()

    html, date = build_html()
    BUILD.mkdir(parents=True, exist_ok=True)
    html_path = BUILD / "user-guide.html"
    html_path.write_text(html, encoding="utf-8")

    PDF_OUT.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        chrome_binary(),
        "--headless", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage",
        "--no-pdf-header-footer", "--run-all-compositor-stages-before-draw",
        # Chrome prints no /Link annotations for in-page fragments, but it does
        # build a real PDF outline (bookmarks) from the h1–h6 headings — that is
        # how a reader navigates an 86-page manual.
        "--generate-pdf-document-outline",
        f"--print-to-pdf={PDF_OUT}", html_path.as_uri(),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not PDF_OUT.exists():
        print(result.stderr[-4000:], file=sys.stderr)
        return 1

    size = PDF_OUT.stat().st_size
    pages = ""
    if shutil.which("pdfinfo"):
        info = subprocess.run(["pdfinfo", str(PDF_OUT)], capture_output=True, text=True).stdout
        m = re.search(r"^Pages:\s+(\d+)", info, re.M)
        pages = f", {m.group(1)} pages" if m else ""
    print(f"OK {PDF_OUT.relative_to(REPO)} — {size / 1_048_576:.1f} MB{pages}, bản {date}")
    if not args.keep_html:
        html_path.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
