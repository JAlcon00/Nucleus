#!/usr/bin/env python3
"""Calcula la razón de contraste WCAG 2.x entre dos colores.

Uso:
  python3 contrast_check.py FG BG [--alpha A]
  python3 contrast_check.py --pairs pares.json

FG y BG en hex (#RGB, #RRGGBB o #RRGGBBAA). --alpha compone FG sobre BG
con esa opacidad (0-1) antes de medir; útil para texto con opacidad o tintes.
pares.json: [{"name": "caption-on-card", "fg": "#8E8E93", "bg": "#FFFFFF", "alpha": 1}]
"""
import argparse
import json
import sys


def parse_hex(value: str):
    h = value.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) not in (6, 8):
        raise ValueError(f"Color inválido: {value}")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
    return r, g, b, a


def composite(fg, bg, alpha):
    a = fg[3] * alpha
    return tuple(fg[i] * a + bg[i] * (1 - a) for i in range(3))


def luminance(rgb):
    def chan(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (chan(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(fg_hex, bg_hex, alpha=1.0):
    bg = parse_hex(bg_hex)
    fg = composite(parse_hex(fg_hex), bg, alpha)
    l1, l2 = luminance(fg), luminance(bg[:3])
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def verdict(r):
    return {
        "texto_normal_AA_4.5": r >= 4.5,
        "texto_grande_o_icono_AA_3.0": r >= 3.0,
        "texto_normal_AAA_7.0": r >= 7.0,
    }


def report(name, fg, bg, alpha):
    r = ratio(fg, bg, alpha)
    v = verdict(r)
    marks = "  ".join(f"{k}: {'PASA' if ok else 'FALLA'}" for k, ok in v.items())
    label = f"{name}: " if name else ""
    print(f"{label}{fg} sobre {bg} (alpha {alpha:g}) -> {r:.2f}:1  |  {marks}")
    return v["texto_grande_o_icono_AA_3.0"]


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("fg", nargs="?")
    p.add_argument("bg", nargs="?")
    p.add_argument("--alpha", type=float, default=1.0)
    p.add_argument("--pairs", help="JSON con lista de pares a evaluar")
    a = p.parse_args()
    try:
        if a.pairs:
            with open(a.pairs, encoding="utf-8") as f:
                pairs = json.load(f)
            ok = all(report(x.get("name", ""), x["fg"], x["bg"], float(x.get("alpha", 1))) for x in pairs)
            sys.exit(0 if ok else 1)
        if not (a.fg and a.bg):
            p.error("Indica FG y BG, o --pairs")
        report("", a.fg, a.bg, a.alpha)
    except ValueError as e:
        print(e, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
