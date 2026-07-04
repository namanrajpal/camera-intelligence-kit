#!/usr/bin/env python3
"""
generate_asset.py -- OpenAI GPT Image asset generator for Camera Intelligence Kit.

Usage:
    python tools/generate_asset.py --prompt "A cartoon watermelon..." --output assets/fruit/watermelon.png
    python tools/generate_asset.py --prompt "..." --output out.png --size 1024x1024 --quality medium
    python tools/generate_asset.py --prompt "..." --output out.png --model gpt-image-1

Requires: pip install openai
Reads OPENAI_API_KEY from environment or from keys.md in repo root.
"""

import argparse
import base64
import os
import sys
from pathlib import Path


def get_api_key() -> str:
    """Get API key from env var or keys.md fallback."""
    key = os.environ.get("OPENAI_API_KEY")
    if key:
        return key

    # Fallback: read from keys.md in repo root
    keys_file = Path(__file__).parent.parent / "keys.md"
    if keys_file.exists():
        for line in keys_file.read_text().splitlines():
            if line.startswith("OPENAI_API_KEY="):
                return line.split("=", 1)[1].strip()

    print("ERROR: No OPENAI_API_KEY found in environment or keys.md", file=sys.stderr)
    sys.exit(1)


def generate_image(
    prompt: str,
    output_path: str,
    size: str = "1024x1024",
    quality: str = "low",
    model: str = "gpt-image-1",
) -> str:
    """Generate an image and save it. Returns the output path."""
    try:
        from openai import OpenAI
    except ImportError:
        print(
            "ERROR: openai package not installed. Run: pip install openai",
            file=sys.stderr,
        )
        sys.exit(1)

    client = OpenAI(api_key=get_api_key())

    print(f"Generating: {output_path}")
    print(f"  Model:   {model}")
    print(f"  Size:    {size}")
    print(f"  Quality: {quality}")
    print(f"  Prompt:  {prompt[:120]}{'...' if len(prompt) > 120 else ''}")

    result = client.images.generate(
        model=model,
        prompt=prompt,
        size=size,
        quality=quality,
    )

    image_base64 = result.data[0].b64_json
    image_bytes = base64.b64decode(image_base64)

    # Ensure output directory exists
    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(image_bytes)

    size_kb = len(image_bytes) / 1024
    print(f"  Saved:   {out} ({size_kb:.1f} KB)")
    return str(out)


def main():
    parser = argparse.ArgumentParser(
        description="Generate game assets via OpenAI GPT Image"
    )
    parser.add_argument("--prompt", "-p", required=True, help="Image generation prompt")
    parser.add_argument("--output", "-o", required=True, help="Output PNG path")
    parser.add_argument(
        "--size",
        "-s",
        default="1024x1024",
        help="Image size (default: 1024x1024)",
    )
    parser.add_argument(
        "--quality",
        "-q",
        default="low",
        choices=["low", "medium", "high", "auto"],
        help="Quality (default: low for fast iteration)",
    )
    parser.add_argument(
        "--model",
        "-m",
        default="gpt-image-1",
        help="Model (default: gpt-image-1, also: gpt-image-2)",
    )
    args = parser.parse_args()

    generate_image(args.prompt, args.output, args.size, args.quality, args.model)


if __name__ == "__main__":
    main()
