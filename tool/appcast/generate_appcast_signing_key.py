#!/usr/bin/env python3
"""Generates a fresh Ed25519 keypair for signing the Plug Agente appcast feed.

Usage
-----

    python tool/appcast/generate_appcast_signing_key.py

Stores the secret in your CI secret manager (e.g. GitHub Actions Secrets) as
``APPCAST_SIGNING_PRIVATE_KEY`` and the public key in
``AUTO_UPDATE_FEED_PUBLIC_KEY`` so that runtime builds verify signatures
against the same key the publish workflow signs with.

The script writes both values to stdout in a key=value format suitable for
shell sourcing. Never commit the private key to the repository.

Dependency
----------

    pip install cryptography>=42.0.0
"""

from __future__ import annotations


import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]
_ROOT = _TOOL_DIR.parent
for _entry in (str(_ROOT), str(_TOOL_DIR)):
    if _entry not in sys.path:
        sys.path.insert(0, _entry)

import argparse

from tool.appcast.appcast_signing import generate_keypair


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--export-shell",
        action="store_true",
        help="Print 'export KEY=VALUE' lines instead of 'KEY=VALUE'.",
    )
    args = parser.parse_args()

    private_b64, public_b64 = generate_keypair()
    prefix = "export " if args.export_shell else ""
    print(f"{prefix}APPCAST_SIGNING_PRIVATE_KEY={private_b64}")
    print(f"{prefix}AUTO_UPDATE_FEED_PUBLIC_KEY={public_b64}")
    print()
    print("# Store APPCAST_SIGNING_PRIVATE_KEY in your CI secret manager.")
    print("# Ship AUTO_UPDATE_FEED_PUBLIC_KEY with each release build")
    print("# (--dart-define or .env on production installs).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
