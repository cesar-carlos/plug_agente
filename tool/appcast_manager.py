#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as et
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
APPCAST_TITLE = "Plug Agente Updates"
APPCAST_LINK = "https://github.com/cesar-carlos/plug_agente/releases"
APPCAST_DESCRIPTION = "Atualizacoes do Plug Agente"
ENCLOSURE_MIME_TYPE = "application/octet-stream"
WINDOWS_OS_NAME = "windows"
CONTROL_CHAR_RE = re.compile(r"[\x00-\x08\x0B\x0C\x0E-\x1F]")


@dataclass(frozen=True)
class AppcastContext:
    version_short: str
    full_version: str
    asset_url: str
    asset_size: str
    release_body: str = ""
    asset_name: str = ""
    max_items: int = 10

    @property
    def version(self) -> str:
        return self.full_version or self.version_short

    @property
    def expected_title(self) -> str:
        return f"Version {self.version}"

    @property
    def expected_description(self) -> str:
        if self.release_body:
            return sanitize_release_notes(self.release_body)
        return f"Nova Versao {self.version} - Atualizacao automatica via GitHub Release."

    @property
    def expected_asset_name(self) -> str:
        if self.asset_name:
            return self.asset_name
        if self.asset_url:
            return self.asset_url.rsplit("/", 1)[-1]
        return ""


def sanitize_release_notes(raw: str, max_len: int = 2000) -> str:
    cleaned = CONTROL_CHAR_RE.sub("", raw or "")
    return cleaned[:max_len]


def _sparkle_attr(name: str) -> str:
    return f"{{{SPARKLE_NS}}}{name}"


def _sparkle_version(enclosure: et.Element | None) -> str:
    if enclosure is None:
        return ""
    return (enclosure.get(_sparkle_attr("version")) or enclosure.get("sparkle:version") or "").strip()


def _sparkle_os(enclosure: et.Element | None) -> str:
    if enclosure is None:
        return ""
    return (enclosure.get(_sparkle_attr("os")) or enclosure.get("sparkle:os") or "").strip()


def _ensure_channel(root: et.Element) -> et.Element:
    channel = root.find("channel")
    if channel is not None:
        return channel

    channel = et.SubElement(root, "channel")
    et.SubElement(channel, "title").text = APPCAST_TITLE
    et.SubElement(channel, "link").text = APPCAST_LINK
    et.SubElement(channel, "description").text = APPCAST_DESCRIPTION
    return channel


def _base_rss_root() -> et.Element:
    root = et.Element("rss")
    root.set("version", "2.0")
    return root


def load_or_create_tree(appcast_path: Path) -> et.ElementTree:
    if appcast_path.exists():
        return et.parse(appcast_path)
    return et.ElementTree(_base_rss_root())


def update_appcast_tree(
    tree: et.ElementTree,
    context: AppcastContext,
    published_at: datetime | None = None,
) -> et.ElementTree:
    published_at = published_at or datetime.now(timezone.utc)
    root = tree.getroot()
    channel = _ensure_channel(root)
    et.register_namespace("sparkle", SPARKLE_NS)

    for item in list(channel.findall("item")):
        enclosure = item.find("enclosure")
        sparkle_version = _sparkle_version(enclosure)
        if sparkle_version in {context.version, context.version_short}:
            channel.remove(item)

    item = et.Element("item")
    et.SubElement(item, "title").text = context.expected_title
    et.SubElement(item, "pubDate").text = published_at.strftime("%a, %d %b %Y %H:%M:%S +0000")
    et.SubElement(item, "description").text = context.expected_description
    enclosure = et.SubElement(item, "enclosure")
    enclosure.set("url", context.asset_url)
    enclosure.set(_sparkle_attr("version"), context.version)
    enclosure.set(_sparkle_attr("os"), WINDOWS_OS_NAME)
    enclosure.set("length", str(context.asset_size))
    enclosure.set("type", ENCLOSURE_MIME_TYPE)
    channel.insert(0, item)

    preserved = [child for child in channel if child.tag in {"title", "link", "description"}]
    items = [child for child in channel if child.tag == "item"][: context.max_items]
    for child in list(channel):
        channel.remove(child)

    if preserved:
        for child in preserved:
            channel.append(child)
    else:
        et.SubElement(channel, "title").text = APPCAST_TITLE
        et.SubElement(channel, "link").text = APPCAST_LINK
        et.SubElement(channel, "description").text = APPCAST_DESCRIPTION

    for child in items:
        channel.append(child)

    return tree


def write_appcast_tree(tree: et.ElementTree, appcast_path: Path) -> None:
    et.indent(tree, space=" ")
    with appcast_path.open("wb") as fh:
        fh.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        tree.write(fh, encoding="utf-8")


def validate_appcast_tree(tree: et.ElementTree, context: AppcastContext) -> None:
    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        raise ValueError("appcast.xml missing <channel>.")

    items = channel.findall("item")
    if not items:
        raise ValueError("appcast.xml missing <item>.")
    if len(items) > context.max_items:
        raise ValueError(
            f"invalid item count in appcast.xml: {len(items)} (expected between 1 and {context.max_items})."
        )

    latest_item = items[0]
    latest_enclosure = latest_item.find("enclosure")
    latest_version = _sparkle_version(latest_enclosure)
    if latest_version != context.version:
        raise ValueError(
            f"latest appcast item version mismatch: expected {context.version!r}, actual {latest_version!r}"
        )

    validate_item(latest_item, context)


def validate_item(item: et.Element, context: AppcastContext) -> None:
    title = (item.findtext("title") or "").strip()
    description = (item.findtext("description") or "").strip()
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("missing <enclosure> in latest item")

    version = _sparkle_version(enclosure)
    latest_url = (enclosure.get("url") or "").strip()
    latest_size = (enclosure.get("length") or "").strip()
    mime_type = (enclosure.get("type") or "").strip()
    os_name = _sparkle_os(enclosure)

    if title != context.expected_title:
        raise ValueError(
            f"unexpected title {title!r}, expected {context.expected_title!r}"
        )
    if description != context.expected_description:
        raise ValueError("latest item description does not match release body")
    if version != context.version:
        raise ValueError(
            f"unexpected version {version!r}, expected {context.version!r}"
        )
    if latest_url != context.asset_url:
        raise ValueError("latest enclosure URL does not match release asset URL")
    if latest_size != str(context.asset_size):
        raise ValueError("latest enclosure length does not match release asset size")
    if mime_type != ENCLOSURE_MIME_TYPE:
        raise ValueError(f"invalid enclosure type: {mime_type!r}")
    if os_name != WINDOWS_OS_NAME:
        raise ValueError(f"invalid sparkle:os value: {os_name!r}")
    if context.expected_asset_name and context.expected_asset_name not in latest_url:
        raise ValueError("latest enclosure URL does not include expected asset name")
    if not (latest_url.startswith("https://") and latest_url.lower().endswith(".exe")):
        raise ValueError(f"invalid enclosure url: {latest_url!r}")
    try:
        if int(latest_size) <= 0:
            raise ValueError
    except ValueError as exc:
        raise ValueError(f"invalid enclosure length: {latest_size!r}") from exc


def smoke_validate_feed(
    feed_url: str,
    context: AppcastContext,
    *,
    attempts: int = 6,
    delay_seconds: int = 5,
) -> None:
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        request = urllib.request.Request(
            f"{feed_url}?cb={int(time.time())}",
            headers={"Cache-Control": "no-cache", "Pragma": "no-cache"},
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                body = response.read()
            root = et.fromstring(body)
            channel = root.find("channel")
            if channel is None:
                raise ValueError("missing <channel>")
            items = channel.findall("item")
            if not items:
                raise ValueError("missing <item>")
            if len(items) > context.max_items:
                raise ValueError(f"item count {len(items)} exceeds limit {context.max_items}")
            validate_item(items[0], context)
            return
        except Exception as error:  # pragma: no cover - exercised via retry loop
            last_error = error
            if attempt < attempts:
                print(
                    f"Attempt {attempt}/{attempts} failed while checking published appcast: {error}. "
                    f"Retrying in {delay_seconds} seconds..."
                )
                time.sleep(delay_seconds)
    raise RuntimeError(f"published appcast smoke validation failed: {last_error}")


def load_release_body(path: Path | None) -> str:
    if path is None or not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


def build_context_from_args(args: argparse.Namespace) -> AppcastContext:
    return AppcastContext(
        version_short=args.version_short,
        full_version=args.full_version,
        asset_url=args.asset_url,
        asset_size=str(args.asset_size),
        asset_name=getattr(args, "asset_name", "") or "",
        release_body=load_release_body(getattr(args, "release_body_file", None)),
        max_items=args.max_items,
    )


def command_update(args: argparse.Namespace) -> int:
    context = build_context_from_args(args)
    tree = load_or_create_tree(args.appcast)
    update_appcast_tree(tree, context)
    write_appcast_tree(tree, args.appcast)
    print(f"Successfully updated {args.appcast} with version {context.version}")
    return 0


def command_validate_file(args: argparse.Namespace) -> int:
    context = build_context_from_args(args)
    tree = et.parse(args.appcast)
    validate_appcast_tree(tree, context)
    print(
        "appcast.xml validation passed "
        f"(version={context.version}, item_count={len(tree.getroot().find('channel').findall('item'))})"
    )
    return 0


def command_smoke_validate_url(args: argparse.Namespace) -> int:
    context = build_context_from_args(args)
    smoke_validate_feed(
        args.feed_url,
        context,
        attempts=args.attempts,
        delay_seconds=args.delay_seconds,
    )
    print(
        "Published appcast smoke validation passed "
        f"(version={context.version}, feed={args.feed_url})."
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage and validate appcast.xml")
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_shared_arguments(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument("--version-short", required=True)
        subparser.add_argument("--full-version", required=True)
        subparser.add_argument("--asset-url", required=True)
        subparser.add_argument("--asset-size", required=True)
        subparser.add_argument("--asset-name", default="")
        subparser.add_argument("--release-body-file", type=Path)
        subparser.add_argument("--max-items", type=int, default=10)

    update_parser = subparsers.add_parser("update")
    update_parser.add_argument("--appcast", type=Path, required=True)
    add_shared_arguments(update_parser)
    update_parser.set_defaults(func=command_update)

    validate_parser = subparsers.add_parser("validate-file")
    validate_parser.add_argument("--appcast", type=Path, required=True)
    add_shared_arguments(validate_parser)
    validate_parser.set_defaults(func=command_validate_file)

    smoke_parser = subparsers.add_parser("smoke-validate-url")
    smoke_parser.add_argument("--feed-url", required=True)
    smoke_parser.add_argument("--attempts", type=int, default=6)
    smoke_parser.add_argument("--delay-seconds", type=int, default=5)
    add_shared_arguments(smoke_parser)
    smoke_parser.set_defaults(func=command_smoke_validate_url)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except Exception as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
