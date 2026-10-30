"""Generates the previous Glamshot app icon as an Icon Composer document.

This script no longer builds the shipped icon. Icon/Glamshot.icon is now maintained directly as an
Icon Composer document and is the source of truth, so the script refuses to write over it. It is
kept as a record of the earlier design and writes only to another .icon bundle.

The earlier icon is a Safari window built like a camera seen from the front: large traffic lights stay
top left, the toolbar's right end is a yellow flash window, and a glass lens in a thick white ring
sits in the middle of the page. In the light appearance the toolbar is white, the traffic lights
have darker rims and the page is a sky-blue gradient; in the dark one the window is graphite. The
backdrop is a deep system-blue gradient.

Geometry follows Icon Composer's grid (lines every 128 pt, circles of radius 102, 256 and 410 about
the centre of the 1024 canvas): the window fills 128...896 x 160...864, centred on 512.

usage: python3 Icon/build-icon.py OUT.icon ['{"toolbar": "dark", "url": true}']

OUT is required and is replaced wholesale, so close it in Icon Composer first.
The optional JSON overrides any key of P below. Preview a build with Icon Composer's ictool
(renditions: Default, Dark, TintedLight, TintedDark, ClearLight, ClearDark):
  "$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" OUT.icon \\
      --export-image --output-file preview.png --platform macOS --rendition Default \\
      --width 512 --height 512 --scale 2 --design-generation 26
"""
import json, math, os, shutil, sys

if len(sys.argv) < 2:
    sys.exit("usage: python3 Icon/build-icon.py OUT.icon [JSON]")
OUT = sys.argv[1]
SHIPPED = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Glamshot.icon")
if os.path.realpath(OUT.rstrip("/")) == os.path.realpath(SHIPPED):
    sys.exit("refusing to replace %s: the shipped icon is edited in Icon Composer, not generated" % SHIPPED)
if not OUT.rstrip("/").endswith(".icon"):
    sys.exit("refusing to replace %s: the output must be an .icon bundle" % OUT)
# band: "navy", "blue" or null; body and toolbar: "light" or "dark" in the light appearance;
# bg: "bright" (with a pale corner) or "deep".
P = {"band": None, "body": "light", "toolbar": "light", "bg": "deep", "url": False, "lines": 0,
     "bar": 196, "photo_r": 186, "ring": 26, "light_r": 44, "flash_w": 240, "bloom": 170, "streak": False,
     "glow": 0.7, "glow_r": 300, "bloom_dark": 175, "bloom_dark_peak": 1.0, "glow_dark": 0.4,
     "bloom_peak": 1.0, "photo": "pastel", "toolbar_light": "#FFFFFF", "ring_light": "#FFFFFF", "edge": None,
     "flash_light": ["#FFC400", "#FFE680"], "glare": False,
     "lens": True, "pane_light": ["#CFE4FF", "#8DBDFF"],
     "light_colors": ["#FF3B30", "#FFCC00", "#28D150"], "light_rim": 9, "rim_colors": ["#C4120A", "#C79100", "#14963A"]}
if len(sys.argv) > 2:
    P.update(json.loads(sys.argv[2]))
A = os.path.join(OUT, "Assets")
shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(A)

HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'

# Window: grid 128...896 x 160...864.
X, Y, W, H, R, BAR = 128, 160, 768, 704, 120, P["bar"]
CY0 = Y + BAR/2
# Flash window at the toolbar's right end.
FW = P["flash_w"]
FX = X + W - (30 + BAR/2 - BAR*0.28) - FW
FCX = FX + FW/2
# The band and the round photo centred on it, in the middle of the page below the toolbar.
PCX, PCY, PR = 512, Y + BAR + (H - BAR)/2 - (30 if P["lines"] else 0), P["photo_r"]
BX, BW, BH = X + 56, W - 112, 300
BY = PCY - BH/2
LY = BY + BH + 48

# Organic gradients: a base colour and soft radial blobs (x, y, radius as fractions of the box width, colour).
CANVAS = (["#0A6CFF", (0.15, 0.0, 0.95, "#6CC0FF"), (0.95, 1.05, 0.85, "#0038B8")] if P["bg"] == "bright" else
          ["#0656E0", (0.2, 0.0, 0.9, "#1E7BFF"), (0.9, 1.05, 0.85, "#002A8C")])
CANVAS_DARK = ["#0A1A40", (0.15, 0.0, 0.95, "#1A4C8C"), (0.95, 1.05, 0.85, "#040A20")]
PHOTOS = {"vivid": ["#4B2BFF", (0.2, 0.15, 0.7, "#00C2FF"), (0.9, 0.3, 0.6, "#FF2D8A"), (0.6, 1.0, 0.6, "#FF9F0A"), (0.0, 0.9, 0.5, "#0A4BFF")]}
PHOTO = ["#7A6CFF", (0.2, 0.15, 0.7, "#7FE7FF"), (0.9, 0.3, 0.6, "#FF8AC8"), (0.6, 1.0, 0.6, "#FFC46B"), (0.0, 0.9, 0.5, "#4A7BFF")]
BANDS = {"navy": (("#22397A", "#0D1A40"), ("#16244E", "#080F26")), "blue": (("#3D9BFF", "#0A6CFF"), ("#2A7FE0", "#0A52B8"))}

LIGHT_ONLY = [{"appearance": "dark", "value": True}]
LIGHT_ONLY_UNTINTED = [{"appearance": "dark", "value": True}, {"appearance": "tinted", "value": True}]
DARK_ONLY = [{"value": True}, {"appearance": "dark", "value": False}]


def rr(x, y, w, h, r):
    return ("M%.1f,%.1fh%.1fa%.1f,%.1f 0 0 1 %.1f,%.1fv%.1fa%.1f,%.1f 0 0 1 %.1f,%.1fh%.1fa%.1f,%.1f 0 0 1 %.1f,%.1fv%.1fa%.1f,%.1f 0 0 1 %.1f,%.1fz"
            % (x + r, y, w - 2*r, r, r, r, r, h - 2*r, r, r, -r, r, -(w - 2*r), r, r, -r, -r, -(h - 2*r), r, r, r, -r))


def top_rr(x, y, w, h, r):
    """Rectangle with only its top corners rounded."""
    return ("M%.1f,%.1fv%.1fa%.1f,%.1f 0 0 1 %.1f,%.1fh%.1fa%.1f,%.1f 0 0 1 %.1f,%.1fv%.1fz"
            % (x, y + h, -(h - r), r, r, r, -r, w - 2*r, r, r, r, r, h - r))


def circle(cx, cy, r):
    return "M%.1f,%.1fa%.1f,%.1f 0 1 0 %.1f,0a%.1f,%.1f 0 1 0 %.1f,0z" % (cx - r, cy, r, r, 2*r, r, r, -2*r)


def ring(cx, cy, r0, r1):
    return '<path fill-rule="evenodd" d="%s %s"/>' % (circle(cx, cy, r0), circle(cx, cy, r1))


def srgb(h, a=1.0):
    h = h.lstrip("#")
    return "srgb:%.5f,%.5f,%.5f,%.5f" % (int(h[0:2], 16)/255, int(h[2:4], 16)/255, int(h[4:6], 16)/255, a)


def solid(h, a=1.0):
    return {"solid": srgb(h, a)}


def lin(c0, c1):
    return {"linear-gradient": [srgb(c0), srgb(c1)], "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}


def fills(light, dark, tinted):
    return [{"value": light}, {"appearance": "dark", "value": dark}, {"appearance": "tinted", "value": tinted}]


def blobs(spec, box, uid):
    x, y, w, h = box
    defs, body = "", '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (x, y, w, h, spec[0])
    for i, (bx, by, r, c) in enumerate(spec[1:]):
        defs += ('<radialGradient id="%s%d"><stop offset="0" stop-color="%s"/><stop offset="0.55" stop-color="%s" stop-opacity="0.6"/>'
                 '<stop offset="1" stop-color="%s" stop-opacity="0"/></radialGradient>' % (uid, i, c, c, c))
        body += '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="url(#%s%d)"/>' % (x + bx*w, y + by*h, r*w, uid, i)
    return defs, body


def layer(name, body, fill=None, hidden=None, **extra):
    """Writes Assets/<name>.svg; a layer fill, when given, replaces the SVG's own colours."""
    with open(os.path.join(A, name + ".svg"), "w") as fh:
        fh.write(HEAD + body + "</svg>\n")
    L = {"name": name, "image-name": name + ".svg"}
    if fill:
        L["fill-specializations"] = fill
    if hidden:
        L["hidden-specializations"] = hidden
    L.update(extra)
    return L


def shape(name, d, fill, **extra):
    return layer(name, '<path d="%s"/>' % d, fill, **extra)


def clipped(name, spec, clip_d, box, hidden=None):
    """An organic gradient clipped to clip_d."""
    d, b = blobs(spec, box, name.replace("-", ""))
    return layer(name, '<defs>%s<clipPath id="c"><path d="%s"/></clipPath></defs><g clip-path="url(#c)">%s</g>' % (d, clip_d, b), hidden=hidden)


def soft(core, edge, peak, k=4.0, hold=0.0):
    """Gaussian-like falloff to zero at the rim, so a glow has no visible edge; hold keeps the
    centre at full strength out to that fraction of the radius."""
    tail = math.exp(-k)
    out = []
    for i in range(11):
        t = i/10
        u = max(0.0, (t - hold)/(1 - hold))
        out.append((t, core if t <= hold else edge, peak*(math.exp(-k*u*u) - tail)/(1 - tail)))
    return out


def radial(name, cx, cy, rx, ry, stops, **extra):
    s = "".join('<stop offset="%.2f" stop-color="%s" stop-opacity="%.2f"/>' % st for st in stops)
    return layer(name, '<defs><radialGradient id="g">%s</radialGradient></defs><ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="url(#g)"/>'
                 % (s, cx, cy, rx, ry), **extra)


groups = []


def group(name, layers, **opts):
    g = {"name": name, "layers": layers}
    g.update(opts)
    groups.append(g)


# Photo: the round photo in its glass ring, the camera's lens. The light appearance can use a
# deeper photo and an outline so the ring reads on the white pane.
photo = [clipped("circle", PHOTO, circle(PCX, PCY, PR), (PCX - PR, PCY - PR, 2*PR, 2*PR))]
if P["photo"] in PHOTOS:
    photo = [clipped("circle", PHOTOS[P["photo"]], circle(PCX, PCY, PR), (PCX - PR, PCY - PR, 2*PR, 2*PR), hidden=LIGHT_ONLY),
             clipped("circle-dark", PHOTO, circle(PCX, PCY, PR), (PCX - PR, PCY - PR, 2*PR, 2*PR), hidden=DARK_ONLY)]
trim = [layer("trim", ring(PCX, PCY, PR + P["ring"], PR - 2), fills(solid(P["ring_light"]), solid("#E6EBF2"), solid("#FFFFFF")))]
if P["edge"]:
    trim.append(layer("edge", ring(PCX, PCY, PR + P["ring"] + 10, PR + P["ring"] - 2), fills(solid(P["edge"]), solid("#E6EBF2", 0.0), solid("#FFFFFF", 0.0)),
                      hidden=LIGHT_ONLY))
if P["lens"]:
    # A coated glass lens: a dark barrel, deep glass with cyan and magenta reflections, and highlights.
    GR = PR*0.8
    glass = ('<defs><radialGradient id="g" cx="0.42" cy="0.38" r="0.68"><stop offset="0" stop-color="#7FDBFF"/>'
             '<stop offset="0.3" stop-color="#3D63FF"/><stop offset="0.68" stop-color="#1C1670"/><stop offset="1" stop-color="#06071C"/></radialGradient>'
             '<radialGradient id="m"><stop offset="0" stop-color="#FF4FB0" stop-opacity="0.85"/><stop offset="1" stop-color="#FF4FB0" stop-opacity="0"/></radialGradient></defs>'
             '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="url(#g)"/><circle cx="%.1f" cy="%.1f" r="%.1f" fill="url(#m)"/>'
             % (PCX, PCY, GR, PCX + GR*0.38, PCY + GR*0.4, GR*0.5))
    hl = ('<path d="M%.1f,%.1f A%.1f,%.1f 0 0 1 %.1f,%.1f A%.1f,%.1f 0 0 0 %.1f,%.1f Z"/><circle cx="%.1f" cy="%.1f" r="%.1f"/>'
          % (PCX - GR*0.66, PCY - GR*0.02, GR*0.7, GR*0.7, PCX - GR*0.02, PCY - GR*0.66, GR*0.8, GR*0.8, PCX - GR*0.66, PCY - GR*0.02,
             PCX + GR*0.42, PCY + GR*0.42, GR*0.09))
    photo = [layer("highlight", hl, fills(solid("#FFFFFF", 0.7), solid("#FFFFFF", 0.6), solid("#FFFFFF", 0.8))),
             layer("glass", glass),
             layer("barrel", ring(PCX, PCY, PR, GR - 2), fills(lin("#3A4150", "#14171E"), lin("#3A4150", "#0E1015"), solid("#3A3A3A")))]
group("Photo", trim + photo,
      specular=True, lighting="combined", shadow={"kind": "neutral", "opacity": 0.45}, translucency={"enabled": True, "value": 0.1})

# Chrome: flash glare (no glass, so it stays soft), traffic lights, flash window, band and page.
# Dark mode gets a tighter, dimmer bloom: the light one spreads into a grey haze over graphite.
glare = [radial("bloom-dark", FCX, CY0, P["bloom_dark"], P["bloom_dark"], soft("#FFFFFF", "#FFF6D8", P["bloom_dark_peak"], k=7.0, hold=0.45),
                glass=False, **{"hidden-specializations": DARK_ONLY}),
         radial("bloom", FCX, CY0, P["bloom"], P["bloom"], soft("#FFFFFF", "#FFF6D8", P["bloom_peak"], k=3.5, hold=0.32),
                glass=False, **{"hidden-specializations": LIGHT_ONLY})]
if P["streak"]:
    glare.insert(0, radial("streak", FCX, CY0, 420, 26, [(0, "#FFFFFF", 0.95), (0.5, "#FFF8E4", 0.35), (1, "#FFF8E4", 0)],
                           glass=False, **{"hidden-specializations": [{"appearance": "tinted", "value": True}]}))
lr = P["light_r"]
LX = [X + 30 + BAR/2 + i*lr*2.6 for i in range(3)]
lights = layer("lights", "".join('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (LX[i], CY0, lr, c) for i, c in enumerate(P["light_colors"])))
# An optional darker rim inside each light, in the light appearance, so they read on a white toolbar.
rim = [layer("rims", "".join('<path fill-rule="evenodd" fill="%s" d="%s %s"/>' % (c, circle(LX[i], CY0, lr), circle(LX[i], CY0, lr - P["light_rim"]))
                             for i, c in enumerate(P["rim_colors"])), hidden=LIGHT_ONLY_UNTINTED)] if P["light_rim"] else []
n = max(3, int(FW/36))
FH = BAR*0.56
fresnel = layer("fresnel", "".join('<path d="%s"/>' % rr(FX + FW*(i + 1)/(n + 1) - 4, CY0 - FH*0.29, 8, FH*0.58, 4) for i in range(n)),
                fills(solid("#D89A00", 0.4), solid("#B88600", 0.45), solid("#9A9A9A", 0.4)))
FH = BAR*0.56
flash = shape("flash", rr(FX, CY0 - FH/2, FW, FH, FH*0.37), fills(lin(*P["flash_light"]), lin("#FFE680", "#FFF6D8"), solid("#FFFFFF")))
chrome = (glare if P["glare"] else []) + rim + [lights, fresnel, flash]
if P["url"]:
    ux0 = X + 66 + lr*6.4 + 40
    chrome.append(shape("url", rr(ux0, CY0 - 26, FX - 32 - ux0, 52, 26), fills(solid("#FFFFFF", 0.95), solid("#FFFFFF", 0.14), solid("#FFFFFF", 0.9))))
if P["band"]:
    bl, bd = BANDS[P["band"]]
    chrome.append(shape("band", rr(BX, BY, BW, BH, 40), fills(lin(*bl), lin(*bd), solid("#FFFFFF", 0.35))))
if P["lines"]:
    chrome.append(layer("lines", "".join('<path d="%s"/>' % rr(BX, LY + i*52, w, 28, 14) for i, w in enumerate([BW, BW*0.62][:P["lines"]])),
                        fills(solid("#0A3A80", 0.35), solid("#FFFFFF", 0.35), solid("#FFFFFF", 0.5))))
group("Chrome", chrome, specular=True, lighting="individual", shadow={"kind": "layer-color", "opacity": 0.45},
      translucency={"enabled": True, "value": 0.1})

# Body: the window pane and its toolbar.
dark_body = P["body"] == "dark"
group("Body", [shape("toolbar", top_rr(X, Y, W, BAR, R), fills(solid("#FFFFFF", 0.07) if dark_body else solid("#1E222A", 0.92) if P["toolbar"] == "dark" else solid(P["toolbar_light"], 0.9),
                                                               solid("#FFFFFF", 0.07), solid("#FFFFFF", 0.3))),
               shape("pane", rr(X, Y, W, H, R), fills(lin(*P["pane_light"]) if P["pane_light"] else solid("#262A33", 0.94) if dark_body else solid("#FFFFFF", 0.94),
                                                     solid("#2A2C33", 0.9), solid("#FFFFFF", 0.7)))],
      specular=True, lighting="combined", **{"blur-material": 0.3},
      shadow={"kind": "neutral", "opacity": 0.6}, translucency={"enabled": True, "value": 0.15})

# Canvas: the flash's light on the backdrop, over the blue gradient (tinted falls back to the fill).
g = P["glow"]
cd, cb = blobs(CANVAS, (0, 0, 1024, 1024), "c")
dd, db = blobs(CANVAS_DARK, (0, 0, 1024, 1024), "d")
glow = [radial("glow-dark", FCX, CY0, P["glow_r"], P["glow_r"], soft("#FFFFFF", "#FFF6DA", P["glow_dark"], k=5.0),
               glass=False, **{"hidden-specializations": DARK_ONLY}),
        radial("glow", FCX, CY0, P["glow_r"], P["glow_r"], soft("#FFFFFF", "#FFF6DA", g, k=5.0),
               glass=False, **{"hidden-specializations": LIGHT_ONLY})]
group("Canvas", (glow if P["glare"] else []) + [layer("canvas-dark", "<defs>%s</defs>%s" % (dd, db), hidden=DARK_ONLY),
                                                layer("canvas", "<defs>%s</defs>%s" % (cd, cb), hidden=LIGHT_ONLY_UNTINTED)],
      specular=False, shadow={"kind": "none", "opacity": 0}, translucency={"enabled": False, "value": 0})

doc = {"fill-specializations": fills(lin("#4FA6FF", "#0050D0"), lin("#1A3A70", "#060E24"), lin("#4FA6FF", "#0050D0")),
       "groups": groups, "supported-platforms": {"squares": "shared"}}
with open(os.path.join(OUT, "icon.json"), "w") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
# Drop SVGs written for layers the chosen options left out.
used = {L["image-name"] for g in groups for L in g["layers"]}
for f in os.listdir(A):
    if f not in used:
        os.remove(os.path.join(A, f))
print(OUT)
