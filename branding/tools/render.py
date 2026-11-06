#!/usr/bin/env python3
"""Render every PeplowPC OS brand asset from the brand tokens and the browser's icon.svg.

Usage (from the repo root):
    pip install fonttools uharfbuzz
    python3 branding/tools/render.py

Needs rsvg-convert (librsvg) on PATH for PNG output.
Writes SVG sources to branding/src and installs PNG/SVG files into system_files/.
Text is converted to outlines, so the installed system never depends on brand fonts.
"""

import io
import subprocess
from pathlib import Path

import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "branding" / "src"
SYS = ROOT / "system_files"
FONT = ROOT / "branding" / "fonts" / "bricolage-grotesque.ttf"

# Brand tokens (match peplowpc.com and peplowpc-browser/branding/README.md)
INK = "#0B0D14"
SURFACE = "#141826"
SURFACE_2 = "#1C2133"
BORDER = "#2A3048"
CREAM = "#F4F1EA"
MUTED = "#A9B0C2"
LIME = "#C6F432"

# The P tile from peplowpc-browser/branding/icon.svg, in a 64x64 box.
TILE_RECT = '<rect x="6" y="6" width="52" height="52" rx="14" fill="{fill}" transform="rotate(-6 32 32)"/>'
TILE_P = ('<path d="M24 46V18h10.5c6.2 0 10 3.4 10 8.8S40.7 35.6 34.5 35.6H30.6V46z '
          'M30.6 30.4h3.6c2.6 0 4-1.3 4-3.6s-1.4-3.5-4-3.5h-3.6z" fill="{fill}"/>')


def tile(x, y, size, tile_fill=LIME, p_fill=INK, extra=""):
    s = size / 64
    return (f'<g transform="translate({x:.2f} {y:.2f}) scale({s:.4f})" {extra}>'
            + TILE_RECT.format(fill=tile_fill) + TILE_P.format(fill=p_fill) + "</g>")


# ---------------------------------------------------------------- text to outlines
_font_cache = {}


def _font(wght):
    if wght not in _font_cache:
        vf = TTFont(FONT)
        static = instantiateVariableFont(vf, {"wght": wght})
        buf = io.BytesIO()
        static.save(buf)
        data = buf.getvalue()
        _font_cache[wght] = (TTFont(io.BytesIO(data)), hb.Font(hb.Face(data)))
    return _font_cache[wght]


def text_path(text, size, x, y, wght=800, tracking=0.0):
    """SVG path data for text with baseline at (x, y). Returns (d, advance_width)."""
    tt, hbfont = _font(wght)
    upem = tt["head"].unitsPerEm
    scale = size / upem
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(hbfont, buf, {"kern": True, "liga": True})
    glyphset = tt.getGlyphSet()
    order = tt.getGlyphOrder()
    pen = SVGPathPen(glyphset)
    cx = 0.0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        name = order[info.codepoint]
        t = TransformPen(pen, (scale, 0, 0, -scale, x + (cx + pos.x_offset) * scale, y - pos.y_offset * scale))
        glyphset[name].draw(t)
        cx += pos.x_advance + tracking * upem
    return pen.getCommands(), cx * scale


def cap_height(size, wght=800):
    tt, _ = _font(wght)
    os2 = tt["OS/2"]
    ch = getattr(os2, "sCapHeight", 0) or int(tt["head"].unitsPerEm * 0.7)
    return ch / tt["head"].unitsPerEm * size


# ---------------------------------------------------------------- wordmark
def wordmark(text_fill, x, y, size, with_os=False, os_fill=LIME):
    """PeplowPC wordmark: tilted P tile followed by 'eplowPC' (optionally ' OS'). Baseline at y."""
    ch = cap_height(size)
    tsize = ch * 1.62           # tile box, as on the business card
    tx = x
    ty = y - ch - (tsize - ch) * 0.62
    parts = [tile(tx, ty, tsize)]
    d, w = text_path("eplowPC", size, tx + tsize * 0.93, y)
    parts.append(f'<path d="{d}" fill="{text_fill}"/>')
    end = tx + tsize * 0.93 + w
    if with_os:
        d2, w2 = text_path("OS", size, end + size * 0.24, y)
        parts.append(f'<path d="{d2}" fill="{os_fill}"/>')
        end += size * 0.24 + w2
    bbox = (x, ty, end - x, (y + size * 0.26) - ty)  # include descender of 'p'
    return "\n".join(parts), bbox


def svg_doc(w, h, body, bg=None):
    rect = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f"{rect}{body}</svg>\n")


def save(name, svg):
    SRC.mkdir(parents=True, exist_ok=True)
    p = SRC / name
    p.write_text(svg)
    return p


def png(svg_path, out, width=None, height=None):
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["rsvg-convert", str(svg_path), "-o", str(out)]
    if width:
        cmd += ["-w", str(width)]
    if height:
        cmd += ["-h", str(height)]
    subprocess.run(cmd, check=True)
    print("wrote", out.relative_to(ROOT))


# ---------------------------------------------------------------- assets
def dot_grid(w, h, step, r, fill, opacity):
    return (f'<defs><pattern id="dots" width="{step}" height="{step}" patternUnits="userSpaceOnUse">'
            f'<circle cx="{step/2}" cy="{step/2}" r="{r}" fill="{fill}" fill-opacity="{opacity}"/></pattern></defs>'
            f'<rect width="{w}" height="{h}" fill="url(#dots)"/>')


def glow(cx, cy, r, color, opacity, gid):
    return (f'<defs><radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}" gradientUnits="userSpaceOnUse">'
            f'<stop offset="0" stop-color="{color}" stop-opacity="{opacity}"/>'
            f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient></defs>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#{gid})"/>')


def wallpaper_dots():
    W, H = 3840, 2160
    body = dot_grid(W, H, 52, 2.6, MUTED, 0.13)
    body += glow(2660, 1420, 1300, LIME, 0.11, "g1")  # centered behind the tile
    body += glow(W * 0.08, H * 0.04, 1100, "#5B6BFF", 0.06, "g2")
    # Tile with an outline echo, kept inside the area that survives GNOME's "zoom" crop on every
    # common screen shape. On a 4:3 screen only the middle 2880 px of this 3840 px image show
    # (x 480 to 3360), so the tile and its echo stay within that box with a margin.
    size = 880
    x, y = 3360 - size - 260, H - size - 300
    body += (f'<g transform="translate({x - 90:.0f} {y - 70:.0f}) scale({size/64:.3f})">'
             f'<rect x="6" y="6" width="52" height="52" rx="14" fill="none" stroke="{LIME}" '
             f'stroke-opacity="0.28" stroke-width="0.35" transform="rotate(6 32 32)"/></g>')
    body += tile(x, y, size)
    return svg_doc(W, H, body, bg=INK)


def wallpaper_tile():
    W, H = 3840, 2160
    body = dot_grid(W, H, 52, 2.6, MUTED, 0.13)
    body += glow(W / 2, H / 2, 1300, LIME, 0.12, "g1")
    size = 640
    body += tile(W / 2 - size / 2, H / 2 - size / 2, size)
    return svg_doc(W, H, body, bg=INK)


def plymouth_watermark():
    mark, (bx, by, bw, bh) = wordmark(CREAM, 0, 0, 120, with_os=True)
    pad = 8
    body = f'<g transform="translate({-bx + pad:.1f} {-by + pad:.1f})">{mark}</g>'
    return svg_doc(round(bw + 2 * pad), round(bh + 2 * pad), body)


def gdm_logo():
    # GDM shows this small at the bottom of the login screen.
    return plymouth_watermark()


def about_logo(text_fill):
    mark, (bx, by, bw, bh) = wordmark(text_fill, 0, 0, 120, with_os=True,
                                      os_fill=LIME if text_fill == CREAM else "#4A6200")
    body = f'<g transform="translate({-bx:.1f} {-by:.1f})">{mark}</g>'
    return svg_doc(round(bw), round(bh), body)


def icon():
    return svg_doc(64, 64, TILE_RECT.format(fill=LIME) + TILE_P.format(fill=INK))


def preview(paths, out):
    """One image showing every asset, for review."""
    from PIL import Image, ImageDraw, ImageFont
    ims = [(label, Image.open(p).convert("RGBA")) for label, p in paths]
    W = max(im.width for _, im in ims) + 80
    H = sum(im.height + 70 for _, im in ims) + 30
    sheet = Image.new("RGBA", (W, H), SURFACE)
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(str(FONT.parent / "inter.ttf"), 20)
    except OSError:
        font = ImageFont.load_default()
    y = 30
    for label, im in ims:
        draw.text((40, y), label, fill=MUTED, font=font)
        sheet.alpha_composite(im, (40, y + 32))
        y += im.height + 70
    sheet.convert("RGB").save(out)
    print("wrote", out.relative_to(ROOT))


def main():
    bg = SYS / "usr/share/backgrounds/peplowpc"
    png(save("wallpaper-dots.svg", wallpaper_dots()), bg / "peplowpc-dots.png")
    png(save("wallpaper-tile.svg", wallpaper_tile()), bg / "peplowpc-tile.png")

    wm = save("plymouth-watermark.svg", plymouth_watermark())
    png(wm, SYS / "usr/share/plymouth/themes/peplowpc/watermark.png", height=88)
    png(save("gdm-logo.svg", gdm_logo()), SYS / "usr/share/pixmaps/peplowpc-gdm-logo.png", height=96)

    apps = SYS / "usr/share/icons/hicolor/scalable/apps"
    apps.mkdir(parents=True, exist_ok=True)
    (apps / "peplowpc-logo.svg").write_text(icon())
    (apps / "peplowpc-logo-text.svg").write_text(about_logo(INK))        # light backgrounds
    (apps / "peplowpc-logo-text-dark.svg").write_text(about_logo(CREAM))  # dark backgrounds
    for n in ("peplowpc-logo.svg", "peplowpc-logo-text.svg", "peplowpc-logo-text-dark.svg"):
        print("wrote", (apps / n).relative_to(ROOT))
    pix = SYS / "usr/share/pixmaps"
    png(apps / "peplowpc-logo.svg", pix / "peplowpc-logo.png", width=256)

    # Review sheet
    tmp = ROOT / "branding" / "previews"
    tmp.mkdir(exist_ok=True)
    png(SRC / "wallpaper-dots.svg", tmp / "dots-small.png", width=760)
    png(SRC / "wallpaper-tile.svg", tmp / "tile-small.png", width=760)
    png(apps / "peplowpc-logo-text-dark.svg", tmp / "about-dark.png", height=70)
    png(apps / "peplowpc-logo-text.svg", tmp / "about-light.png", height=70)
    preview([
        ("Desktop wallpaper (peplowpc-dots)", tmp / "dots-small.png"),
        ("Lock screen / alt wallpaper (peplowpc-tile)", tmp / "tile-small.png"),
        ("Boot splash + login logo", SYS / "usr/share/plymouth/themes/peplowpc/watermark.png"),
        ("Settings > About (dark)", tmp / "about-dark.png"),
        ("Settings > About (light)", tmp / "about-light.png"),
    ], ROOT / "branding" / "assets-preview.png")


if __name__ == "__main__":
    main()
