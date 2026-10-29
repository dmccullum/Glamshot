"""Generates Icon/Glamshot.icon, the Icon Composer source for the app icon.

The icon is a Safari window built like a camera seen from the front: large traffic lights stay
top left, the toolbar's right end is a lit flash window, and a round photo in a thick glass ring
sits where a lens would. The window is white in the light appearance and graphite in the dark one,
on a deep system-blue gradient.

Geometry follows Icon Composer's grid (lines every 128 pt, circles of radius 102, 256 and 410 about
the centre of the 1024 canvas): the window fills 128...896 x 160...864, centred on 512.

usage: python3 Icon/build-icon.py [OUT.icon] ['{"toolbar": "dark", "url": true}']

OUT defaults to Icon/Glamshot.icon and is replaced wholesale, so close it in Icon Composer first.
The optional JSON overrides any key of P below. Preview a build with Icon Composer's ictool
(renditions: Default, Dark, TintedLight, TintedDark, ClearLight, ClearDark):
  "$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" Icon/Glamshot.icon \\
      --export-image --output-file preview.png --platform macOS --rendition Default \\
      --width 512 --height 512 --scale 2 --design-generation 26
"""
import json, os, shutil, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "Glamshot.icon")
if not OUT.rstrip("/").endswith(".icon"):
    sys.exit("refusing to replace %s: the output must be an .icon bundle" % OUT)
# band: "navy", "blue" or null; body and toolbar: "light" or "dark" in the light appearance;
# bg: "bright" (with a pale corner) or "deep".
P = {"band": None, "body": "light", "toolbar": "light", "bg": "deep", "url": False, "lines": 0,
     "bar": 196, "photo_r": 186, "ring": 26, "light_r": 44, "flash_w": 240, "bloom": 110, "streak": False,
     "glow": 0.45, "glow_r": 230}
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


def radial(name, cx, cy, rx, ry, stops, **extra):
    s = "".join('<stop offset="%.2f" stop-color="%s" stop-opacity="%.2f"/>' % st for st in stops)
    return layer(name, '<defs><radialGradient id="g">%s</radialGradient></defs><ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="url(#g)"/>'
                 % (s, cx, cy, rx, ry), **extra)


groups = []


def group(name, layers, **opts):
    g = {"name": name, "layers": layers}
    g.update(opts)
    groups.append(g)


# Photo: the round photo in its glass ring, the camera's lens.
group("Photo", [layer("trim", ring(PCX, PCY, PR + P["ring"], PR - 2), fills(solid("#FFFFFF"), solid("#E6EBF2"), solid("#FFFFFF")))]
      + [clipped("circle", PHOTO, circle(PCX, PCY, PR), (PCX - PR, PCY - PR, 2*PR, 2*PR))],
      specular=True, lighting="combined", shadow={"kind": "neutral", "opacity": 0.45}, translucency={"enabled": True, "value": 0.1})

# Chrome: flash glare (no glass, so it stays soft), traffic lights, flash window, band and page.
glare = [radial("bloom", FCX, CY0, P["bloom"], P["bloom"], [(0, "#FFFFFF", 1), (0.4, "#FFFCEE", 0.95), (0.7, "#FFF4D0", 0.4), (1, "#FFF4D0", 0)], glass=False)]
if P["streak"]:
    glare.insert(0, radial("streak", FCX, CY0, 420, 26, [(0, "#FFFFFF", 0.95), (0.5, "#FFF8E4", 0.35), (1, "#FFF8E4", 0)],
                           glass=False, **{"hidden-specializations": [{"appearance": "tinted", "value": True}]}))
lr = P["light_r"]
lights = layer("lights", "".join('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (X + 30 + BAR/2 - lr + lr + i*lr*2.6, CY0, lr, c)
                                 for i, c in enumerate(["#FF3B30", "#FFCC00", "#28D150"])))
n = max(3, int(FW/36))
FH = BAR*0.56
fresnel = layer("fresnel", "".join('<path d="%s"/>' % rr(FX + FW*(i + 1)/(n + 1) - 4, CY0 - FH*0.29, 8, FH*0.58, 4) for i in range(n)),
                fills(solid("#D89A00", 0.4), solid("#B88600", 0.45), solid("#9A9A9A", 0.4)))
FH = BAR*0.56
flash = shape("flash", rr(FX, CY0 - FH/2, FW, FH, FH*0.37), fills(lin("#FFE070", "#FFF6D0"), lin("#FFE070", "#FFF0C0"), solid("#FFFFFF")))
chrome = glare + [lights, fresnel, flash]
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
group("Body", [shape("toolbar", top_rr(X, Y, W, BAR, R), fills(solid("#FFFFFF", 0.07) if dark_body else solid("#1E222A", 0.92) if P["toolbar"] == "dark" else solid("#D3DBE7", 0.9),
                                                               solid("#FFFFFF", 0.07), solid("#FFFFFF", 0.3))),
               shape("pane", rr(X, Y, W, H, R), fills(solid("#262A33", 0.94) if dark_body else solid("#FFFFFF", 0.94),
                                                     solid("#2A2C33", 0.9), solid("#FFFFFF", 0.7)))],
      specular=True, lighting="combined", **{"blur-material": 0.3},
      shadow={"kind": "neutral", "opacity": 0.6}, translucency={"enabled": True, "value": 0.15})

# Canvas: the flash's light on the backdrop, over the blue gradient (tinted falls back to the fill).
g = P["glow"]
cd, cb = blobs(CANVAS, (0, 0, 1024, 1024), "c")
dd, db = blobs(CANVAS_DARK, (0, 0, 1024, 1024), "d")
group("Canvas", [radial("glow", FCX, CY0, P["glow_r"], P["glow_r"], [(0, "#FFFFFF", 0.95*g), (0.35, "#FFF6DA", 0.55*g), (1, "#FFF6DA", 0)]),
                 layer("canvas-dark", "<defs>%s</defs>%s" % (dd, db), hidden=DARK_ONLY),
                 layer("canvas", "<defs>%s</defs>%s" % (cd, cb), hidden=LIGHT_ONLY_UNTINTED)],
      specular=False, shadow={"kind": "none", "opacity": 0}, translucency={"enabled": False, "value": 0})

doc = {"fill-specializations": fills(lin("#4FA6FF", "#0050D0"), lin("#1A3A70", "#060E24"), lin("#4FA6FF", "#0050D0")),
       "groups": groups, "supported-platforms": {"squares": "shared"}}
with open(os.path.join(OUT, "icon.json"), "w") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
print(OUT)
