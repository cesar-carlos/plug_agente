#!/usr/bin/env python3
from __future__ import annotations


import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]
_ROOT = _TOOL_DIR.parent
for _entry in (str(_ROOT), str(_TOOL_DIR)):
    if _entry not in sys.path:
        sys.path.insert(0, _entry)

import argparse
import re
import shlex
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as et
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
PLUG_NS = "https://plug.se7esistemas.com/appcast"
APPCAST_TITLE = "Plug Agente Updates"
APPCAST_LINK = "https://github.com/cesar-carlos/plug_agente/releases"
APPCAST_DESCRIPTION = "Atualizacoes do Plug Agente"
ENCLOSURE_MIME_TYPE = "application/octet-stream"
WINDOWS_OS_NAME = "windows"
CONTROL_CHAR_RE = re.compile(r"[\x00-\x08\x0B\x0C\x0E-\x1F]")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
DEFAULT_CHANNEL = "stable"
DEFAULT_ROLLOUT_PERCENTAGE = 100


@dataclass(frozen=True)
class AppcastContext:
    version_short: str
    full_version: str
    asset_url: str
    asset_size: str
    asset_sha256: str
    release_body: str = ""
    asset_name: str = ""
    channel: str = DEFAULT_CHANNEL
    rollout_percentage: int = DEFAULT_ROLLOUT_PERCENTAGE
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

    @property
    def expected_asset_sha256(self) -> str:
        return normalize_sha256(self.asset_sha256)

    @property
    def expected_channel(self) -> str:
        channel = (self.channel or DEFAULT_CHANNEL).strip().lower()
        if not channel:
            return DEFAULT_CHANNEL
        return channel

    @property
    def expected_rollout_percentage(self) -> int:
        percentage = int(self.rollout_percentage)
        if percentage < 0 or percentage > 100:
            raise ValueError("rollout percentage must be between 0 and 100")
        return percentage


def sanitize_release_notes(raw: str, max_len: int = 2000) -> str:
    normalized = (raw or "").lstrip("\ufeff").replace("\r\n", "\n").replace("\r", "\n")
    cleaned = CONTROL_CHAR_RE.sub("", normalized)
    return cleaned[:max_len]


def normalize_sha256(value: str) -> str:
    normalized = (value or "").strip().lower()
    if normalized.startswith("sha256:"):
        normalized = normalized.split(":", 1)[1].strip()
    if not SHA256_RE.fullmatch(normalized):
        raise ValueError("asset SHA-256 must be a 64-character lowercase hexadecimal digest")
    return normalized


def _sparkle_attr(name: str) -> str:
    return f"{{{SPARKLE_NS}}}{name}"


def _plug_attr(name: str) -> str:
    return f"{{{PLUG_NS}}}{name}"


def _sparkle_version(enclosure: et.Element | None) -> str:
    if enclosure is None:
        return ""
    return (enclosure.get(_sparkle_attr("version")) or enclosure.get("sparkle:version") or "").strip()


def _sparkle_os(enclosure: et.Element | None) -> str:
    if enclosure is None:
        return ""
    return (enclosure.get(_sparkle_attr("os")) or enclosure.get("sparkle:os") or "").strip()


def _plug_sha256(enclosure: et.Element | None) -> str:
    if enclosure is None:
        return ""
    raw = enclosure.get(_plug_attr("sha256")) or enclosure.get("plug:sha256") or ""
    return normalize_sha256(raw)


def _plug_channel(enclosure: et.Element | None) -> str:
    if enclosure is None:
        return DEFAULT_CHANNEL
    raw = enclosure.get(_plug_attr("channel")) or enclosure.get("plug:channel") or DEFAULT_CHANNEL
    return raw.strip().lower() or DEFAULT_CHANNEL


def _plug_rollout_percentage(enclosure: et.Element | None) -> int:
    if enclosure is None:
        return DEFAULT_ROLLOUT_PERCENTAGE
    raw = enclosure.get(_plug_attr("rolloutPercentage")) or enclosure.get("plug:rolloutPercentage") or ""
    if not raw.strip():
        return DEFAULT_ROLLOUT_PERCENTAGE
    percentage = int(raw.strip())
    if percentage < 0 or percentage > 100:
        raise ValueError("plug:rolloutPercentage must be between 0 and 100")
    return percentage


def _cache_busted_url(feed_url: str) -> str:
    parsed = urllib.parse.urlparse(feed_url)
    query = dict(urllib.parse.parse_qsl(parsed.query, keep_blank_values=True))
    query["cb"] = str(int(time.time()))
    return urllib.parse.urlunparse(parsed._replace(query=urllib.parse.urlencode(query)))


def _ensure_channel(root: et.Element) -> et.Element:
    channel = root.find("channel")
    if channel is not None:
        return channel

    channel = et.SubElement(root, "channel")
    et.SubElement(channel, "title").text = APPCAST_TITLE
    et.SubElement(channel, "link").text = APPCAST_LINK
    et.SubElement(channel, "description").text = APPCAST_DESCRIPTION
    return channel


def _find_matching_item(channel: et.Element, context: AppcastContext) -> et.Element | None:
    for item in channel.findall("item"):
        enclosure = item.find("enclosure")
        if _sparkle_version(enclosure) in {context.version, context.version_short}:
            return item
    return None


def _item_matches_context(item: et.Element, context: AppcastContext) -> bool:
    try:
        validate_item(item, context)
    except Exception:
        return False
    return True


def _build_appcast_item(
    context: AppcastContext,
    *,
    pub_date: str,
    signing_private_key_b64: str | None = None,
) -> et.Element:
    item = et.Element("item")
    et.SubElement(item, "title").text = context.expected_title
    et.SubElement(item, "pubDate").text = pub_date
    et.SubElement(item, "description").text = context.expected_description
    enclosure = et.SubElement(item, "enclosure")
    enclosure.set("url", context.asset_url)
    enclosure.set(_sparkle_attr("version"), context.version)
    enclosure.set(_sparkle_attr("os"), WINDOWS_OS_NAME)
    enclosure.set(_plug_attr("sha256"), context.expected_asset_sha256)
    enclosure.set(_plug_attr("channel"), context.expected_channel)
    enclosure.set(_plug_attr("rolloutPercentage"), str(context.expected_rollout_percentage))
    enclosure.set("length", str(context.asset_size))
    enclosure.set("type", ENCLOSURE_MIME_TYPE)
    if signing_private_key_b64:
        from tool.appcast.appcast_signing import EnclosureSignaturePayload, sign_payload

        payload = EnclosureSignaturePayload(
            version=context.version,
            os=WINDOWS_OS_NAME,
            sha256=context.expected_asset_sha256,
            channel=context.expected_channel,
            rollout_percentage=context.expected_rollout_percentage,
            asset_url=context.asset_url,
            asset_size=int(context.asset_size),
        )
        enclosure.set(_plug_attr("edSignature"), sign_payload(payload, signing_private_key_b64))
    return item


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
    *,
    signing_private_key_b64: str | None = None,
) -> et.ElementTree:
    published_at = published_at or datetime.now(timezone.utc)
    root = tree.getroot()
    channel = _ensure_channel(root)
    et.register_namespace("sparkle", SPARKLE_NS)
    et.register_namespace("plug", PLUG_NS)
    matching_item = _find_matching_item(channel, context)
    existing_pub_date = (matching_item.findtext("pubDate") or "").strip() if matching_item is not None else ""

    for item in list(channel.findall("item")):
        enclosure = item.find("enclosure")
        sparkle_version = _sparkle_version(enclosure)
        if sparkle_version in {context.version, context.version_short}:
            channel.remove(item)

    if matching_item is not None and existing_pub_date and _item_matches_context(matching_item, context):
        item = matching_item
    else:
        item = _build_appcast_item(
            context,
            pub_date=existing_pub_date or published_at.strftime("%a, %d %b %Y %H:%M:%S +0000"),
            signing_private_key_b64=signing_private_key_b64,
        )
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
    sha256 = _plug_sha256(enclosure)
    channel = _plug_channel(enclosure)
    rollout_percentage = _plug_rollout_percentage(enclosure)

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
    if sha256 != context.expected_asset_sha256:
        raise ValueError("latest enclosure plug:sha256 does not match release asset SHA-256")
    if channel != context.expected_channel:
        raise ValueError("latest enclosure plug:channel does not match release channel")
    if rollout_percentage != context.expected_rollout_percentage:
        raise ValueError("latest enclosure plug:rolloutPercentage does not match release rollout percentage")
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


def fetch_feed_root(feed_url: str, *, cache_bust: bool = True) -> et.Element:
    request_url = _cache_busted_url(feed_url) if cache_bust else feed_url
    request = urllib.request.Request(
        request_url,
        headers={"Cache-Control": "no-cache", "Pragma": "no-cache"},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        body = response.read()
    return et.fromstring(body)


def context_from_latest_item(item: et.Element, *, max_items: int = 10) -> AppcastContext:
    description = (item.findtext("description") or "").strip()
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("missing <enclosure> in latest item")

    version = _sparkle_version(enclosure)
    if not version:
        raise ValueError("latest item missing sparkle:version")

    asset_url = (enclosure.get("url") or "").strip()
    asset_size = (enclosure.get("length") or "").strip()
    asset_sha256 = _plug_sha256(enclosure)
    channel = _plug_channel(enclosure)
    rollout_percentage = _plug_rollout_percentage(enclosure)
    asset_name = Path(urllib.parse.urlparse(asset_url).path).name
    context = AppcastContext(
        version_short=version.split("+", 1)[0],
        full_version=version,
        asset_url=asset_url,
        asset_size=asset_size,
        asset_sha256=asset_sha256,
        asset_name=asset_name,
        channel=channel,
        rollout_percentage=rollout_percentage,
        release_body=description,
        max_items=max_items,
    )
    validate_item(item, context)
    return context


def inspect_feed_url(feed_url: str, *, max_items: int = 10, cache_bust: bool = True) -> AppcastContext:
    root = fetch_feed_root(feed_url, cache_bust=cache_bust)
    channel = root.find("channel")
    if channel is None:
        raise ValueError("missing <channel>")

    items = channel.findall("item")
    if not items:
        raise ValueError("missing <item>")
    if len(items) > max_items:
        raise ValueError(f"item count {len(items)} exceeds limit {max_items}")

    return context_from_latest_item(items[0], max_items=max_items)


def write_shell_env(path: Path, context: AppcastContext) -> None:
    values = {
        "VERSION_SHORT": context.version_short,
        "FULL_VERSION": context.full_version,
        "ASSET_URL": context.asset_url,
        "ASSET_SIZE": context.asset_size,
        "ASSET_NAME": context.expected_asset_name,
        "ASSET_SHA256": context.expected_asset_sha256,
        "CHANNEL": context.expected_channel,
        "ROLLOUT_PERCENTAGE": str(context.expected_rollout_percentage),
    }
    path.write_text(
        "".join(f"{key}={shlex.quote(value)}\n" for key, value in values.items()),
        encoding="utf-8",
    )


def smoke_validate_feed(
    feed_url: str,
    context: AppcastContext,
    *,
    attempts: int = 6,
    delay_seconds: int = 5,
    cache_bust: bool = True,
) -> None:
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            root = fetch_feed_root(feed_url, cache_bust=cache_bust)
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
        asset_sha256=args.asset_sha256,
        asset_name=getattr(args, "asset_name", "") or "",
        channel=getattr(args, "channel", DEFAULT_CHANNEL),
        rollout_percentage=getattr(args, "rollout_percentage", DEFAULT_ROLLOUT_PERCENTAGE),
        release_body=load_release_body(getattr(args, "release_body_file", None)),
        max_items=args.max_items,
    )


def command_update(args: argparse.Namespace) -> int:
    context = build_context_from_args(args)
    tree = load_or_create_tree(args.appcast)
    signing_key = getattr(args, "signing_private_key", None) or None
    update_appcast_tree(tree, context, signing_private_key_b64=signing_key)
    write_appcast_tree(tree, args.appcast)
    signed = " (signed)" if signing_key else ""
    print(f"Successfully updated {args.appcast} with version {context.version}{signed}")
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
        cache_bust=not args.no_cache_bust,
    )
    print(
        "Published appcast smoke validation passed "
        f"(version={context.version}, feed={args.feed_url})."
    )
    return 0


def command_inspect_url(args: argparse.Namespace) -> int:
    context = inspect_feed_url(
        args.feed_url,
        max_items=args.max_items,
        cache_bust=not args.no_cache_bust,
    )
    write_shell_env(args.env_file, context)
    args.release_body_file.write_text(context.release_body, encoding="utf-8")
    print(
        "Current appcast inspection passed "
        f"(version={context.version}, asset={context.expected_asset_name})."
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
        subparser.add_argument("--asset-sha256", required=True)
        subparser.add_argument("--asset-name", default="")
        subparser.add_argument("--channel", default=DEFAULT_CHANNEL)
        subparser.add_argument("--rollout-percentage", type=int, default=DEFAULT_ROLLOUT_PERCENTAGE)
        subparser.add_argument("--release-body-file", type=Path)
        subparser.add_argument("--max-items", type=int, default=10)

    update_parser = subparsers.add_parser("update")
    update_parser.add_argument("--appcast", type=Path, required=True)
    update_parser.add_argument(
        "--signing-private-key",
        default="",
        help=(
            "Optional base64-encoded Ed25519 private key. When provided, the new "
            "enclosure receives a plug:edSignature attribute. Pair with "
            "AUTO_UPDATE_FEED_PUBLIC_KEY on consumer builds."
        ),
    )
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
    smoke_parser.add_argument(
        "--no-cache-bust",
        action="store_true",
        help="Do not append a cb query parameter when fetching the feed.",
    )
    add_shared_arguments(smoke_parser)
    smoke_parser.set_defaults(func=command_smoke_validate_url)

    inspect_parser = subparsers.add_parser("inspect-url")
    inspect_parser.add_argument("--feed-url", required=True)
    inspect_parser.add_argument("--env-file", type=Path, required=True)
    inspect_parser.add_argument("--release-body-file", type=Path, required=True)
    inspect_parser.add_argument("--max-items", type=int, default=10)
    inspect_parser.add_argument(
        "--no-cache-bust",
        action="store_true",
        help="Do not append a cb query parameter when fetching the feed.",
    )
    inspect_parser.set_defaults(func=command_inspect_url)

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
