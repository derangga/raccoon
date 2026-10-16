#!/usr/bin/env python3
"""Turns the canvas sources in src/ (Claude Design .dc.html artboards) into self-contained
HTML mockups beside this file, Latte and Mocha side by side.

Usage: python3 -I design/ui/mockups/build.py
src/ is the copy of the Raccoon UI canvas; edit there, rebuild here.
"""
import re
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "src"
NAMES = {"Main.dc.html": "01-first-launch.html"}
FLAVORS = [("latte", "Latte · light"), ("mocha", "Mocha · dark")]
css = (SRC / "raccoon.css").read_text()

for src in sorted(SRC.glob("*.dc.html")):
    s = src.read_text()
    s = s.replace('<script src="./support.js"></script>\n', "")
    s = s.replace('<link rel="stylesheet" href="./raccoon.css">', "<style>\n" + css + "</style>")
    # the canvas runtime would read {{name}} as a template hole, so the sources route each
    # Variable reference through renderVals as {{v.key}}; take the real text from there
    m = re.search(r"\bv: \{(.*?)\}, flavors", s)
    holes = dict(re.findall(r"(\w+): '([^']*)'", m.group(1))) if m else {}
    s = re.sub(r'<script type="text/x-dc".*?</script>\n', "", s, flags=re.S)
    s = re.sub(r"\{\{v\.(\w+)\}\}", lambda k: holes[k.group(1)], s)
    for tag in ("<x-dc>", "</x-dc>", "<helmet>", "</helmet>"):
        s = s.replace(tag + "\n", "")
    m = re.search(r'<sc-for list="\{\{flavors\}\}"[^>]*>\n(.*?)</sc-for>\n', s, flags=re.S)
    assert m, src.name
    body = "".join(m.group(1).replace("{{f.cls}}", c).replace("{{f.label}}", l) for c, l in FLAVORS)
    s = s[:m.start()] + body + s[m.end():]
    assert "{{f." not in s and "sc-" not in s and "x-dc" not in s, src.name
    out = HERE / NAMES.get(src.name, src.name.replace(".dc.html", ".html"))
    out.write_text(s)
    print(out.name)
