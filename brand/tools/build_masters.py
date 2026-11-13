#!/usr/bin/env python3
"""Genera los SVG maestros de la marca Homita en brand/src/.

Uso:  python3 brand/tools/build_masters.py
Requiere: fontTools (pip install fonttools). La fuente Geist SemiBold ya está en el repo; el
wordmark se convierte a trazados, así que NINGÚN SVG generado depende de la fuente.
Es determinista: ejecutarlo dos veces da los mismos bytes. NO editar brand/src/ a mano:
cambiar la marca = cambiar este script (las constantes de arriba) y regenerar.
"""
import os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
SRC = os.path.join(HERE, '..', 'src')
FONT = os.path.join(ROOT, 'apps/control-ios/Sources/ControlKit/Resources/Fonts/geist_semibold.ttf')

# ── Tokens de marca (fuente única; BRAND.md los repite) ─────────────────────────────────────────
SAGE = '#4F7A63'      # salvia: fondo del icono principal
FOREST = '#2F4A3A'    # bosque: tinta (texto y trazos sobre claro). Nunca negro puro.
TERRA = '#D9663B'     # terracota: acento
MUST = '#E9B44C'      # mostaza: la "luz" del hogar (punto)
MUSTL = '#F6D58A'     # mostaza clara: punto sobre terracota
CREAM = '#F4EFE6'     # crema de marca
BORDER = '#E0CDB4'    # filo del icono claro

# ── Geometría del glifo (cuadrícula 120×120). NO cambiar sin regenerar todo ─────────────────────
STEM = 'M36 24 V96'                    # fuste de la h
ARCH = 'M36 62 L60 42 L84 62 V96'      # hombro de la h = tejado
STROKE_W = 12
DOT = (60, 78, 7)                      # cx, cy, r: la luz del hogar bajo el tejado
RX = 27                                # esquina del icono redondeado (22,5 %)

def glyph(stroke, dot):
    st = f'fill="none" stroke="{stroke}" stroke-width="{STROKE_W}" stroke-linecap="round" stroke-linejoin="round"'
    return (f'<path d="{STEM}" {st}/><path d="{ARCH}" {st}/>'
            f'<circle cx="{DOT[0]}" cy="{DOT[1]}" r="{DOT[2]}" fill="{dot}"/>')

def svg(w, h, body, vb=None, title=None):
    vb = vb or f'0 0 {w} {h}'
    t = f'<title>{title}</title>' if title else ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{vb}">{t}{body}</svg>\n'

def icon(bg, stroke, dot, rounded=True, border=False):
    if rounded and border:
        r = f'<rect x="0.75" y="0.75" width="118.5" height="118.5" rx="{RX-0.5}" fill="{bg}" stroke="{BORDER}" stroke-width="1.5"/>'
    elif rounded:
        r = f'<rect width="120" height="120" rx="{RX}" fill="{bg}"/>'
    else:
        r = f'<rect width="120" height="120" fill="{bg}"/>'
    return r + glyph(stroke, dot)

# ── Wordmark "homita": Geist SemiBold → trazados; el punto de la i es un círculo propio ─────────
font = TTFont(FONT); gs = font.getGlyphSet()
def bounds(n):
    bp = BoundsPen(gs); gs[n].draw(bp); return bp.bounds
HMAX = bounds('h')[3]
TRACK = -12
x = 0; parts = []; idot = None
for g in ['h', 'o', 'm', 'dotlessi', 't', 'a']:
    pen = SVGPathPen(gs); gs[g].draw(TransformPen(pen, (1, 0, 0, -1, x, HMAX))); parts.append(pen.getCommands())
    if g == 'dotlessi':
        b = bounds(g); stem = b[2] - b[0]
        idot = (x + (b[0] + b[2]) / 2, stem * 0.5, HMAX - b[3])
    x += gs[g].width + TRACK
WORD_W = x - TRACK
WORD_D = ' '.join(parts)
DOT_CY = idot[2] - 70 - idot[1]          # 70 u por encima del fuste de la i
WORD_VB_H = HMAX + 44                    # origen y = -34
def word_body(ink, dot):
    return f'<path d="{WORD_D}" fill="{ink}"/><circle cx="{idot[0]:.0f}" cy="{DOT_CY:.0f}" r="{idot[1]:.0f}" fill="{dot}"/>'
def wordmark_svg(ink, dot):
    return svg(round(WORD_W), round(WORD_VB_H), word_body(ink, dot), vb=f'0 -34 {WORD_W:.0f} {WORD_VB_H:.0f}', title='Homita')

# ── Lockups ─────────────────────────────────────────────────────────────────────────────────────
def lockup_h(icon_body, ink, dot, title):
    isz, gap, wh = 96, 26, 64
    s = wh / WORD_VB_H
    ww = WORD_W * s
    W = round(isz + gap + ww); H = isz
    body = (f'<g transform="scale({isz/120})">{icon_body}</g>'
            f'<g transform="translate({isz+gap} {(isz-wh)/2:.1f}) scale({s:.5f}) translate(0 34)">{word_body(ink, dot)}</g>')
    return svg(W, H, body, title=title)
def lockup_v(icon_body, ink, dot, title):
    isz, gap, wh = 160, 28, 72
    s = wh / WORD_VB_H; ww = WORD_W * s
    W = 400; H = isz + gap + wh + 20
    body = (f'<g transform="translate({(W-isz)/2:.1f} 0) scale({isz/120})">{icon_body}</g>'
            f'<g transform="translate({(W-ww)/2:.1f} {isz+gap}) scale({s:.5f}) translate(0 34)">{word_body(ink, dot)}</g>')
    return svg(W, round(H), body, title=title)

# ── Android adaptive: lienzo 108, glifo dentro de la zona segura (círculo de 66) ────────────────
K = 0.62   # esquina más lejana del glifo = 51,6 u * 0.62 = 32 px < 33 px de radio seguro
def android_fg(stroke, dot):
    return f'<g transform="translate(54 54) scale({K}) translate(-60 -60)">{glyph(stroke, dot)}</g>'

OUT = {
 # iconos (rect + glifo)
 'icon-sage.svg':                svg(120, 120, icon(SAGE, CREAM, MUST, rounded=False), title='Homita · icono (sin esquinas, para iOS y tiendas)'),
 'icon-sage-rounded.svg':        svg(120, 120, icon(SAGE, CREAM, MUST), title='Homita · icono salvia'),
 'icon-terracota-rounded.svg':   svg(120, 120, icon(TERRA, CREAM, MUSTL), title='Homita · icono terracota'),
 'icon-light-rounded.svg':       svg(120, 120, icon(CREAM, FOREST, TERRA, border=True), title='Homita · icono claro'),
 'icon-ios-dark.svg':            svg(120, 120, icon(FOREST, CREAM, MUST, rounded=False), title='Homita · icono iOS oscuro'),
 'icon-ios-tinted.svg':          svg(120, 120, icon('#000000', '#FFFFFF', '#9A9A9A', rounded=False), title='Homita · icono iOS tintado (escala de grises)'),
 # glifos sueltos (fondo transparente)
 'glyph-on-light.svg':           svg(120, 120, glyph(FOREST, TERRA), title='Homita · glifo sobre claro'),
 'glyph-on-dark.svg':            svg(120, 120, glyph(CREAM, MUST), title='Homita · glifo sobre oscuro'),
 'glyph-mono-black.svg':         svg(120, 120, glyph('#000000', '#000000'), title='Homita · glifo una tinta negro'),
 'glyph-mono-white.svg':         svg(120, 120, glyph('#FFFFFF', '#FFFFFF'), title='Homita · glifo una tinta blanco'),
 # Android
 'android-foreground.svg':       svg(108, 108, android_fg(CREAM, MUST), title='Homita · primer plano del icono adaptativo'),
 # wordmark y lockups
 'wordmark-light.svg':           wordmark_svg(FOREST, TERRA),
 'wordmark-dark.svg':            wordmark_svg(CREAM, MUST),
 'lockup-horizontal-light.svg':  lockup_h(icon(SAGE, CREAM, MUST), FOREST, TERRA, 'Homita'),
 'lockup-horizontal-dark.svg':   lockup_h(icon(CREAM, FOREST, TERRA, border=False), CREAM, MUST, 'Homita'),
 'lockup-stacked-light.svg':     lockup_v(icon(SAGE, CREAM, MUST), FOREST, TERRA, 'Homita'),
 'lockup-stacked-dark.svg':      lockup_v(icon(CREAM, FOREST, TERRA), CREAM, MUST, 'Homita'),
}
if __name__ == '__main__':
    os.makedirs(SRC, exist_ok=True)
    for name, content in OUT.items():
        with open(os.path.join(SRC, name), 'w', encoding='utf-8') as f: f.write(content)
    print(f'{len(OUT)} SVG en {os.path.normpath(SRC)}')
