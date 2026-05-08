from __future__ import annotations

import sys
import tempfile
import threading
import unittest
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tool import appcast_manager


class AppcastManagerTests(unittest.TestCase):
    def build_context(
        self,
        *,
        version_short: str = "1.6.0",
        full_version: str = "1.6.0+1",
        asset_url: str = "https://example.com/releases/download/v1.6.0/PlugAgente-Setup-1.6.0.exe",
        asset_size: str = "12345",
        release_body: str = "Release notes with <tag> & details",
        asset_name: str = "PlugAgente-Setup-1.6.0.exe",
        max_items: int = 2,
    ) -> appcast_manager.AppcastContext:
        return appcast_manager.AppcastContext(
            version_short=version_short,
            full_version=full_version,
            asset_url=asset_url,
            asset_size=asset_size,
            release_body=release_body,
            asset_name=asset_name,
            max_items=max_items,
        )

    def test_update_appcast_tree_deduplicates_and_trims_items(self) -> None:
        tree = appcast_manager.et.ElementTree(appcast_manager._base_rss_root())
        root = tree.getroot()
        channel = appcast_manager._ensure_channel(root)

        def add_item(version: str) -> None:
            item = appcast_manager.et.SubElement(channel, "item")
            appcast_manager.et.SubElement(item, "title").text = f"Version {version}"
            appcast_manager.et.SubElement(item, "description").text = "Older"
            enclosure = appcast_manager.et.SubElement(item, "enclosure")
            enclosure.set(appcast_manager._sparkle_attr("version"), version)
            enclosure.set(appcast_manager._sparkle_attr("os"), appcast_manager.WINDOWS_OS_NAME)
            enclosure.set("url", f"https://example.com/{version}.exe")
            enclosure.set("length", "42")
            enclosure.set("type", appcast_manager.ENCLOSURE_MIME_TYPE)

        add_item("1.5.9+1")
        add_item("1.6.0+1")
        add_item("1.5.8+1")

        context = self.build_context(max_items=2)
        appcast_manager.update_appcast_tree(
            tree,
            context,
            published_at=datetime(2026, 5, 8, 12, 0, tzinfo=timezone.utc),
        )

        items = tree.getroot().find("channel").findall("item")
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0].findtext("title"), "Version 1.6.0+1")
        self.assertEqual(items[1].findtext("title"), "Version 1.5.9+1")

    def test_update_appcast_tree_round_trips_release_body_without_double_escaping(self) -> None:
        context = self.build_context(release_body="Body with <tag> & details")
        tree = appcast_manager.update_appcast_tree(
            appcast_manager.et.ElementTree(appcast_manager._base_rss_root()),
            context,
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "appcast.xml"
            appcast_manager.write_appcast_tree(tree, path)
            parsed = appcast_manager.et.parse(path)
            description = parsed.getroot().find("channel").find("item").findtext("description")
            self.assertEqual(description, "Body with <tag> & details")

    def test_validate_appcast_tree_requires_latest_item_to_match_context(self) -> None:
        context = self.build_context()
        tree = appcast_manager.update_appcast_tree(
            appcast_manager.et.ElementTree(appcast_manager._base_rss_root()),
            context,
        )
        appcast_manager.validate_appcast_tree(tree, context)

        latest_enclosure = tree.getroot().find("channel").find("item").find("enclosure")
        latest_enclosure.set("url", "https://example.com/other.exe")
        with self.assertRaisesRegex(ValueError, "latest enclosure URL does not match release asset URL"):
            appcast_manager.validate_appcast_tree(tree, context)

    def test_smoke_validate_feed_reads_latest_item_from_local_server(self) -> None:
        context = self.build_context()
        tree = appcast_manager.update_appcast_tree(
            appcast_manager.et.ElementTree(appcast_manager._base_rss_root()),
            context,
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            appcast_path = Path(tmpdir) / "appcast.xml"
            appcast_manager.write_appcast_tree(tree, appcast_path)
            body = appcast_path.read_bytes()

            class Handler(BaseHTTPRequestHandler):
                def do_GET(self) -> None:  # noqa: N802
                    self.send_response(200)
                    self.send_header("Content-Type", "application/rss+xml; charset=utf-8")
                    self.end_headers()
                    self.wfile.write(body)

                def log_message(self, format: str, *args: object) -> None:  # noqa: A003
                    return

            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                appcast_manager.smoke_validate_feed(
                    f"http://127.0.0.1:{server.server_port}/appcast.xml",
                    context,
                    attempts=1,
                    delay_seconds=0,
                )
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)

    def test_inspect_feed_url_writes_context_for_smoke_validate_url(self) -> None:
        context = self.build_context()
        tree = appcast_manager.update_appcast_tree(
            appcast_manager.et.ElementTree(appcast_manager._base_rss_root()),
            context,
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            appcast_path = Path(tmpdir) / "appcast.xml"
            env_path = Path(tmpdir) / "appcast.env"
            release_body_path = Path(tmpdir) / "release_body.txt"
            appcast_manager.write_appcast_tree(tree, appcast_path)
            body = appcast_path.read_bytes()

            class Handler(BaseHTTPRequestHandler):
                def do_GET(self) -> None:  # noqa: N802
                    self.send_response(200)
                    self.send_header("Content-Type", "application/rss+xml; charset=utf-8")
                    self.end_headers()
                    self.wfile.write(body)

                def log_message(self, format: str, *args: object) -> None:  # noqa: A003
                    return

            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                inspected = appcast_manager.inspect_feed_url(
                    f"http://127.0.0.1:{server.server_port}/appcast.xml",
                    max_items=context.max_items,
                )
                appcast_manager.write_shell_env(env_path, inspected)
                release_body_path.write_text(inspected.release_body, encoding="utf-8")
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)

            env_content = env_path.read_text(encoding="utf-8")
            self.assertIn("FULL_VERSION=1.6.0+1", env_content)
            self.assertIn("ASSET_NAME=PlugAgente-Setup-1.6.0.exe", env_content)
            self.assertEqual(release_body_path.read_text(encoding="utf-8"), context.release_body)


if __name__ == "__main__":
    unittest.main()
