#!/usr/bin/env python3
"""
Batch-generate all launcher UI assets using gpt-image-2 (best model).

Usage:
    python tools/generate_ui_assets.py              # generate all
    python tools/generate_ui_assets.py --list        # list without generating
    python tools/generate_ui_assets.py --only logo_mark icon_fruit_chop
    python tools/generate_ui_assets.py --skip-existing

Requires: pip install openai
"""

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from generate_asset import generate_image

# ---------------------------------------------------------------------------
# Style anchors
# ---------------------------------------------------------------------------
ICON_STYLE = (
    "Flat vector game icon sprite. Chunky rounded dark outline (using a darker "
    "shade of the main color, NOT pure black). Solid flat color fills. Small "
    "white elliptical highlight dot for depth. Centered composition on a white "
    "background. Friendly rounded cartoon style similar to Overcooked, Cut the "
    "Rope, or Nintendo Switch game menus. Slightly organic imperfect shapes. "
    "No text whatsoever. No words, no letters, no numbers. Clean isolated icon."
)

UI_STYLE = (
    "Clean minimal UI icon for a game interface. Simple flat vector style with "
    "rounded shapes. White color on transparent/white background. No text. "
    "Suitable as a small button icon in a game HUD. Bold, chunky, easy to "
    "read at small sizes."
)

CURSOR_STYLE = (
    "Flat vector game sprite. Chunky rounded outline. Friendly cartoon style "
    "similar to Overcooked or Cut the Rope. Centered on white background. "
    "No text. Clean isolated sprite."
)

OUT = "assets/ui"

# ---------------------------------------------------------------------------
# Asset definitions
# ---------------------------------------------------------------------------
ASSETS = {
    # ── Brand / Logo ──────────────────────────────────────────
    "logo_mark": (
        f"{OUT}/logo_mark.png",
        ICON_STYLE,
        "A stylized logo mark icon: an open human hand silhouette viewed from "
        "the front (palm facing viewer), with magical cyan-teal colored air "
        "wisps and sparkle particles swirling around the fingers and palm. The "
        "hand is simplified and chunky, not realistic. The wisps suggest motion "
        "and magic. Colors are cyan (#4ECDC4) and teal with white sparkle dots. "
        "The hand itself is white/light gray. Magical, playful, inviting. This "
        "is a game brand logo icon."
    ),

    # ── Game Card Icons (one per game) ────────────────────────
    "icon_fruit_chop": (
        f"{OUT}/icons/icon_fruit_chop.png",
        ICON_STYLE,
        "A game icon showing a bright red watermelon being sliced in half by a "
        "dramatic diagonal slash. The two halves are separating with red juice "
        "droplets flying out. A curved white slash trail cuts through the middle. "
        "Dynamic, exciting composition. Warm reds and greens. The icon represents "
        "a fruit-slicing game."
    ),
    "icon_whack_a_mole": (
        f"{OUT}/icons/icon_whack_a_mole.png",
        ICON_STYLE,
        "A game icon showing a cute cartoon mole character popping out of a "
        "brown dirt hole, with a large wooden mallet/hammer above it about to "
        "bonk it. The mole has big round eyes and looks surprised. Brown earth "
        "tones with a warm wooden hammer. Fun and energetic. The icon represents "
        "a whack-a-mole game."
    ),
    "icon_bubble_pop": (
        f"{OUT}/icons/icon_bubble_pop.png",
        ICON_STYLE,
        "A game icon showing 3-4 colorful translucent soap bubbles floating "
        "upward, with one bubble in the center bursting into sparkly fragments. "
        "The bubbles are iridescent with rainbow reflections -- blues, pinks, "
        "and purples. Light and airy feeling. Small sparkle stars around the "
        "popping bubble. The icon represents a bubble-popping game."
    ),
    "icon_hoops": (
        f"{OUT}/icons/icon_hoops.png",
        ICON_STYLE,
        "A game icon showing a bright orange basketball going through a red "
        "basketball hoop/net viewed from a slight angle. The ball has its "
        "characteristic black seam lines. The net is a simple white mesh hanging "
        "from a red rim. Motion lines suggest the ball is swooshing through. "
        "Energetic and sporty. The icon represents a basketball shooting game."
    ),
    "icon_hand_test": (
        f"{OUT}/icons/icon_hand_test.png",
        ICON_STYLE,
        "A game/tool icon showing a wireframe hand skeleton visualization -- "
        "an open hand outline made of thin glowing bright green lines connecting "
        "21 small circular joint dots. Like a motion-capture or hand-tracking "
        "debug display. The lines form the finger bones and palm structure. "
        "Technical but friendly, like a futuristic UI hologram. Green (#00E676) "
        "on a dark navy circle background (#1B2838). The icon represents a hand "
        "tracking test/debug tool."
    ),

    # ── Hand Cursors ──────────────────────────────────────────
    "cursor_open_hand": (
        f"{OUT}/cursors/cursor_open_hand.png",
        CURSOR_STYLE,
        "A cartoon open hand/palm viewed from the front. Five fingers spread "
        "apart in a friendly wave gesture. The hand is a warm peachy-beige skin "
        "tone with a chunky dark outline. Simple, cute, like a hand emoji but in "
        "game art style. No arm, just the hand from the wrist up. Slightly "
        "rounded chunky fingers. A soft white glow aura around the hand suggests "
        "it is a game cursor."
    ),
    "cursor_pinch_hand": (
        f"{OUT}/cursors/cursor_pinch_hand.png",
        CURSOR_STYLE,
        "A cartoon hand doing a pinch gesture -- thumb and index finger tips "
        "touching to form a circle, other three fingers relaxed. Viewed from "
        "the front. Warm peachy-beige skin tone with chunky dark outline. Small "
        "sparkle or star where the thumb and index finger meet to indicate the "
        "pinch contact point. Simple, cute, game art style. A soft glow aura "
        "around the hand."
    ),
    "cursor_fist": (
        f"{OUT}/cursors/cursor_fist.png",
        CURSOR_STYLE,
        "A cartoon closed fist viewed from the front. All fingers curled in, "
        "thumb wrapped around. Warm peachy-beige skin tone with chunky dark "
        "outline. Compact, powerful, determined expression through shape alone. "
        "Simple game art style. A soft glow aura around the fist."
    ),

    # ── UI Buttons / Icons ────────────────────────────────────
    "btn_settings": (
        f"{OUT}/buttons/btn_settings.png",
        UI_STYLE,
        "A settings gear/cog icon. Classic six-toothed gear shape with a "
        "circular hole in the center. White color, chunky rounded shape. Bold "
        "and easy to read at small sizes. Game UI icon style."
    ),
    "btn_back": (
        f"{OUT}/buttons/btn_back.png",
        UI_STYLE,
        "A back arrow icon. A chunky bold left-pointing chevron arrow (like "
        "< but thicker and rounder). White color. Simple, bold, game UI style. "
        "Easy to recognize at small sizes."
    ),
    "btn_info": (
        f"{OUT}/buttons/btn_info.png",
        UI_STYLE,
        "An information icon. A circle with a lowercase letter 'i' inside it. "
        "White color, chunky rounded style. Simple game UI icon."
    ),
    "btn_fullscreen": (
        f"{OUT}/buttons/btn_fullscreen.png",
        UI_STYLE,
        "A fullscreen toggle icon. Four small arrows pointing outward to the "
        "four corners of a square, suggesting expansion. White color, chunky "
        "bold lines. Simple game UI icon."
    ),

    # ── Decorations ───────────────────────────────────────────
    "deco_sparkle": (
        f"{OUT}/decorations/deco_sparkle.png",
        ICON_STYLE,
        "A four-pointed sparkle/twinkle star. Bright white center fading to "
        "soft cyan-teal (#4ECDC4) at the tips. Clean geometric shape with "
        "slightly rounded points. Glowing and magical. Small decorative element "
        "for sprinkling around UI elements."
    ),
    "deco_glow_circle": (
        f"{OUT}/decorations/deco_glow_circle.png",
        (
            "A soft circular glow effect on white background. A circle of warm "
            "white-yellow light that is brightest in the center and fades out "
            "smoothly to transparent at the edges. Like a lens flare or light "
            "bloom. Soft, warm, subtle. No hard edges. Decorative light effect."
        ),
        ""  # prompt_suffix is empty, full prompt is in style
    ),
    "card_shine_overlay": (
        f"{OUT}/decorations/card_shine_overlay.png",
        (
            "A subtle diagonal shine/gloss effect overlay for a game card. A "
            "thin diagonal white-to-transparent gradient strip going from "
            "upper-left to lower-right across a rectangular area. Very subtle "
            "and elegant, like light reflecting off glass. White on white "
            "background. The shine is about 20% opacity. Decorative overlay."
        ),
        ""
    ),

    # ── Hover Ring ────────────────────────────────────────────
    "hover_ring": (
        f"{OUT}/cursors/hover_ring.png",
        (
            "A circular progress ring UI element for a game. A thin glowing "
            "ring/circle outline in bright cyan-teal color (#4ECDC4). The ring "
            "is about 80% complete (like a circular progress bar with a gap). "
            "Clean vector style with a soft outer glow. White background. No "
            "text. Game HUD element for showing hover-to-select progress."
        ),
        ""
    ),
}


def main():
    parser = argparse.ArgumentParser(description="Batch-generate launcher UI assets")
    parser.add_argument("--list", action="store_true", help="List all assets without generating")
    parser.add_argument("--only", nargs="+", metavar="KEY", help="Only generate these keys")
    parser.add_argument("--skip-existing", action="store_true", help="Skip existing files")
    parser.add_argument("--quality", "-q", default="medium", choices=["low", "medium", "high"],
                        help="Quality (default: medium)")
    parser.add_argument("--model", "-m", default="gpt-image-2", help="Model (default: gpt-image-2)")
    parser.add_argument("--size", "-s", default="1024x1024", help="Size (default: 1024x1024)")
    args = parser.parse_args()

    repo_root = Path(__file__).parent.parent

    assets = ASSETS
    if args.only:
        unknown = set(args.only) - set(ASSETS.keys())
        if unknown:
            print(f"ERROR: Unknown keys: {', '.join(unknown)}")
            print(f"Available: {', '.join(sorted(ASSETS.keys()))}")
            sys.exit(1)
        assets = {k: v for k, v in ASSETS.items() if k in args.only}

    if args.list:
        print(f"{'Key':<25} {'Path':<50} {'Exists'}")
        print("-" * 85)
        for key, (path, _s, _p) in sorted(assets.items()):
            full = repo_root / path
            print(f"{key:<25} {path:<50} {'YES' if full.exists() else 'no'}")
        print(f"\nTotal: {len(assets)} assets")
        return

    total = len(assets)
    generated = skipped = failed = 0
    print(f"Generating {total} UI assets (model={args.model}, quality={args.quality})")
    print("=" * 70)

    for i, (key, (rel_path, style, prompt_suffix)) in enumerate(assets.items(), 1):
        full_path = repo_root / rel_path
        if args.skip_existing and full_path.exists():
            print(f"[{i}/{total}] SKIP: {key}")
            skipped += 1
            continue

        # Build full prompt: style + suffix (some assets have empty suffix)
        if prompt_suffix:
            full_prompt = f"{style}\n\n{prompt_suffix}"
        else:
            full_prompt = style

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
            if i < total:
                time.sleep(1)
        except Exception as e:
            print(f"  FAILED: {e}")
            failed += 1

    print("\n" + "=" * 70)
    print(f"Done! Generated: {generated}, Skipped: {skipped}, Failed: {failed}")


if __name__ == "__main__":
    main()
