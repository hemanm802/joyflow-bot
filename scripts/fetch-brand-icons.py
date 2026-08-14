#!/usr/bin/env python3
"""Rasterize real brand marks from published icon packs into JoyflowKit.

Do not hand-draw logos. Sources, in order:
  1. Iconify `logos` (Gil Barbara SVG Logos)
  2. Iconify `thesvg-color`, `vscode-icons`, `skill-icons`, `simple-icons`, `lucide`
  3. Official GitHub / site rasters
"""

from __future__ import annotations

import io
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "JoyflowKit" / "Sources" / "JoyflowKit" / "Resources" / "Plugins"
CAIRO = "/opt/homebrew/bin/cairosvg"
SIZE = 256
CORNER = 56
MARK = 176

ICONIFY: dict[str, list[str]] = {
    "gmail": ["logos:google-gmail"],
    "googlecalendar": ["logos:google-calendar"],
    "googledrive": ["logos:google-drive"],
    "granola": ["thesvg-color:granola-light", "token-branded:granola"],
    "awsagents": ["logos:aws"],
    "awssagemaker": ["skill-icons:aws-dark", "logos:aws"],
    "slack": ["logos:slack-icon"],
    "notion": ["logos:notion-icon"],
    "github": ["logos:github-icon"],
    "arize": ["simple-icons:arize", "token-branded:arize"],
    "atlan": ["simple-icons:atlan", "token-branded:atlan"],
    "linear": ["logos:linear-icon", "simple-icons:linear"],
    "figma": ["logos:figma"],
    "discord": ["logos:discord-icon"],
    "outlook": ["vscode-icons:file-type-outlook", "simple-icons:microsoftoutlook"],
    "jira": ["logos:jira"],
    "composio": ["thesvg-color:composio", "token-branded:composio"],
    "context7": ["vscode-icons:file-type-context7", "catppuccin:context7"],
    "trello": ["logos:trello"],
    "asana": ["logos:asana-icon", "simple-icons:asana"],
    "dropbox": ["logos:dropbox"],
    "twitter": ["logos:x", "simple-icons:x"],
    "hubspot": ["simple-icons:hubspot", "logos:hubspot"],
    "zoom": ["logos:zoom-icon", "simple-icons:zoom"],
    "stripe": ["logos:stripe"],
    "airtable": ["logos:airtable"],
    "salesforce": ["logos:salesforce"],
    "twilio": ["logos:twilio-icon", "simple-icons:twilio"],
    "confluence": ["logos:confluence"],
    "clickup": ["simple-icons:clickup"],
    "googlesheets": ["simple-icons:googlesheets", "logos:google-sheets"],
    "googledocs": ["simple-icons:googledocs", "logos:google-docs"],
    "microsoftteams": ["logos:microsoft-teams"],
    "telegram": ["logos:telegram"],
    "youtube": ["logos:youtube-icon"],
    "linkedin": ["logos:linkedin-icon"],
    "vercel": ["simple-icons:vercel", "logos:vercel-icon"],
    "supabase": ["simple-icons:supabase", "logos:supabase-icon"],
    "intercom": ["simple-icons:intercom"],
    "box": ["simple-icons:box"],
}

OFFICIAL = {
    "arize": [
        "https://github.com/Arize-ai.png?size=256",
        "https://www.arize.com/favicon.ico",
    ],
    "atlan": [
        "https://www.atlan.com/favicon-32x32.png",
        "https://github.com/atlanhq.png?size=256",
        "https://atlan.com/favicon.ico",
    ],
}

DARK_CARD = {"notion", "awssagemaker", "composio", "vercel", "twitter"}
BRAND_CARD = {
    "arize": (255, 255, 255, 255),
    "atlan": (255, 255, 255, 255),
}


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "JoyflowIconFetch/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def iconify_svg(icon_id: str) -> bytes | None:
    prefix, name = icon_id.split(":", 1)
    url = f"https://api.iconify.design/{prefix}/{name}.svg?height=256"
    try:
        data = fetch(url)
    except urllib.error.HTTPError:
        return None
    if not data or data.strip() in {b"404", b"Not found"}:
        return None
    if b"<svg" not in data[:200]:
        return None
    return data


def svg_to_png(svg: bytes, px: int = 192) -> Image.Image:
    out = subprocess.check_output(
        [CAIRO, "-f", "png", "-W", str(px), "-H", str(px), "/dev/stdin"],
        input=svg,
    )
    return Image.open(io.BytesIO(out)).convert("RGBA")


def load_raster(data: bytes) -> Image.Image:
    im = Image.open(io.BytesIO(data))
    if getattr(im, "n_frames", 1) > 1:
        best = 0
        best_area = 0
        for i in range(im.n_frames):
            im.seek(i)
            area = im.size[0] * im.size[1]
            if area > best_area:
                best_area = area
                best = i
        im.seek(best)
    return im.convert("RGBA")


def trim_alpha(im: Image.Image) -> Image.Image:
    bbox = im.split()[-1].getbbox()
    return im.crop(bbox) if bbox else im


def knockout_field(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    field = px[1, 1]
    out = im.copy()
    opx = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = opx[x, y]
            if abs(r - field[0]) < 28 and abs(g - field[1]) < 28 and abs(b - field[2]) < 28:
                opx[x, y] = (r, g, b, 0)
    return out


def fit_mark(im: Image.Image, max_side: int) -> Image.Image:
    im = trim_alpha(im)
    w, h = im.size
    if w == 0 or h == 0:
        return im
    scale = min(max_side / w, max_side / h)
    return im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.Resampling.LANCZOS)


def average_luma(im: Image.Image) -> float:
    small = im.convert("RGB").resize((16, 16), Image.Resampling.BOX)
    pixels = list(small.getdata())
    if not pixels:
        return 1
    return sum(0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in pixels) / (len(pixels) * 255)


def full_bleed(logo: Image.Image) -> Image.Image:
    tile = logo.convert("RGBA").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, SIZE - 1, SIZE - 1), radius=CORNER, fill=255)
    tile.putalpha(mask)
    return tile


def rounded_card(logo: Image.Image, bg: tuple[int, int, int, int], source: str) -> Image.Image:
    if source == "official" and min(logo.size) >= 24 and abs(logo.size[0] - logo.size[1]) < 8:
        field = logo.getpixel((2, 2))
        if isinstance(field, tuple) and field[0] < 240:
            return full_bleed(logo)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((0, 0, SIZE - 1, SIZE - 1), radius=CORNER, fill=bg)
    mark = logo.copy()
    if source == "official":
        knocked = knockout_field(mark)
        if trim_alpha(knocked).size[0] >= 8:
            mark = knocked
    mark = fit_mark(mark, MARK)
    img.alpha_composite(mark, ((SIZE - mark.width) // 2, (SIZE - mark.height) // 2))
    return img


def card_bg(slug: str, logo: Image.Image) -> tuple[int, int, int, int]:
    if slug in BRAND_CARD:
        return BRAND_CARD[slug]
    if slug in DARK_CARD:
        return (17, 17, 17, 255)
    return (255, 255, 255, 255) if average_luma(logo) < 0.72 else (17, 17, 17, 255)


def resolve_logo(slug: str) -> tuple[Image.Image, str]:
    for icon_id in ICONIFY.get(slug, []):
        svg = iconify_svg(icon_id)
        if svg:
            print("pack", slug, icon_id)
            return svg_to_png(svg), "iconify"
    for url in OFFICIAL.get(slug, []):
        try:
            data = fetch(url)
            if data.lstrip().startswith(b"<svg") or data.lstrip().startswith(b"<?xml"):
                print("official-svg", slug, url)
                return svg_to_png(data), "official"
            print("official", slug, url)
            return load_raster(data), "official"
        except Exception as exc:
            print("skip", slug, url, exc)
    raise RuntimeError(f"no pack icon for {slug}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    slugs = [
        "gmail",
        "googlecalendar",
        "googledrive",
        "granola",
        "arize",
        "atlan",
        "awsagents",
        "awssagemaker",
        "slack",
        "notion",
        "github",
        "linear",
        "figma",
        "discord",
        "outlook",
        "jira",
        "composio",
        "context7",
        "trello",
        "asana",
        "dropbox",
        "twitter",
        "hubspot",
        "zoom",
        "stripe",
        "airtable",
        "salesforce",
        "twilio",
        "confluence",
        "clickup",
        "googlesheets",
        "googledocs",
        "microsoftteams",
        "telegram",
        "youtube",
        "linkedin",
        "vercel",
        "supabase",
        "intercom",
        "box",
    ]
    for slug in slugs:
        try:
            logo, source = resolve_logo(slug)
            img = rounded_card(logo, card_bg(slug, logo), source)
            dest = OUT / f"{slug}.png"
            img.save(dest)
            print("wrote", dest, dest.stat().st_size)
        except Exception as exc:
            failures.append(f"{slug}: {exc}")
            print("FAIL", slug, exc)
    if failures:
        raise SystemExit("icon fetch failed:\n" + "\n".join(failures))
    print("OK")


if __name__ == "__main__":
    main()
