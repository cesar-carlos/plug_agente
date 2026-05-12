#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.request
import xml.etree.ElementTree as et
from dataclasses import dataclass
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tool import appcast_manager


@dataclass(frozen=True)
class ReleaseAsset:
    name: str
    url: str
    size: str
    digest: str


@dataclass(frozen=True)
class ReleaseInfo:
    tag: str
    name: str
    body: str
    asset: ReleaseAsset


def github_request_json(url: str) -> dict[str, Any]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "plug-agente-release-validator",
    }
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def load_release(repo: str, tag: str) -> ReleaseInfo:
    data = github_request_json(f"https://api.github.com/repos/{repo}/releases/tags/{tag}")
    version = tag.removeprefix("v")
    expected_asset_name = f"PlugAgente-Setup-{version}.exe"
    assets = data.get("assets") or []
    matching_assets = [asset for asset in assets if asset.get("name") == expected_asset_name]
    if not matching_assets:
        names = ", ".join(str(asset.get("name")) for asset in assets) or "<none>"
        raise ValueError(f"Release asset {expected_asset_name!r} not found. Available assets: {names}")

    asset = matching_assets[0]
    return ReleaseInfo(
        tag=str(data.get("tag_name") or tag),
        name=str(data.get("name") or ""),
        body=str(data.get("body") or ""),
        asset=ReleaseAsset(
            name=str(asset.get("name") or ""),
            url=str(asset.get("browser_download_url") or ""),
            size=str(asset.get("size") or ""),
            digest=str(asset.get("digest") or ""),
        ),
    )


def load_appcast_tree(args: argparse.Namespace) -> et.ElementTree | None:
    if args.appcast:
        return et.parse(args.appcast)
    if args.feed_url:
        return et.ElementTree(
            appcast_manager.fetch_feed_root(
                args.feed_url,
                cache_bust=not args.no_cache_bust,
            )
        )
    return None


def latest_version_from_appcast(tree: et.ElementTree, version_short: str) -> str:
    channel = tree.getroot().find("channel")
    if channel is None:
        raise ValueError("appcast missing <channel>.")
    items = channel.findall("item")
    if not items:
        raise ValueError("appcast missing <item>.")

    latest_enclosure = items[0].find("enclosure")
    latest_version = appcast_manager._sparkle_version(latest_enclosure)
    if latest_version.split("+", 1)[0] != version_short:
        raise ValueError(
            f"latest appcast version {latest_version!r} does not match release version {version_short!r}."
        )
    return latest_version


def validate_appcast(args: argparse.Namespace, release: ReleaseInfo) -> str | None:
    tree = load_appcast_tree(args)
    if tree is None:
        return None

    version_short = release.tag.removeprefix("v")
    full_version = args.full_version or latest_version_from_appcast(tree, version_short)
    context = appcast_manager.AppcastContext(
        version_short=version_short,
        full_version=full_version,
        asset_url=release.asset.url,
        asset_size=release.asset.size,
        asset_name=release.asset.name,
        release_body=release.body,
        max_items=args.max_items,
    )
    appcast_manager.validate_appcast_tree(tree, context)
    return full_version


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate a GitHub Release asset and optional appcast feed.")
    parser.add_argument("--repo", default="cesar-carlos/plug_agente")
    parser.add_argument("--tag", required=True, help="Release tag, for example v1.6.5.")
    parser.add_argument("--full-version", help="Expected full app version, for example 1.6.5+1.")
    parser.add_argument("--appcast", type=Path, help="Local appcast.xml to validate.")
    parser.add_argument("--feed-url", help="Published appcast feed URL to validate.")
    parser.add_argument("--max-items", type=int, default=10)
    parser.add_argument(
        "--no-cache-bust",
        action="store_true",
        help="Do not append a cb query parameter when fetching --feed-url.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        release = load_release(args.repo, args.tag)
        full_version = validate_appcast(args, release)
    except Exception as error:
        print(f"Release validation failed: {error}", file=sys.stderr)
        return 1

    details = [
        f"tag={release.tag}",
        f"asset={release.asset.name}",
        f"size={release.asset.size}",
    ]
    if full_version:
        details.append(f"appcast_version={full_version}")
    if release.asset.digest:
        details.append(f"digest={release.asset.digest}")
    print(f"Release validation passed ({', '.join(details)}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
