#!/usr/bin/env python3
"""Build and verify Orbit-Games' compact pinned playing-card atlas."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
from urllib.request import Request, urlopen

from PIL import Image, ImageDraw, ImageOps


SOURCE_COMMIT = "1e4497c05c3da9956c9f517bd386e9a7090ff7fa"
SOURCE_ROOT = f"https://raw.githubusercontent.com/hayeah/playing-cards-assets/{SOURCE_COMMIT}"
LICENSE_SHA256 = "fe677a80c2b4ff84c482d46903cde46df6920636061e28779e9248a38b90b832"
DESIGN = "compact-rank-suit-v4"
ATLAS_SIZE = (2048, 512)
CARD_SIZE = (128, 88)
GAP = (16, 8)
DEALER_RECT = (272, 416, 64, 64)
DEALER_SCALE = 4
RANK_CROP = (0, 0, 60, 50)
SUIT_CROP = (0, 38, 44, 90)
FACE_RANKS = {"jack", "queen", "king"}
RANK_REGION = (4, 4, 64, 84)
SUIT_REGION = (65, 5, 124, 83)
SINGLE_RANK_HEIGHT = 62
BLACK = (24, 24, 24, 255)
RED = (204, 24, 32, 255)
BACK_COLOR = (30, 39, 54, 255)
BACK_INK = (228, 231, 235, 255)
DEALER_GOLD = (255, 209, 0, 255)
DEALER_FACE = (242, 238, 218, 255)
SUIT_COLORS = {"clubs": BLACK, "diamonds": RED, "hearts": RED, "spades": BLACK}
RANKS = ("2", "3", "4", "5", "6", "7", "8", "9", "10", "jack", "queen", "king", "ace")
RANK_LABELS = {
    "2": "2",
    "3": "3",
    "4": "4",
    "5": "5",
    "6": "6",
    "7": "7",
    "8": "8",
    "9": "9",
    "10": "10",
    "jack": "J",
    "queen": "Q",
    "king": "K",
    "ace": "A",
}
FIT_TO_WIDTH_RANKS = ("10",)
SINGLE_CHARACTER_RANKS = tuple(rank for rank in RANKS if rank not in FIT_TO_WIDTH_RANKS)
SUITS = ("clubs", "diamonds", "hearts", "spades")
ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = ROOT / "Assets" / "Cards"
ATLAS_PATH = OUTPUT_DIR / "PlayingCards.png"
MANIFEST_PATH = OUTPUT_DIR / "PlayingCards.json"
LICENSE_PATH = OUTPUT_DIR / "LICENSE.playing-cards-assets"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch(path: str) -> bytes:
    request = Request(f"{SOURCE_ROOT}/{path}", headers={"User-Agent": "Orbit-Games asset builder"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def slot_origin(column: int, row: int) -> tuple[int, int]:
    used_width = len(RANKS) * CARD_SIZE[0] + (len(RANKS) - 1) * GAP[0]
    used_height = 5 * CARD_SIZE[1] + 4 * GAP[1]
    left = (ATLAS_SIZE[0] - used_width) // 2
    top = (ATLAS_SIZE[1] - used_height) // 2
    return left + column * (CARD_SIZE[0] + GAP[0]), top + row * (CARD_SIZE[1] + GAP[1])


def extract_glyph(source: bytes, crop: tuple[int, int, int, int]) -> Image.Image:
    with Image.open(io.BytesIO(source)) as image:
        mask = image.convert("RGBA").getchannel("A").crop(crop)
    bounds = mask.getbbox()
    if bounds is None:
        raise SystemExit(f"source glyph crop is empty: {crop}")
    return mask.crop(bounds)


def extract_rank(source: bytes, rank: str) -> Image.Image:
    with Image.open(io.BytesIO(source)) as image:
        mask = image.convert("RGBA").getchannel("A").crop(RANK_CROP)
    if rank in FACE_RANKS:
        mask = mask.crop((0, 0, 29, mask.height))
    width, height = mask.size
    pixels = mask.load()
    selected = Image.new("L", mask.size, 0)
    selected_pixels = selected.load()
    visited = bytearray(width * height)
    for start_y in range(height):
        for start_x in range(width):
            start = start_y * width + start_x
            if visited[start] or pixels[start_x, start_y] == 0:
                continue
            visited[start] = 1
            pending = [(start_x, start_y)]
            component: list[tuple[int, int]] = []
            left = right = start_x
            top = bottom = start_y
            while pending:
                x, y = pending.pop()
                component.append((x, y))
                left, right = min(left, x), max(right, x)
                top, bottom = min(top, y), max(bottom, y)
                for neighbor_y in range(max(0, y - 1), min(height, y + 2)):
                    for neighbor_x in range(max(0, x - 1), min(width, x + 2)):
                        neighbor = neighbor_y * width + neighbor_x
                        if not visited[neighbor] and pixels[neighbor_x, neighbor_y] > 0:
                            visited[neighbor] = 1
                            pending.append((neighbor_x, neighbor_y))
            if left < 43 and top < 12:
                for x, y in component:
                    selected_pixels[x, y] = pixels[x, y]
    bounds = selected.getbbox()
    if bounds is None:
        raise SystemExit("source rank crop is empty")
    return selected.crop(bounds)


def place_glyph(
    slot: Image.Image,
    glyph: Image.Image,
    region: tuple[int, int, int, int],
    color: tuple[int, int, int, int],
) -> None:
    width, height = region[2] - region[0], region[3] - region[1]
    fitted = ImageOps.contain(glyph, (width, height), Image.Resampling.LANCZOS)
    left = region[0] + (width - fitted.width) // 2
    top = region[1] + (height - fitted.height) // 2
    ink = Image.new("RGBA", fitted.size, color)
    ink.putalpha(fitted)
    slot.alpha_composite(ink, (left, top))


def place_rank(
    slot: Image.Image,
    glyph: Image.Image,
    rank: str,
    color: tuple[int, int, int, int],
) -> None:
    region_width = RANK_REGION[2] - RANK_REGION[0]
    if rank in FIT_TO_WIDTH_RANKS:
        fitted_width = region_width
        fitted_height = round(glyph.height * fitted_width / glyph.width)
    else:
        fitted_height = SINGLE_RANK_HEIGHT
        fitted_width = round(glyph.width * fitted_height / glyph.height)
        if fitted_width > region_width:
            raise SystemExit(f"single-character rank exceeds its fixed typography region: {rank}")
    fitted = glyph.resize((fitted_width, fitted_height), Image.Resampling.LANCZOS)
    region_height = RANK_REGION[3] - RANK_REGION[1]
    left = RANK_REGION[0] + (region_width - fitted.width) // 2
    top = RANK_REGION[1] + (region_height - fitted.height) // 2
    ink = Image.new("RGBA", fitted.size, color)
    ink.putalpha(fitted)
    slot.alpha_composite(ink, (left, top))


def render_card(rank_source: bytes, suit_glyph: Image.Image, rank: str, suit: str) -> Image.Image:
    slot = Image.new("RGBA", CARD_SIZE, (0, 0, 0, 0))
    color = SUIT_COLORS[suit]
    place_rank(slot, extract_rank(rank_source, rank), rank, color)
    place_glyph(slot, suit_glyph, SUIT_REGION, color)
    return slot


def rank_typography_metadata() -> dict[str, object]:
    return {
        "singleCharacterRanks": [RANK_LABELS[rank] for rank in SINGLE_CHARACTER_RANKS],
        "singleCharacterHeight": SINGLE_RANK_HEIGHT,
        "fitToWidthRanks": [RANK_LABELS[rank] for rank in FIT_TO_WIDTH_RANKS],
        "fitWidth": RANK_REGION[2] - RANK_REGION[0],
    }


def render_back(source: bytes) -> Image.Image:
    with Image.open(io.BytesIO(source)) as image:
        converted = image.convert("RGBA")
        fitted = ImageOps.fit(converted, (CARD_SIZE[0] - 8, CARD_SIZE[1] - 8), method=Image.Resampling.LANCZOS)
    pattern = ImageOps.invert(ImageOps.grayscale(fitted)).point(lambda value: min(255, value * 7))
    back = Image.new("RGBA", fitted.size, BACK_COLOR)
    ink = Image.new("RGBA", fitted.size, BACK_INK)
    ink.putalpha(pattern)
    back.alpha_composite(ink)
    slot = Image.new("RGBA", CARD_SIZE, (0, 0, 0, 0))
    slot.alpha_composite(back, (4, 4))
    ImageDraw.Draw(slot).rectangle((4, 4, CARD_SIZE[0] - 5, CARD_SIZE[1] - 5), outline=BLACK, width=2)
    return slot


def render_dealer_chip() -> Image.Image:
    size = DEALER_RECT[2] * DEALER_SCALE
    chip = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(chip)
    last = size - 1
    draw.ellipse((2, 2, last - 2, last - 2), fill=BLACK)
    draw.ellipse((10, 10, last - 10, last - 10), fill=DEALER_GOLD)
    draw.ellipse((24, 24, last - 24, last - 24), fill=BLACK)
    draw.ellipse((30, 30, last - 30, last - 30), fill=DEALER_FACE)
    glyph_width = 26
    draw.line((94, 75, 94, 181), fill=BLACK, width=glyph_width)
    draw.arc((55, 75, 185, 181), -90, 90, fill=BLACK, width=glyph_width)
    return chip.resize((DEALER_RECT[2], DEALER_RECT[3]), Image.Resampling.LANCZOS)


def add_entry(
    entries: list[dict[str, object]],
    key: str,
    card_id: int | str,
    source_names: list[str],
    column: int,
    row: int,
) -> None:
    left, top = slot_origin(column, row)
    entries.append(
        {
            "key": key,
            "cardId": card_id,
            "sources": list(dict.fromkeys(source_names)),
            "left": left,
            "top": top,
            "width": CARD_SIZE[0],
            "height": CARD_SIZE[1],
        }
    )


def build() -> None:
    license_bytes = LICENSE_PATH.read_bytes()
    if sha256(license_bytes) != LICENSE_SHA256:
        raise SystemExit("packaged playing-cards-assets licence does not match the pinned upstream licence")

    rank_sources = {rank: fetch(f"png/{rank}_of_diamonds.png") for rank in RANKS}
    suit_sources = {suit: fetch(f"png/2_of_{suit}.png") for suit in SUITS}

    atlas = Image.new("RGBA", ATLAS_SIZE, (0, 0, 0, 0))
    entries: list[dict[str, object]] = []
    for suit_index, suit in enumerate(SUITS):
        suit_glyph = extract_glyph(suit_sources[suit], SUIT_CROP)
        for rank_index, rank in enumerate(RANKS):
            rank_source_name = f"{rank}_of_diamonds.png"
            suit_source_name = f"2_of_{suit}.png"
            left, top = slot_origin(rank_index, suit_index)
            card = render_card(rank_sources[rank], suit_glyph, rank, suit)
            atlas.alpha_composite(card, (left, top))
            add_entry(
                entries,
                f"{rank}_{suit}",
                suit_index * len(RANKS) + rank_index + 1,
                [rank_source_name, suit_source_name],
                rank_index,
                suit_index,
            )

    back_source = "back@2x.png"
    back_left, back_top = slot_origin(0, 4)
    atlas.alpha_composite(render_back(fetch(f"png/{back_source}")), (back_left, back_top))
    add_entry(entries, "back", "back", [back_source], 0, 4)

    dealer_chip = render_dealer_chip()
    atlas.alpha_composite(dealer_chip, DEALER_RECT[:2])

    output = io.BytesIO()
    atlas.save(output, "PNG", compress_level=9, optimize=False)
    atlas_bytes = output.getvalue()
    manifest = {
        "schemaVersion": 4,
        "design": DESIGN,
        "source": "https://github.com/hayeah/playing-cards-assets",
        "sourceCommit": SOURCE_COMMIT,
        "licenseSha256": LICENSE_SHA256,
        "atlas": {
            "file": ATLAS_PATH.name,
            "width": ATLAS_SIZE[0],
            "height": ATLAS_SIZE[1],
            "sha256": sha256(atlas_bytes),
        },
        "cell": {"width": CARD_SIZE[0], "height": CARD_SIZE[1], "gapX": GAP[0], "gapY": GAP[1]},
        "rankTypography": rank_typography_metadata(),
        "cards": entries,
        "decorations": [
            {
                "key": "dealer_chip",
                "provenance": "Orbit-Games project-generated Pillow primitives",
                "left": DEALER_RECT[0],
                "top": DEALER_RECT[1],
                "width": DEALER_RECT[2],
                "height": DEALER_RECT[3],
                "sha256": sha256(dealer_chip.tobytes()),
            }
        ],
    }
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    ATLAS_PATH.write_bytes(atlas_bytes)
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {ATLAS_PATH.relative_to(ROOT)} ({len(atlas_bytes)} bytes, {len(entries)} cells)")


def check() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    atlas_bytes = ATLAS_PATH.read_bytes()
    license_bytes = LICENSE_PATH.read_bytes()
    if manifest["sourceCommit"] != SOURCE_COMMIT:
        raise SystemExit("manifest source commit is not pinned to the expected revision")
    if manifest.get("schemaVersion") != 4:
        raise SystemExit("playing-card manifest schema mismatch")
    if manifest.get("design") != DESIGN:
        raise SystemExit("playing-card manifest design mismatch")
    if sha256(license_bytes) != LICENSE_SHA256 or manifest["licenseSha256"] != LICENSE_SHA256:
        raise SystemExit("playing-card licence checksum mismatch")
    if sha256(atlas_bytes) != manifest["atlas"]["sha256"]:
        raise SystemExit("playing-card atlas checksum mismatch")
    atlas_metadata = manifest["atlas"]
    if (
        atlas_metadata["file"] != ATLAS_PATH.name
        or atlas_metadata["width"] != ATLAS_SIZE[0]
        or atlas_metadata["height"] != ATLAS_SIZE[1]
    ):
        raise SystemExit("playing-card manifest atlas geometry mismatch")
    with Image.open(io.BytesIO(atlas_bytes)) as atlas:
        if atlas.size != ATLAS_SIZE or atlas.mode != "RGBA":
            raise SystemExit("playing-card atlas format mismatch")
        atlas_pixels = atlas.copy()
    cards = manifest["cards"]
    if len(cards) != 53 or len({entry["key"] for entry in cards}) != 53:
        raise SystemExit("playing-card manifest must contain 52 unique faces and one back")
    if [entry["cardId"] for entry in cards[:-1]] != list(range(1, 53)) or cards[-1]["cardId"] != "back":
        raise SystemExit("playing-card manifest IDs are not canonical")
    expected_cell = {"width": CARD_SIZE[0], "height": CARD_SIZE[1], "gapX": GAP[0], "gapY": GAP[1]}
    if manifest["cell"] != expected_cell:
        raise SystemExit("playing-card manifest cell geometry mismatch")
    if manifest.get("rankTypography") != rank_typography_metadata():
        raise SystemExit("playing-card manifest rank typography mismatch")
    face_hashes: set[str] = set()
    for index, entry in enumerate(cards):
        if index < 52:
            suit_index, rank_index = divmod(index, len(RANKS))
            rank, suit = RANKS[rank_index], SUITS[suit_index]
            expected_key = f"{rank}_{suit}"
            expected_sources = list(dict.fromkeys([f"{rank}_of_diamonds.png", f"2_of_{suit}.png"]))
            expected_left, expected_top = slot_origin(rank_index, suit_index)
        else:
            expected_key = "back"
            expected_sources = ["back@2x.png"]
            expected_left, expected_top = slot_origin(0, 4)
        if (
            entry["key"] != expected_key
            or entry.get("sources") != expected_sources
            or entry["left"] != expected_left
            or entry["top"] != expected_top
            or entry["width"] != CARD_SIZE[0]
            or entry["height"] != CARD_SIZE[1]
        ):
            raise SystemExit(f"playing-card manifest entry mismatch: {expected_key}")
        box = (
            entry["left"],
            entry["top"],
            entry["left"] + entry["width"],
            entry["top"] + entry["height"],
        )
        cell = atlas_pixels.crop(box)
        if cell.getchannel("A").getbbox() is None:
            raise SystemExit(f"playing-card atlas cell is empty: {entry['key']}")
        if index < 52:
            face_hashes.add(sha256(cell.tobytes()))
            rank_bounds = cell.crop(RANK_REGION).getchannel("A").getbbox()
            if rank_bounds is None:
                raise SystemExit(f"playing-card atlas rank is empty: {entry['key']}")
            rank_width = rank_bounds[2] - rank_bounds[0]
            rank_height = rank_bounds[3] - rank_bounds[1]
            if rank in FIT_TO_WIDTH_RANKS:
                if rank_width != RANK_REGION[2] - RANK_REGION[0] or rank_height >= SINGLE_RANK_HEIGHT:
                    raise SystemExit(f"playing-card fit-to-width rank typography mismatch: {entry['key']}")
            elif rank_height != SINGLE_RANK_HEIGHT:
                raise SystemExit(f"playing-card single-character rank height mismatch: {entry['key']}")
            if cell.crop(SUIT_REGION).getchannel("A").getbbox() is None:
                raise SystemExit(f"playing-card atlas suit is empty: {entry['key']}")
    if len(face_hashes) != 52:
        raise SystemExit("playing-card atlas faces are not visually unique")
    decorations = manifest.get("decorations")
    if not isinstance(decorations, list) or len(decorations) != 1:
        raise SystemExit("playing-card manifest must contain one project-generated decoration")
    dealer = decorations[0]
    expected_dealer = {
        "key": "dealer_chip",
        "provenance": "Orbit-Games project-generated Pillow primitives",
        "left": DEALER_RECT[0],
        "top": DEALER_RECT[1],
        "width": DEALER_RECT[2],
        "height": DEALER_RECT[3],
    }
    for key, value in expected_dealer.items():
        if dealer.get(key) != value:
            raise SystemExit(f"dealer-chip manifest mismatch: {key}")
    dealer_pixels = atlas_pixels.crop(
        (
            DEALER_RECT[0],
            DEALER_RECT[1],
            DEALER_RECT[0] + DEALER_RECT[2],
            DEALER_RECT[1] + DEALER_RECT[3],
        )
    )
    if dealer.get("sha256") != sha256(dealer_pixels.tobytes()):
        raise SystemExit("dealer-chip checksum mismatch")
    if (
        dealer_pixels.getpixel((0, 0))[3] != 0
        or dealer_pixels.getpixel((DEALER_RECT[2] // 2, DEALER_RECT[3] // 2))[3] != 255
    ):
        raise SystemExit("dealer-chip transparency mismatch")
    colors = {color for _, color in dealer_pixels.getcolors(maxcolors=DEALER_RECT[2] * DEALER_RECT[3]) or []}
    if DEALER_GOLD not in colors or DEALER_FACE not in colors or BLACK not in colors:
        raise SystemExit("dealer-chip palette mismatch")
    print("playing-card assets: fixed rank typography, 52 faces + back + dealer chip, atlas and licence passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify the generated atlas without network access")
    args = parser.parse_args()
    check() if args.check else build()


if __name__ == "__main__":
    main()
