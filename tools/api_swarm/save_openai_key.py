#!/usr/bin/env python3
"""Safely save an OpenAI API key outside the repository."""

from __future__ import annotations

import argparse
import getpass
import os
from pathlib import Path


DEFAULT_KEY_PATH = Path.home() / ".config" / "openai" / "api_key"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prompt for an OpenAI API key and save it outside the repo.",
    )
    parser.add_argument(
        "--path",
        type=Path,
        default=DEFAULT_KEY_PATH,
        help=f"Key file path. Default: {DEFAULT_KEY_PATH}",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite an existing key file without asking.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    key_path: Path = args.path.expanduser()

    if key_path.exists() and not args.force:
        answer = input(f"{key_path} already exists. Overwrite it? [y/N] ").strip().lower()
        if answer not in {"y", "yes"}:
            print("Cancelled. Existing key file left unchanged.")
            return 1

    api_key = getpass.getpass("OpenAI API key: ").strip()
    if not api_key:
        print("No key entered. Nothing written.")
        return 1

    key_path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(key_path.parent, 0o700)

    tmp_path = key_path.with_name(f".{key_path.name}.tmp")
    tmp_path.write_text(f"{api_key}\n", encoding="utf-8")
    os.chmod(tmp_path, 0o600)
    tmp_path.replace(key_path)
    os.chmod(key_path, 0o600)

    print(f"Saved API key to {key_path}")
    print("The key was not printed. Do not commit or paste this file.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
