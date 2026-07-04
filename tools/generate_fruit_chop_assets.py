#!/usr/bin/env python3
"""
Batch-generate all Fruit Chop game assets using the project design language.

Usage:
    python tools/generate_fruit_chop_assets.py              # generate all
    python tools/generate_fruit_chop_assets.py --list        # list assets without generating
    python tools/generate_fruit_chop_assets.py --only watermelon_whole orange_whole  # specific ones
    python tools/generate_fruit_chop_assets.py --quality medium  # higher quality
    python tools/generate_fruit_chop_assets.py --skip-existing   # don't regenerate existing files

Requires: pip install openai
"""

import argparse
import sys
import time
from pathlib import Path

# Add tools dir to path so we can import generate_asset
sys.path.insert(0, str(Path(__file__).parent))
from generate_asset import generate_image


# ---------------------------------------------------------------------------
# Design language style anchor -- prepended to every prompt
# ---------------------------------------------------------------------------
STYLE = (
    "Flat vector game sprite, chunky dark outline (3-4px, using a darker shade "
    "of the fill color, NOT pure black), single small white elliptical highlight "
    "dot in the upper-left quadrant for a 3D feel, solid flat color fill with no "
    "gradients inside the shape. Transparent/empty background with nothing behind "
    "the object. Centered on canvas. Friendly rounded cartoon style similar to "
    "Overcooked or Cut the Rope game art. Slightly organic imperfect shapes, not "
    "geometrically precise. No text, no drop shadows on background, no floor or "
    "surface. Single isolated game sprite."
)

# Base output directory (relative to repo root)
OUT = "assets/fruit_chop"


# ---------------------------------------------------------------------------
# Asset definitions: key -> (relative_path, prompt_suffix)
# ---------------------------------------------------------------------------
ASSETS = {
    # ── Whole fruits ──────────────────────────────────────────
    "watermelon_whole": (
        f"{OUT}/fruit/watermelon_whole.png",
        "A whole round watermelon. Dark green exterior with lighter green "
        "stripes curving around the surface. Slightly oval plump shape. "
        "Small brown stem nub on top. Chunky and cute."
    ),
    "orange_whole": (
        f"{OUT}/fruit/orange_whole.png",
        "A whole orange citrus fruit. Warm saturated orange color. Very "
        "subtle dimpled texture implied by tiny lighter dots. Small green "
        "leaf attached to a tiny brown stem on top. Perfectly round, plump, "
        "and cheerful."
    ),
    "lime_whole": (
        f"{OUT}/fruit/lime_whole.png",
        "A whole lime fruit. Bright vivid green color, slightly smaller and "
        "rounder than an orange. Smooth surface with very subtle dimpling. "
        "Tiny brown stem bump on top."
    ),
    "grape_cluster": (
        f"{OUT}/fruit/grape_cluster.png",
        "A cluster of about 8-10 purple grapes arranged in a classic "
        "triangular bunch shape. Rich saturated purple-violet color. Each "
        "grape is a small rounded circle with its own tiny white highlight "
        "dot. Small brown stem and one green leaf at the top."
    ),
    "banana": (
        f"{OUT}/fruit/banana.png",
        "A single banana fruit. Bright cheerful yellow color in a classic "
        "crescent curve shape. Small brown stem end on one side, slightly "
        "darker yellow tip on the other. Simple and iconic."
    ),
    "pineapple_whole": (
        f"{OUT}/fruit/pineapple_whole.png",
        "A whole pineapple. Golden-brown body with a diamond crosshatch "
        "pattern. Spiky green crown of leaves on top. Tall and proud shape. "
        "Warm tropical colors."
    ),

    # ── Sliced halves (shown after slash) ─────────────────────
    "watermelon_half": (
        f"{OUT}/fruit/watermelon_half.png",
        "A sliced half watermelon showing the cross-section. Dark green rind "
        "on the curved outside, thin white rind layer, then bright juicy red "
        "interior with small black teardrop seeds scattered inside. The cut "
        "face is flat and clean. Viewed from a slight angle showing both the "
        "red interior and green exterior."
    ),
    "orange_half": (
        f"{OUT}/fruit/orange_half.png",
        "A sliced half orange showing the cross-section. Orange rind on the "
        "curved outside with thin white pith layer. Inside shows lighter "
        "orange-yellow segments radiating from a small center point, like "
        "a citrus wheel. Clean flat cut face."
    ),
    "lime_half": (
        f"{OUT}/fruit/lime_half.png",
        "A sliced half lime showing the cross-section. Green rind on outside "
        "with thin white pith. Inside shows pale translucent yellow-green "
        "segments radiating from center. Clean flat cut face."
    ),
    "banana_half": (
        f"{OUT}/fruit/banana_half.png",
        "A banana cut in half at an angle. Shows the creamy white interior "
        "and the yellow peel curving around it. The cut is clean and diagonal. "
        "One piece of a banana that has been sliced."
    ),
    "pineapple_half": (
        f"{OUT}/fruit/pineapple_half.png",
        "A sliced half pineapple showing the cross-section. Brown-gold rind "
        "on outside, bright golden yellow juicy interior with a lighter core "
        "circle in the center. Some of the green leaf crown visible on top."
    ),

    # ── Bomb / penalty ────────────────────────────────────────
    "bomb": (
        f"{OUT}/bomb/bomb.png",
        "A classic cartoon round bomb. Dark charcoal-gray sphere with a "
        "short fuse rope sticking out of the top, with a bright orange-red "
        "flame spark at the tip of the fuse. A small white skull-and-"
        "crossbones symbol or X mark on the front of the bomb. Menacing but "
        "still cute and cartoony."
    ),

    # ── Star / combo ──────────────────────────────────────────
    "star": (
        f"{OUT}/ui/star.png",
        "A five-pointed star game icon. Bright sunshine yellow-gold color "
        "with a warm orange tint on the edges. Chunky rounded points, not "
        "sharp. Radiating a sense of achievement and celebration. Simple and "
        "bold. Game reward star sprite."
    ),

    # ── Juice splashes (per fruit color) ──────────────────────
    "splash_red": (
        f"{OUT}/vfx/splash_red.png",
        "A cartoon juice splash splatter. Bright red color like watermelon "
        "juice. Several droplets and a central splat shape radiating outward. "
        "Dynamic and energetic. Flat color, chunky outlines. VFX sprite."
    ),
    "splash_orange": (
        f"{OUT}/vfx/splash_orange.png",
        "A cartoon juice splash splatter. Warm orange color like orange "
        "juice. Several droplets and a central splat shape radiating outward. "
        "Dynamic and energetic. Flat color, chunky outlines. VFX sprite."
    ),
    "splash_green": (
        f"{OUT}/vfx/splash_green.png",
        "A cartoon juice splash splatter. Bright lime green color like lime "
        "juice. Several droplets and a central splat shape radiating outward. "
        "Dynamic and energetic. Flat color, chunky outlines. VFX sprite."
    ),
    "splash_purple": (
        f"{OUT}/vfx/splash_purple.png",
        "A cartoon juice splash splatter. Rich purple color like grape juice. "
        "Several droplets and a central splat shape radiating outward. "
        "Dynamic and energetic. Flat color, chunky outlines. VFX sprite."
    ),
    "splash_yellow": (
        f"{OUT}/vfx/splash_yellow.png",
        "A cartoon juice splash splatter. Bright banana yellow color. Several "
        "droplets and a central splat shape radiating outward. Dynamic and "
        "energetic. Flat color, chunky outlines. VFX sprite."
    ),
    "splash_gold": (
        f"{OUT}/vfx/splash_gold.png",
        "A cartoon juice splash splatter. Golden-yellow color like pineapple "
        "juice. Several droplets and a central splat shape radiating outward. "
        "Dynamic and energetic. Flat color, chunky outlines. VFX sprite."
    ),

    # ── Launcher / branding ───────────────────────────────────
    "logo_hand": (
        f"{OUT}/../ui/logo_hand.png",
        "A stylized open hand silhouette icon made of flowing air wisps and "
        "wind trails. The hand shape is formed by swirling cyan and teal "
        "colored translucent wisps against a transparent background. Magical "
        "and ethereal feeling. Suitable as a game logo icon. No text."
    ),
    "icon_fruit_chop": (
        f"{OUT}/../ui/icon_fruit_chop.png",
        "A game icon showing a cartoon slash mark cutting through a "
        "watermelon. The watermelon is split in two halves with red juice "
        "splashing out from the cut. A curved white slash trail goes through "
        "the middle. Dynamic and exciting. Square game icon composition."
    ),
    "icon_hand_test": (
        f"{OUT}/../ui/icon_hand_test.png",
        "A game icon showing a wireframe hand skeleton made of glowing green "
        "lines and dots at the joints, like a motion capture or tracking "
        "visualization. 21 connection points visible. Technical but friendly. "
        "Dark background circle behind it. Square game icon composition."
    ),
}


def main():
    parser = argparse.ArgumentParser(description="Batch-generate Fruit Chop assets")
    parser.add_argument(
        "--list", action="store_true", help="List all assets without generating"
    )
    parser.add_argument(
        "--only", nargs="+", metavar="KEY", help="Only generate these asset keys"
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip assets that already exist on disk",
    )
    parser.add_argument(
        "--quality",
        "-q",
        default="low",
        choices=["low", "medium", "high"],
        help="Quality setting (default: low for fast iteration)",
    )
    parser.add_argument(
        "--model",
        "-m",
        default="gpt-image-1",
        help="Model (default: gpt-image-1)",
    )
    parser.add_argument(
        "--size",
        "-s",
        default="1024x1024",
        help="Image size (default: 1024x1024)",
    )
    args = parser.parse_args()

    # Resolve paths relative to repo root
    repo_root = Path(__file__).parent.parent

    # Filter assets
    assets_to_generate = ASSETS
    if args.only:
        unknown = set(args.only) - set(ASSETS.keys())
        if unknown:
            print(f"ERROR: Unknown asset keys: {', '.join(unknown)}")
            print(f"Available: {', '.join(sorted(ASSETS.keys()))}")
            sys.exit(1)
        assets_to_generate = {k: v for k, v in ASSETS.items() if k in args.only}

    # List mode
    if args.list:
        print(f"{'Key':<25} {'Path':<50} {'Exists'}")
        print("-" * 85)
        for key, (path, _prompt) in sorted(assets_to_generate.items()):
            full_path = repo_root / path
            exists = "YES" if full_path.exists() else "no"
            print(f"{key:<25} {path:<50} {exists}")
        print(f"\nTotal: {len(assets_to_generate)} assets")
        return

    # Generate
    total = len(assets_to_generate)
    generated = 0
    skipped = 0
    failed = 0

    print(f"Generating {total} assets (model={args.model}, quality={args.quality}, size={args.size})")
    print("=" * 70)

    for i, (key, (rel_path, prompt_suffix)) in enumerate(assets_to_generate.items(), 1):
        full_path = repo_root / rel_path

        if args.skip_existing and full_path.exists():
            print(f"[{i}/{total}] SKIP (exists): {key}")
            skipped += 1
            continue

        full_prompt = f"{STYLE}\n\n{prompt_suffix}"
        print(f"\n[{i}/{total}] {key}")

        try:
            generate_image(
                prompt=full_prompt,
                output_path=str(full_path),
                size=args.size,
                quality=args.quality,
                model=args.model,
            )
            generated += 1
            # Small delay between requests to be polite to the API
            if i < total:
                time.sleep(1)
        except Exception as e:
            print(f"  FAILED: {e}")
            failed += 1

    print("\n" + "=" * 70)
    print(f"Done! Generated: {generated}, Skipped: {skipped}, Failed: {failed}")


if __name__ == "__main__":
    main()
