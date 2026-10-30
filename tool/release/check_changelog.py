"""Validate application release history without treating tags as publication proof."""
import argparse
from datetime import date
from pathlib import Path
import re


def validate(text: str, version: str, *, release: bool = False) -> str:
    chunks = re.split(r"(?m)^## ", text)[1:]
    if not chunks or chunks[0].splitlines()[0] not in ("Unreleased", "[Unreleased]"):
        raise ValueError("CHANGELOG must start with one Unreleased section")
    pending = chunks[0].partition("\n")[2]
    entries = {}
    previous = None
    previous_date = None
    for chunk in chunks[1:]:
        heading, _, body = chunk.partition("\n")
        match = re.fullmatch(r"\[?(\d+\.\d+\.\d+)\]? - (\d{4}-\d{2}-\d{2})", heading)
        if not match:
            raise ValueError(f"Invalid CHANGELOG heading: {heading}")
        number, day = match.groups()
        entry_date = date.fromisoformat(day)
        if previous_date is not None and entry_date > previous_date:
            raise ValueError('CHANGELOG dates must be descending')
        previous_date = entry_date
        key = tuple(map(int, number.split('.')))
        if number in entries or (previous is not None and key >= previous):
            raise ValueError("CHANGELOG versions must be unique and descending")
        previous = key
        if not re.search(r"(?m)^Status: (tagged|local|baseline|prepared)$", body):
            raise ValueError(f"Missing or invalid status for {number}")
        if not re.search(r"(?m)^Build: " + re.escape(number) + r"(?:\+\d+)?$", body):
            raise ValueError(f"Missing or mismatched build for {number}")
        if not re.search(r"(?m)^- \S", body):
            raise ValueError(f"Missing change notes for {number}")
        entries[number] = body
    short = version.split('+')[0]
    if short not in entries:
        raise ValueError(f"Missing CHANGELOG entry for {version}")
    if short != next(iter(entries)):
        raise ValueError('Current version must be the latest CHANGELOG entry')
    body = entries[short]
    if f"Build: {version}" not in body.splitlines():
        raise ValueError(f"CHANGELOG build does not match {version}")
    if release and ("Status: prepared" not in body.splitlines() or re.sub(r'(?m)^### .*$', '', pending).strip()):
        raise ValueError("Release requires prepared notes and no pending Unreleased changes")
    return body


def check(root: Path, version: str, *, release: bool = False) -> str:
    return validate((root / 'CHANGELOG.md').read_text(encoding='utf-8'), version, release=release)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    version = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(), re.M).group(1)
    try:
        check(root, version, release=args.release)
    except (ValueError, OSError) as error:
        parser.exit(1, f'Changelog validation failed: {error}\n')
    print(f'Changelog valid for {version}')
