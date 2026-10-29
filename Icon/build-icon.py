"""Generates Icon/Glamshot.icon, the Icon Composer source for the app icon.

The icon is a Safari window built like a camera seen from the front: the address bar's end is a
lit flash window with a bloom and streak of glare, and the page's hero banner holds a round photo
in a glass ring where a lens would sit. It stands on a system-blue gradient.

Geometry follows Icon Composer's grid (lines every 128 pt, circles of radius 102, 256 and 410 about
the centre of the 1024 canvas): the window fills 128...896 x 160...864, centred on 512.

usage: python3 Icon/build-icon.py [OUT.icon]

OUT defaults to Icon/Glamshot.icon and is replaced wholesale, so close it in Icon Composer first.
Preview a build with Icon Composer's ictool (renditions: Default, Dark, TintedLight, TintedDark,
ClearLight, ClearDark):
  "$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" Icon/Glamshot.icon \\
      --export-image --output-file preview.png --platform macOS --rendition Default \\
      --width 512 --height 512 --scale 2 --design-generation 26
"""
import json, os, shutil, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "Glamshot.icon")
if not OUT.rstrip("/").endswith(".icon"):
    sys.exit("refusing to replace %s: the output must be an .icon bundle" % OUT)
A = os.path.join(OUT, "Assets")
shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(A)

HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'

# Window: grid 128...896 x 160...864, toolbar 128 tall.
X, Y, W, H, R, BAR = 128, 160, 768, 704, 120, 128
CY0 = Y + BAR/2
# Flash window at the toolbar's right end; the address bar runs from the traffic lights to it.
FW = 92
FX = X + W - 72 - FW
FCX = FX + FW/2
UX0 = X + 270
# Hero banner and the round photo centred in it.
HX, HY, HW, HH = X + 56, Y + BAR + 64, W - 112, 288
PCX, PCY, PR = 512, HY + HH/2, 150
LY = HY + HH + 52  # first text line

# Organic gradients: a base colour and soft radial blobs (x, y, radius as fractions of the box width, colour).
CANVAS = ["#0A6CFF", (0.15, 0.0, 0.95, "#6CC0FF"), (0.95, 1.05, 0.85, "#0038B8")]
CANVAS_DARK = ["#0A1A40", (0.15, 0.0, 0.95, "#1A4C8C"), (0.95, 1.05, 0.85, "#040A20")]
PHOTO = ["#3F8CFF", (0.15, 0.15, 0.8, "#9BE3FF"), (0.9, 0.25, 0.7, "#A07BFF"), (0.8, 0.95, 0.8, "#FF9CC4"), (0.1, 0.9, 0.6, "#1E4FE0")]
PHOTO_DARK = ["#123A80", (0.15, 0.15, 0.8, "#2E7DB8"), (0.9, 0.25, 0.7, "#4A36A0"), (0.8, 0.95, 0.8, "#8A3A70"), (0.1, 0.9, 0.6, "#0A2A90")]
HERO = ["#5A78F0", (0.0, 0.3, 0.55, "#2F5BFF"), (0.3, 1.0, 0.45, "#2440D8"), (0.6, 0.0, 0.5, "#9A7BFF"), (1.0, 0.75, 0.55, "#FF9CC4")]
HERO_DARK = ["#1E2C70", (0.0, 0.3, 0.55, "#14308A"), (0.3, 1.0, 0.45, "#0E1E6A"), (0.6, 0.0, 0.5, "#42358C"), (1.0, 0.75, 0.55, "#7A3A68")]

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


def photo(name, spec, dark_spec, clip_d, box):
    """A light and a dark rendering of an organic gradient, clipped to clip_d."""
    out = []
    for s, nm, hidden in ((dark_spec, name + "-dark", DARK_ONLY), (spec, name, LIGHT_ONLY)):
        d, b = blobs(s, box, nm.replace("-", ""))
        out.append(layer(nm, '<defs>%s<clipPath id="c"><path d="%s"/></clipPath></defs><g clip-path="url(#c)">%s</g>' % (d, clip_d, b), hidden=hidden))
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


# Photo: the round photo in its glass ring, the camera's lens.
group("Photo", [layer("trim", ring(PCX, PCY, PR + 14, PR - 2), fills(solid("#FFFFFF", 0.95), solid("#9AA3B0", 0.8), solid("#FFFFFF", 0.9)))]
      + photo("circle", PHOTO, PHOTO_DARK, circle(PCX, PCY, PR), (PCX - PR, PCY - PR, 2*PR, 2*PR)),
      specular=True, lighting="combined", shadow={"kind": "neutral", "opacity": 0.4}, translucency={"enabled": True, "value": 0.2})

# Chrome: flash glare (no glass, so it stays soft), traffic lights, flash window, address bar and page.
glare = [radial("streak", FCX, CY0, 420, 26, [(0, "#FFFFFF", 0.95), (0.5, "#FFF8E4", 0.35), (1, "#FFF8E4", 0)],
                glass=False, **{"hidden-specializations": [{"appearance": "tinted", "value": True}]}),
         radial("bloom", FCX, CY0, 150, 150, [(0, "#FFFFFF", 1), (0.25, "#FFFBEA", 0.85), (0.6, "#FFF4D0", 0.3), (1, "#FFF4D0", 0)], glass=False)]
lights = layer("lights", "".join('<circle cx="%.1f" cy="%.1f" r="17" fill="%s"/>' % (X + 84 + i*52, CY0, c)
                                 for i, c in enumerate(["#FF5F57", "#FEBC2E", "#28C840"])))
fresnel = layer("fresnel", "".join('<path d="%s"/>' % rr(FX + FW*(i + 1)/4 - 3, CY0 - 18, 6, 36, 3) for i in range(3)),
                fills(solid("#E0A800", 0.35), solid("#B88600", 0.4), solid("#9A9A9A", 0.4)))
flash = shape("flash", rr(FX, CY0 - 32, FW, 64, 22), fills(lin("#FFE58A", "#FFF7DA"), lin("#FFE58A", "#FFF2C8"), solid("#FFFFFF")))
url = shape("url", rr(UX0, CY0 - 26, FX - 28 - UX0, 52, 26), fills(solid("#FFFFFF", 0.95), solid("#FFFFFF", 0.14), solid("#FFFFFF", 0.9)))
hero = photo("hero", HERO, HERO_DARK, rr(HX, HY, HW, HH, 36), (HX, HY, HW, HH))
lines = layer("lines", "".join('<path d="%s"/>' % rr(HX, LY + i*52, w, 26, 13) for i, w in enumerate([HW, HW*0.62])),
              fills(solid("#0A3A80", 0.28), solid("#FFFFFF", 0.32), solid("#FFFFFF", 0.5)))
group("Chrome", glare + [lights, fresnel, flash, url] + hero + [lines],
      specular=True, lighting="individual", shadow={"kind": "layer-color", "opacity": 0.45}, translucency={"enabled": True, "value": 0.1})

# Body: the frosted window pane and its toolbar.
group("Body", [shape("toolbar", top_rr(X, Y, W, BAR, R), fills(solid("#E9EEF6", 0.6), solid("#FFFFFF", 0.06), solid("#FFFFFF", 0.3))),
               shape("pane", rr(X, Y, W, H, R), fills(solid("#FFFFFF", 0.86), solid("#2A2C33", 0.78), solid("#FFFFFF", 0.7)))],
      specular=True, lighting="combined", **{"blur-material": 0.5},
      shadow={"kind": "neutral", "opacity": 0.55}, translucency={"enabled": True, "value": 0.3})

# Canvas: the flash's light on the backdrop, over the blue gradient (tinted falls back to the fill).
cd, cb = blobs(CANVAS, (0, 0, 1024, 1024), "c")
dd, db = blobs(CANVAS_DARK, (0, 0, 1024, 1024), "d")
group("Canvas", [radial("glow", FCX, CY0, 380, 380, [(0, "#FFFFFF", 0.95), (0.35, "#FFF6DA", 0.55), (1, "#FFF6DA", 0)]),
                 layer("canvas-dark", "<defs>%s</defs>%s" % (dd, db), hidden=DARK_ONLY),
                 layer("canvas", "<defs>%s</defs>%s" % (cd, cb), hidden=LIGHT_ONLY_UNTINTED)],
      specular=False, shadow={"kind": "none", "opacity": 0}, translucency={"enabled": False, "value": 0})

doc = {"fill-specializations": fills(lin("#4FA6FF", "#0050D0"), lin("#1A3A70", "#060E24"), lin("#4FA6FF", "#0050D0")),
       "groups": groups, "supported-platforms": {"squares": "shared"}}
with open(os.path.join(OUT, "icon.json"), "w") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
print(OUT)
