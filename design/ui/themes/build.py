#!/usr/bin/env python3
"""Builds catppuccin.json from the palette and the token mapping, and checks contrast.

Usage: python3 -I design/ui/themes/build.py [--table]
Writes catppuccin.json next to this file. --table prints the contrast results as Markdown.
Exits 1 if any checked pair fails, so it doubles as the test design-system.md cites.
"""
import colorsys, json, sys
from pathlib import Path

# github.com/catppuccin/palette palette.json, verified 2026-10-16.
PALETTE = {
    "latte": dict(rosewater="#dc8a78", flamingo="#dd7878", pink="#ea76cb", mauve="#8839ef", red="#d20f39", maroon="#e64553", peach="#fe640b", yellow="#df8e1d", green="#40a02b", teal="#179299", sky="#04a5e5", sapphire="#209fb5", blue="#1e66f5", lavender="#7287fd", text="#4c4f69", subtext1="#5c5f77", subtext0="#6c6f85", overlay2="#7c7f93", overlay1="#8c8fa1", overlay0="#9ca0b0", surface2="#acb0be", surface1="#bcc0cc", surface0="#ccd0da", base="#eff1f5", mantle="#e6e9ef", crust="#dce0e8"),
    "frappe": dict(rosewater="#f2d5cf", flamingo="#eebebe", pink="#f4b8e4", mauve="#ca9ee6", red="#e78284", maroon="#ea999c", peach="#ef9f76", yellow="#e5c890", green="#a6d189", teal="#81c8be", sky="#99d1db", sapphire="#85c1dc", blue="#8caaee", lavender="#babbf1", text="#c6d0f5", subtext1="#b5bfe2", subtext0="#a5adce", overlay2="#949cbb", overlay1="#838ba7", overlay0="#737994", surface2="#626880", surface1="#51576d", surface0="#414559", base="#303446", mantle="#292c3c", crust="#232634"),
    "macchiato": dict(rosewater="#f4dbd6", flamingo="#f0c6c6", pink="#f5bde6", mauve="#c6a0f6", red="#ed8796", maroon="#ee99a0", peach="#f5a97f", yellow="#eed49f", green="#a6da95", teal="#8bd5ca", sky="#91d7e3", sapphire="#7dc4e4", blue="#8aadf4", lavender="#b7bdf8", text="#cad3f5", subtext1="#b8c0e0", subtext0="#a5adcb", overlay2="#939ab7", overlay1="#8087a2", overlay0="#6e738d", surface2="#5b6078", surface1="#494d64", surface0="#363a4f", base="#24273a", mantle="#1e2030", crust="#181926"),
    "mocha": dict(rosewater="#f5e0dc", flamingo="#f2cdcd", pink="#f5c2e7", mauve="#cba6f7", red="#f38ba8", maroon="#eba0ac", peach="#fab387", yellow="#f9e2af", green="#a6e3a1", teal="#94e2d5", sky="#89dceb", sapphire="#74c7ec", blue="#89b4fa", lavender="#b4befe", text="#cdd6f4", subtext1="#bac2de", subtext0="#a6adc8", overlay2="#9399b2", overlay1="#7f849c", overlay0="#6c7086", surface2="#585b70", surface1="#45475a", surface0="#313244", base="#1e1e2e", mantle="#181825", crust="#11111b"),
}
FLAVORS = [("latte", "Latte", "light"), ("frappe", "Frappé", "dark"), ("macchiato", "Macchiato", "dark"), ("mocha", "Mocha", "dark")]

# One mapping by palette name, held across all four Flavors.
MAPPING = {
    "background": "base", "backgroundElevated": "surface0", "backgroundRecessed": "mantle",
    "border": "surface1", "selection": "surface1", "rowHover": "surface0",
    "text": "text", "textSecondary": "subtext1", "textTertiary": "subtext0", "textDisabled": "overlay2",
    "textOnAccent": "base",
    "accent": "blue", "focusRing": "blue",
    "methodGet": "green", "methodPost": "peach", "methodPut": "blue", "methodPatch": "mauve",
    "methodDelete": "red", "methodHead": "teal", "methodOptions": "pink", "methodOther": "subtext0",
    "status1xx": "sky", "status2xx": "green", "status3xx": "sapphire", "status4xx": "peach",
    "status5xx": "red", "statusFailed": "red",
    "jsonKey": "blue", "jsonString": "green", "jsonNumber": "peach", "jsonBoolean": "mauve",
    "jsonNull": "maroon", "jsonPunctuation": "overlay2",
    "xmlTag": "blue", "xmlAttribute": "yellow", "xmlValue": "green",
    "curlFlag": "maroon",
    "variableDefined": "blue", "variableSecret": "mauve", "variableUndefined": "red",
    "dirtyDot": "peach", "warning": "yellow", "error": "red", "success": "green",
}

# Where a Flavor needs a different palette name. Latte has no colour lighter than base, so
# an elevated surface cannot be lighter than the editor; it stays base and is lifted by a
# border and a shadow instead (design-system.md, Surfaces).
OVERRIDES = {"latte": {"backgroundElevated": "base", "rowHover": "mantle", "selection": "surface0"}}

# Approximate fills of NSVisualEffectView .sidebar on a neutral desktop. The real material
# is translucent, so this is an estimate (Open UI questions, Q3).
SIDEBAR = {"light": "#e8e8ea", "dark": "#2a2a2e"}

# `selection` is only text selection. NSTextView draws selected text in `text`
# (selectedTextAttributes), so `text` is the one token checked on it.
TEXT_BGS = ["background", "backgroundElevated", "backgroundRecessed", "rowHover"]
CODE_BGS = ["background", "backgroundRecessed"]
# token -> (minimum ratio, backgrounds it is drawn on). "sidebar" is the native material.
CHECKS = {
    "text": (4.5, TEXT_BGS + ["selection"]),
    **{t: (4.5, TEXT_BGS) for t in ["textSecondary", "textTertiary", "textDisabled"]},
    "textOnAccent": (4.5, ["accent"]),
    "accent": (3.0, ["background", "backgroundElevated"]),
    "focusRing": (3.0, ["background", "backgroundElevated", "backgroundRecessed"]),
    **{t: (4.5, ["background", "backgroundElevated", "backgroundRecessed", "rowHover", "sidebar"])
       for t in MAPPING if t.startswith("method")},
    **{t: (4.5, ["background", "backgroundRecessed"]) for t in MAPPING if t.startswith("status")},
    # The Curl pane's box is `background` inside the `backgroundRecessed` inspector.
    **{t: (4.5, CODE_BGS) for t in MAPPING if t.startswith(("json", "xml", "curl"))},
    **{t: (4.5, ["background", "backgroundElevated", "backgroundRecessed", "rowHover"]) for t in MAPPING if t.startswith("variable")},
    "dirtyDot": (3.0, ["background", "backgroundRecessed", "rowHover"]),
    **{t: (4.5, ["background", "backgroundElevated", "backgroundRecessed"]) for t in ["warning", "error", "success"]},
}


def rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


def lum(h):
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in rgb(h)]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def ratio(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)


def shift(h, dl):
    hh, l, s = colorsys.rgb_to_hls(*rgb(h))
    return "#" + "".join(f"{round(x * 255):02x}" for x in colorsys.hls_to_rgb(hh, min(1, max(0, l + dl)), s))


assert round(ratio("#000000", "#ffffff"), 1) == 21.0
assert ratio("#777777", "#ffffff") < 4.5 < ratio("#767676", "#ffffff")


def build(key, appearance):
    pal = PALETTE[key]
    names = {**MAPPING, **OVERRIDES.get(key, {})}
    colors = {t: pal[n] for t, n in names.items()}
    bg = lambda b: SIDEBAR[appearance] if b == "sidebar" else colors[b]
    adjusted, rows = {}, []
    # A token that fails moves away from the background in HLS lightness, 2% a step, until
    # every pair passes: hue and saturation stay Catppuccin's, and the shift is recorded.
    away = -0.02 if appearance == "light" else 0.02
    for t, (need, bgs) in CHECKS.items():
        if t == "textOnAccent":
            # the label is fixed at `base`; the accent fill moves instead
            t, bgs, test = "accent", ["textOnAccent"], lambda: ratio(colors["textOnAccent"], colors["accent"])
        else:
            test = lambda: min(ratio(colors[t], bg(b)) for b in bgs)
        base_hex, step = colors[t], adjusted.get(t, (0, 0))[1] // 2
        while test() < need and step < 40:
            step += 1
            colors[t] = shift(base_hex, away * step)
        if step:
            adjusted[t] = (names[t], step * 2)
    # accent and focusRing share a palette name; keep them one colour after accent moved
    if "accent" in adjusted:
        colors["focusRing"] = colors["accent"]
    for t, (need, bgs) in CHECKS.items():
        for b in bgs:
            rows.append((t, b, ratio(colors[t], bg(b)), need))
    return colors, adjusted, rows, names


def scheme_markdown(theme):
    flavors = theme["flavors"]
    head = " | ".join(f"{f['name']} ({f['appearance']})" for f in flavors)
    lines = [
        "# Catppuccin color scheme",
        "",
        "Generated by `build.py` from the same data as `catppuccin.json`: edit `MAPPING`,",
        "`OVERRIDES` or `PALETTE` there and rerun, never this file. What each token is drawn as,",
        "and the contrast it was checked for, is `../design-system.md` §2. These colors are for the",
        "themed content areas only; the window, sidebar, toolbar, menus and sheets use the system's",
        "`NSColor` semantic colors (`../design-system.md` §1).",
        "",
        "## Tokens",
        "",
        "A hex that differs from the palette color named is the lightness-adjusted value",
        "(§2, The adjustment rule); a palette name marked `*` is a Latte override.",
        "",
        f"| Token | Palette | {head} |",
        "|---|---|" + "---|" * len(flavors),
    ]
    latte = OVERRIDES.get("latte", {})
    for t, name in MAPPING.items():
        pname = f"{name} (Latte: {latte[t]}*)" if t in latte else name
        lines.append(f"| `{t}` | {pname} | " + " | ".join(f"`{f['colors'][t]}`" for f in flavors) + " |")
    lines += ["", "## Palette", "", "Catppuccin's own values, from github.com/catppuccin/palette.", "",
              "| Color | " + " | ".join(n for _, n, _ in FLAVORS) + " |", "|---|" + "---|" * len(FLAVORS)]
    for color in PALETTE["latte"]:
        lines.append(f"| {color} | " + " | ".join(f"`{PALETTE[k][color]}`" for k, _, _ in FLAVORS) + " |")
    return "\n".join(lines) + "\n"


def main():
    theme = {"name": "Catppuccin", "flavors": []}
    failed, report = False, []
    for key, name, appearance in FLAVORS:
        colors, adjusted, rows, names = build(key, appearance)
        theme["flavors"].append({"name": name, "appearance": appearance, "colors": colors})
        worst = {}
        for t, b, r, need in rows:
            if t not in worst or r < worst[t][1]:
                worst[t] = (b, r, need)
            failed |= r < need
        report.append((name, worst, adjusted, names))
    keys = [set(f["colors"]) for f in theme["flavors"]]
    assert all(k == keys[0] for k in keys), "every Flavor must have every key"
    assert keys[0] == set(MAPPING)
    out = Path(__file__).with_name("catppuccin.json")
    out.write_text(json.dumps(theme, indent=2, ensure_ascii=False) + "\n")
    out.with_suffix(".md").write_text(scheme_markdown(theme))
    appearance_of = {n: a for _, n, a in FLAVORS}
    if "--table" in sys.argv:
        print("| Token | Palette | Min | " + " | ".join(n for n, *_ in report) + " |")
        print("|---|---|---|" + "---|" * len(report))
        for t in CHECKS:
            cells = []
            for name, worst, adjusted, names in report:
                b, r, need = worst[t]
                mark = "" if r >= need else " FAIL"
                adj = f", L{'-' if appearance_of[name] == 'light' else '+'}{adjusted[t][1]}%" if t in adjusted else ""
                pname = names[t] if names[t] != MAPPING[t] else ""
                cells.append(f"{r:.2f} on {b}{adj}{', = ' + pname if pname else ''}{mark}")
            print(f"| `{t}` | {MAPPING[t]} | {CHECKS[t][0]} | " + " | ".join(cells) + " |")
    print("FAIL" if failed else "all pairs pass", file=sys.stderr)
    sys.exit(1 if failed else 0)


main()
