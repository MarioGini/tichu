"""Renders the web app icons in web/ from icon.svg.

icon.svg holds the Dragon and Phoenix cards in <defs> and lays them out on the
table felt. This script reuses those defs with three layouts:

  web/icons/Icon-{192,512}.png           both cards, full bleed
  web/icons/Icon-maskable-{192,512}.png  both cards inside Android's safe zone
  web/favicon.png                        the Dragon card alone, transparent

Needs google-chrome (headless, rasterises the SVG) and Pillow (downscales).

    python3 tool/web_icons/render.py
"""

import pathlib
import subprocess
import sys
import tempfile

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
WEB = HERE.parent.parent / "web"
SIZE = 512

CARDS = """
  <g filter="url(#shadow)">
    <use href="#phoenix" transform="translate(182 262) rotate(-14)"/>
    <use href="#dragon" transform="translate(330 262) rotate(12)"/>
  </g>"""
FELT = '<rect width="512" height="512" fill="url(#felt)"/>'

LAYOUTS = {
    "icon": FELT + CARDS,
    # The maskable safe zone is the centred circle of radius 0.4 * size.
    "maskable": FELT + f'<g transform="translate(256 262) scale(0.74) translate(-256 -262)">{CARDS}</g>',
    "favicon": '<use href="#dragon" transform="translate(256 256) rotate(6) scale(1.5)"/>',
}


def svg_with(scene: str) -> str:
    source = (HERE / "icon.svg").read_text()
    defs_end = source.index("</defs>") + len("</defs>")
    return f"{source[:defs_end]}\n{scene}\n</svg>\n"


def rasterise(svg: str, out: pathlib.Path) -> Image.Image:
    with tempfile.TemporaryDirectory() as tmp:
        svg_path = pathlib.Path(tmp) / "icon.svg"
        svg_path.write_text(svg)
        subprocess.run(
            [
                "google-chrome", "--headless=new", "--disable-gpu",
                "--hide-scrollbars", "--default-background-color=00000000",
                f"--window-size={SIZE},{SIZE}", f"--screenshot={out}",
                svg_path.as_uri(),
            ],
            check=True, capture_output=True,
        )
    return Image.open(out).convert("RGBA")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        images = {
            name: rasterise(svg_with(scene), pathlib.Path(tmp) / f"{name}.png")
            for name, scene in LAYOUTS.items()
        }
    targets = [
        ("icon", WEB / "icons" / "Icon-512.png", 512),
        ("icon", WEB / "icons" / "Icon-192.png", 192),
        ("maskable", WEB / "icons" / "Icon-maskable-512.png", 512),
        ("maskable", WEB / "icons" / "Icon-maskable-192.png", 192),
        ("favicon", WEB / "favicon.png", 32),
    ]
    for name, path, size in targets:
        image = images[name]
        if name != "favicon":
            image = image.convert("RGB")
        image.resize((size, size), Image.LANCZOS).save(path, optimize=True)
        print(f"wrote {path.relative_to(WEB.parent)} ({size}px)", file=sys.stderr)


if __name__ == "__main__":
    main()
