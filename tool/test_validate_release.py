from __future__ import annotations

import argparse
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tool import appcast_manager
from tool import validate_release


class ValidateReleaseTests(unittest.TestCase):
    def build_release(self) -> validate_release.ReleaseInfo:
        return validate_release.ReleaseInfo(
            tag="v1.6.6",
            name="Version 1.6.6",
            body="Release notes",
            asset=validate_release.ReleaseAsset(
                name="PlugAgente-Setup-1.6.6.exe",
                url="https://github.com/cesar-carlos/plug_agente/releases/download/v1.6.6/PlugAgente-Setup-1.6.6.exe",
                size="12345",
                digest="sha256:abc",
            ),
        )

    def test_validate_appcast_accepts_release_context(self) -> None:
        release = self.build_release()
        context = appcast_manager.AppcastContext(
            version_short="1.6.6",
            full_version="1.6.6+1",
            asset_url=release.asset.url,
            asset_size=release.asset.size,
            asset_name=release.asset.name,
            release_body=release.body,
        )
        tree = appcast_manager.update_appcast_tree(
            appcast_manager.et.ElementTree(appcast_manager._base_rss_root()),
            context,
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            appcast_path = Path(tmpdir) / "appcast.xml"
            appcast_manager.write_appcast_tree(tree, appcast_path)
            args = argparse.Namespace(
                appcast=appcast_path,
                feed_url=None,
                no_cache_bust=False,
                full_version=None,
                max_items=10,
            )

            full_version = validate_release.validate_appcast(args, release)

        self.assertEqual(full_version, "1.6.6+1")

    def test_validate_appcast_rejects_stale_latest_version(self) -> None:
        release = self.build_release()
        stale_context = appcast_manager.AppcastContext(
            version_short="1.6.5",
            full_version="1.6.5+1",
            asset_url=release.asset.url.replace("v1.6.6", "v1.6.5").replace("1.6.6.exe", "1.6.5.exe"),
            asset_size=release.asset.size,
            asset_name="PlugAgente-Setup-1.6.5.exe",
            release_body=release.body,
        )
        tree = appcast_manager.update_appcast_tree(
            appcast_manager.et.ElementTree(appcast_manager._base_rss_root()),
            stale_context,
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            appcast_path = Path(tmpdir) / "appcast.xml"
            appcast_manager.write_appcast_tree(tree, appcast_path)
            args = argparse.Namespace(
                appcast=appcast_path,
                feed_url=None,
                no_cache_bust=False,
                full_version=None,
                max_items=10,
            )

            with self.assertRaisesRegex(ValueError, "does not match release version"):
                validate_release.validate_appcast(args, release)


if __name__ == "__main__":
    unittest.main()
