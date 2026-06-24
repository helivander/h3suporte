#!/usr/bin/env python3
"""Gera todos os assets de icone/banner da H3 Suporte a partir de:
   assetsh3/512.png  -> icone quadrado
   assetsh3/1.png    -> banner horizontal
Rode da raiz do projeto: python assetsh3/gen_icons.py
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SQUARE = Image.open(os.path.join(ROOT, "assetsh3", "512.png")).convert("RGBA")
BANNER = Image.open(os.path.join(ROOT, "assetsh3", "1.png")).convert("RGBA")

def p(*a):
    return os.path.join(ROOT, *a)

def save_png(img, *path):
    dst = p(*path)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img.save(dst, "PNG")
    print("png ", os.path.relpath(dst, ROOT), img.size)

def rs(size):
    return SQUARE.resize((size, size), Image.LANCZOS)

def flatten(img, bg=(255, 255, 255)):
    base = Image.new("RGB", img.size, bg)
    base.paste(img, mask=img.split()[-1])
    return base

def circular(img):
    from PIL import ImageDraw
    size = img.size[0]
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size, size), fill=255)
    out = img.copy()
    out.putalpha(mask)
    return out

def save_ico(sizes, *path):
    dst = p(*path)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    base = rs(max(sizes))
    base.save(dst, "ICO", sizes=[(s, s) for s in sizes])
    print("ico ", os.path.relpath(dst, ROOT), sizes)

# ---------- res/ (Cargo bundle, Linux, geral) ----------
save_png(rs(512), "res", "icon.png")
save_png(rs(32),  "res", "32x32.png")
save_png(rs(64),  "res", "64x64.png")
save_png(rs(128), "res", "128x128.png")
save_png(rs(256), "res", "128x128@2x.png")
save_png(rs(512), "res", "mac-icon.png")
save_ico([16, 32, 48, 64, 128, 256], "res", "icon.ico")
save_ico([16, 32, 48], "res", "tray-icon.ico")

# ---------- Flutter assets (banner interno + icone) ----------
save_png(BANNER,  "flutter", "assets", "logo.png")   # banner loadLogo() (tema claro)
save_png(rs(512), "flutter", "assets", "icon.png")   # loadIcon()

# versao clara do banner para o tema escuro: recolore o TEXTO (x>=split) para
# branco e mantem o logo H3 (x<split) intacto. split ~150px no banner 452px.
def banner_dark(src):
    img = src.copy(); px = img.load(); W, H = img.size
    split = int(W * 150 / 452)
    for x in range(W):
        for y in range(H):
            r, g, b, a = px[x, y]
            if x >= split and a > 0:
                px[x, y] = (242, 242, 242, a)
    return img
save_png(banner_dark(BANNER), "flutter", "assets", "logo_dark.png")

# ---------- Windows runner ----------
save_ico([16, 32, 48, 64, 128, 256], "flutter", "windows", "runner", "resources", "app_icon.ico")

# ---------- Android mipmaps ----------
android = ["flutter", "android", "app", "src", "main", "res"]
launcher = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
foreground = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
for dpi, sz in launcher.items():
    save_png(rs(sz), *android, f"mipmap-{dpi}", "ic_launcher.png")
    save_png(circular(rs(sz)), *android, f"mipmap-{dpi}", "ic_launcher_round.png")
for dpi, sz in foreground.items():
    # foreground adaptativo: logo ~62% centralizado em canvas transparente
    canvas = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    inner = int(sz * 0.62)
    logo = SQUARE.resize((inner, inner), Image.LANCZOS)
    off = (sz - inner) // 2
    canvas.paste(logo, (off, off), logo)
    save_png(canvas, *android, f"mipmap-{dpi}", "ic_launcher_foreground.png")

# ---------- iOS (sem alpha) ----------
ios = ["flutter", "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"]
ios_icons = {
    "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167, "Icon-App-1024x1024@1x.png": 1024,
}
for name, sz in ios_icons.items():
    save_png(flatten(rs(sz)), *ios, name)

print("\nOK - todos os assets gerados.")
