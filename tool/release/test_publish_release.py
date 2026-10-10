import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tool.appcast.appcast_signing import generate_keypair
from tool.release import publish_release as publication
from tool.updater.manifest import DEFAULT_CAPABILITIES, sign, verify


class ReleasePublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.private, public = generate_keypair()
        self.release = publication.Release("1.8.6", "1.8.6+1", "stable", "owner/project", public)
        self.git("init", "-b", "main")
        (self.root / "pubspec.yaml").write_text("version: 1.8.6+1\n", encoding="utf-8")
        (self.root / "appcast.xml").write_text("initial feed", encoding="utf-8")
        (self.root / ".gitignore").write_text("installer/dist/\nremote-assets/\n", encoding="utf-8")
        self.git("add", ".")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "Fixture")
        self.commit = self.git("rev-parse", "HEAD").stdout.strip()
        self.artifacts = self.root / "installer/dist"
        self.artifacts.mkdir(parents=True)
        self.remote = self.root / "remote-assets"
        self.remote.mkdir()
        self.write_artifacts(self.artifacts)
        self.commands = []
        self.metadata = None
        self.api_error = None
        self.graphql_error = None
        self.repository_available = True
        self.fail_upload = False
        self.tamper_download = False
        self.replace_download = False
        self.replace_manifest = False
        self.fail_push = False
        self.real_command = publication.command

    def git(self, *arguments):
        return subprocess.run(["git", *arguments], cwd=self.root, check=True,
                              capture_output=True, text=True, encoding="utf-8")

    def write_artifacts(self, directory, content=b"verified installer", commit=None):
        installer, manifest = (directory / name for name in self.release.asset_names)
        installer.write_bytes(content)
        payload = {"formatVersion": 1, "version": self.release.full_version,
                   "channel": self.release.channel,
                   "installer": {"name": installer.name, "size": len(content),
                                 "sha256": hashlib.sha256(content).hexdigest()},
                   "requirements": DEFAULT_CAPABILITIES, "protocol": {"host": 1, "worker": 1},
                   "data": {"schema": 30, "rollbackProtocol": 1},
                   "release": {"tag": self.release.tag, "commit": commit or self.commit}}
        manifest.write_text(json.dumps(sign(payload, self.private)), encoding="utf-8")

    def run_command(self, arguments, root, *, check=True):
        self.commands.append(arguments)
        if arguments[:2] == ["git", "push"]:
            if self.fail_push:
                raise RuntimeError("Atomic push rejected")
            return subprocess.CompletedProcess(arguments, 0, "", "")
        if arguments[0] == "git":
            return self.real_command(arguments, root, check=check)
        if arguments[:2] == ["gh", "api"]:
            if arguments[2] != "graphql":
                # REST's tag lookup cannot find drafts.
                if self.metadata is None or self.metadata["draft"]:
                    return subprocess.CompletedProcess(arguments, 1, "", "HTTP 404: Not Found")
                return subprocess.CompletedProcess(arguments, 0, json.dumps(self.metadata), "")
            if self.api_error is not None:
                return subprocess.CompletedProcess(arguments, 1, "", self.api_error)
            entry = None if self.metadata is None else {
                "tagName": self.metadata["tag_name"], "isDraft": self.metadata["draft"],
                "isPrerelease": self.metadata["prerelease"]}
            response = {"data": {"repository": {"release": entry} if self.repository_available else None}}
            if self.graphql_error:
                response["errors"] = [{"message": self.graphql_error}]
            return subprocess.CompletedProcess(arguments, 0, json.dumps(response), "")
        operation = arguments[2]
        if operation == "create":
            self.metadata = {"tag_name": self.release.tag, "draft": True,
                             "prerelease": self.release.channel == "beta"}
        elif operation == "upload":
            if self.fail_upload:
                raise RuntimeError("Upload interrupted")
            for name in self.release.asset_names:
                shutil.copy2(self.artifacts / name, self.remote / name)
        elif operation == "download":
            destination = Path(arguments[arguments.index("--dir") + 1])
            for name in self.release.asset_names:
                shutil.copy2(self.remote / name, destination / name)
            if self.tamper_download:
                (destination / self.release.asset_names[0]).write_bytes(b"corrupt upload")
            if self.replace_download:
                self.write_artifacts(destination, content=b"different but correctly signed installer")
            if self.replace_manifest:
                manifest = destination / self.release.asset_names[1]
                payload = verify(json.loads(manifest.read_text()), [self.release.public_keys])
                payload["data"]["schema"] += 1
                manifest.write_text(json.dumps(sign(payload, self.private)))
        elif operation == "edit":
            self.metadata["draft"] = False
        else:
            self.fail(f"Unexpected command: {arguments}")
        return subprocess.CompletedProcess(arguments, 0, "", "")

    def publish(self):
        with patch.object(publication, "command", side_effect=self.run_command):
            publication.publish(self.release, self.root)

    def writes(self):
        return [args for args in self.commands if args[:2] == ["git", "push"] or
                args[:3] in (["gh", "release", "create"], ["gh", "release", "upload"], ["gh", "release", "edit"])]

    def published_release(self):
        self.git("tag", self.release.tag)
        self.metadata = {"tag_name": self.release.tag, "draft": False,
                         "prerelease": self.release.channel == "beta"}
        self.write_artifacts(self.remote)

    def test_new_release_pushes_atomically_and_verifies_upload_before_publication(self):
        self.publish()
        self.assertFalse(self.metadata["draft"])
        operations = [args[:3] for args in self.writes()]
        self.assertEqual(operations, [["git", "push", "--atomic"], ["gh", "release", "create"],
                                     ["gh", "release", "upload"], ["gh", "release", "edit"]])
        push = self.writes()[0]
        self.assertIn("HEAD:refs/heads/main", push)
        self.assertIn(f"refs/tags/{self.release.tag}", push)
        create = self.writes()[1]
        self.assertIn("--draft", create)
        self.assertIn("--verify-tag", create)
        self.assertIn("--latest", self.writes()[-1])
        download = next(index for index, args in enumerate(self.commands) if args[:3] == ["gh", "release", "download"])
        edit = next(index for index, args in enumerate(self.commands) if args[:3] == ["gh", "release", "edit"])
        self.assertLess(download, edit)

    def test_invalid_local_installer_signature_or_commit_never_writes_remotely(self):
        for corruption in ("installer", "signature", "commit"):
            with self.subTest(corruption=corruption):
                self.write_artifacts(self.artifacts)
                if corruption == "installer":
                    (self.artifacts / self.release.asset_names[0]).write_bytes(b"tampered")
                elif corruption == "signature":
                    path = self.artifacts / self.release.asset_names[1]
                    envelope = json.loads(path.read_text())
                    envelope["signatureBase64"] = "A" * 88
                    path.write_text(json.dumps(envelope))
                else:
                    self.write_artifacts(self.artifacts, commit="b" * 40)
                with self.assertRaises(ValueError):
                    self.publish()
                self.assertEqual(self.writes(), [])

    def test_missing_public_key_blocks_publication(self):
        self.release = publication.Release("1.8.6", "1.8.6+1", "stable", "owner/project", "")
        with self.assertRaisesRegex(ValueError, "PUBLIC_KEY"):
            self.publish()
        self.assertEqual(self.writes(), [])

    def test_api_authentication_or_server_error_does_not_create_a_release(self):
        for error in ("HTTP 401: Unauthorized", "HTTP 404: Not Found", "HTTP 500: Server Error"):
            self.api_error = error
            with self.subTest(error=error), self.assertRaisesRegex(RuntimeError, "inspect GitHub release"):
                self.publish()
            self.assertEqual(self.writes(), [])

    def test_graphql_errors_do_not_create_a_release(self):
        self.graphql_error = "Resource not accessible by integration"
        with self.assertRaisesRegex(RuntimeError, "Resource not accessible"):
            self.publish()
        self.assertEqual(self.writes(), [])

    def test_inaccessible_repository_is_not_treated_as_a_missing_release(self):
        self.repository_available = False
        with self.assertRaisesRegex(RuntimeError, "repository is unavailable"):
            self.publish()
        self.assertEqual(self.writes(), [])

    def test_interrupted_upload_leaves_a_draft_and_can_be_resumed(self):
        self.fail_upload = True
        with self.assertRaisesRegex(RuntimeError, "Upload interrupted"):
            self.publish()
        self.assertTrue(self.metadata["draft"])
        self.commands.clear()
        self.fail_upload = False
        self.publish()
        self.assertFalse(self.metadata["draft"])
        self.assertFalse(any(args[:2] == ["git", "push"] or args[:3] == ["gh", "release", "create"]
                             for args in self.commands))

    def test_tampered_uploaded_installer_is_not_published(self):
        self.tamper_download = True
        with self.assertRaisesRegex(ValueError, "does not match signed manifest"):
            self.publish()
        self.assertTrue(self.metadata["draft"])
        self.assertFalse(any(args[:3] == ["gh", "release", "edit"] for args in self.commands))

    def test_upload_must_match_local_artifacts_even_when_replacement_is_correctly_signed(self):
        self.replace_download = True
        with self.assertRaisesRegex(ValueError, "Uploaded asset differs"):
            self.publish()
        self.assertTrue(self.metadata["draft"])
        self.assertFalse(any(args[:3] == ["gh", "release", "edit"] for args in self.commands))

    def test_installer_hashes_are_computed_once_per_local_and_downloaded_asset(self):
        with patch.object(hashlib, "file_digest", wraps=hashlib.file_digest) as digest:
            self.publish()
        installer_reads = [call.args[0].name for call in digest.call_args_list
                           if Path(call.args[0].name).name == self.release.asset_names[0]]
        self.assertEqual(len(installer_reads), 2)
        self.assertEqual(len(set(installer_reads)), 2)
        self.assertFalse(self.metadata["draft"])

    def test_a_different_valid_manifest_cannot_replace_the_verified_local_manifest(self):
        self.replace_manifest = True
        with self.assertRaisesRegex(ValueError, self.release.asset_names[1]):
            self.publish()
        self.assertTrue(self.metadata["draft"])
        self.assertFalse(any(args[:3] == ["gh", "release", "edit"] for args in self.commands))

    def test_existing_public_release_keeps_original_assets_after_a_rebuild(self):
        self.published_release()
        self.write_artifacts(self.artifacts, content=b"rebuilt installer with a new timestamp")
        (self.root / "appcast.xml").write_text("published feed", encoding="utf-8")
        self.publish()
        self.assertEqual(self.writes(), [])
        self.assertEqual((self.remote / self.release.asset_names[0]).read_bytes(), b"verified installer")

    def test_corrupt_public_release_is_rejected_without_replacing_assets(self):
        self.published_release()
        (self.remote / self.release.asset_names[0]).write_bytes(b"corrupt")
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(self.writes(), [])

    def test_existing_tag_with_changed_source_or_build_number_is_rejected(self):
        self.git("tag", self.release.tag)
        (self.root / "pubspec.yaml").write_text("version: 1.8.6+2\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "different source"):
            self.publish()
        self.assertEqual(self.writes(), [])

    def test_existing_release_with_wrong_channel_is_rejected(self):
        self.published_release()
        self.metadata["prerelease"] = True
        with self.assertRaisesRegex(ValueError, "prerelease status"):
            self.publish()
        self.assertEqual(self.writes(), [])

    def test_uncommitted_source_is_rejected_for_new_releases(self):
        (self.root / "pubspec.yaml").write_text("version: 1.8.6+2\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Commit tracked source"):
            self.publish()
        self.assertEqual(self.writes(), [])

    def test_atomic_push_failure_does_not_create_a_release(self):
        self.fail_push = True
        with self.assertRaisesRegex(RuntimeError, "Atomic push rejected"):
            self.publish()
        self.assertFalse(any(args[:3] == ["gh", "release", "create"] for args in self.commands))

    def test_beta_release_is_never_marked_latest(self):
        self.release = publication.Release("1.8.6", "1.8.6+1", "beta", "owner/project", self.release.public_keys)
        self.write_artifacts(self.artifacts)
        self.publish()
        self.assertIn("--prerelease", self.writes()[1])
        self.assertIn("--latest=false", self.writes()[-1])

    def test_tag_check_and_source_lookup_do_not_need_keys_or_publish(self):
        self.git("tag", self.release.tag)
        environment = {"VERSION_SHORT": "1.8.6", "FULL_VERSION": "1.8.6+1",
                       "RELEASE_CHANNEL": "stable", "GITHUB_REPOSITORY": "owner/project",
                       "RELEASE_TAG": "v1.8.6", "AUTO_UPDATE_FEED_PUBLIC_KEY": ""}
        with patch.dict(os.environ, environment), patch.object(publication, "PROJECT_ROOT", self.root):
            with patch.object(publication, "publish") as publish:
                self.assertEqual(publication.main(["--check-tag"]), 0)
                self.assertEqual(publication.main(["--source-commit"]), 0)
                publish.assert_not_called()

    def test_invalid_versions_are_rejected_before_commands_run(self):
        for version, full in (("1.2.3; injected", "1.2.3+1"), ("1.8.6", "1.8.7+1"), ("1.8.6", "1.8.6")):
            with self.subTest(version=version, full=full), self.assertRaises(ValueError):
                publication.Release(version, full, "stable", "owner/project", "")


if __name__ == "__main__":
    unittest.main()
