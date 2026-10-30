"""Verify release artifacts and resume publication without replacing public assets."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from tool.updater.verify_release import verify_release

PROJECT_ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Release:
    version: str
    full_version: str
    channel: str
    repository: str
    public_keys: str

    def __post_init__(self) -> None:
        if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", self.version):
            raise ValueError("VERSION_SHORT must contain three numeric components")
        if not re.fullmatch(re.escape(self.version) + r"\+[0-9]+", self.full_version):
            raise ValueError("FULL_VERSION must match VERSION_SHORT and include a build number")
        if self.channel not in {"stable", "beta"}:
            raise ValueError("RELEASE_CHANNEL must be stable or beta")
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", self.repository):
            raise ValueError("GITHUB_REPOSITORY must identify the release repository")

    @property
    def tag(self) -> str:
        return f"v{self.version}"

    @property
    def asset_names(self) -> tuple[str, str]:
        return (f"PlugAgente-Setup-{self.version}.exe", f"PlugAgente-Manifest-{self.version}.json")


def command(arguments: list[str], root: Path, *, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(arguments, cwd=root, capture_output=True, text=True, encoding="utf-8")
    if check and result.returncode:
        raise RuntimeError(f"{' '.join(arguments[:3])} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result


def tagged_source(release: Release, root: Path) -> str | None:
    ref = f"refs/tags/{release.tag}"
    exists = command(["git", "show-ref", "--verify", "--quiet", ref], root, check=False)
    if exists.returncode == 1:
        return None
    if exists.returncode:
        raise RuntimeError(f"Unable to inspect release tag: {exists.stderr.strip()}")
    commit = command(["git", "rev-parse", f"{ref}^{{commit}}"], root).stdout.strip()
    # The feed is updated after publication and is not part of the installer source.
    difference = command(["git", "diff", "--quiet", commit, "--", ".", ":(exclude)appcast.xml"], root, check=False)
    if difference.returncode == 1:
        raise ValueError(f"Tag {release.tag} belongs to different source; use a new release version")
    if difference.returncode:
        raise RuntimeError(f"Unable to compare release source: {difference.stderr.strip()}")
    return commit


def source_commit(release: Release, root: Path) -> str:
    return tagged_source(release, root) or command(["git", "rev-parse", "HEAD"], root).stdout.strip()


def release_metadata(release: Release, root: Path) -> dict | None:
    owner, repository = release.repository.split("/", 1)
    query = """query($owner: String!, $repository: String!, $tag: String!) {
      repository(owner: $owner, name: $repository) {
        release(tagName: $tag) { tagName isDraft isPrerelease }
      }
    }"""
    result = command(["gh", "api", "graphql", "-f", f"query={query}",
                      "-f", f"owner={owner}", "-f", f"repository={repository}",
                      "-f", f"tag={release.tag}"], root, check=False)
    if result.returncode:
        raise RuntimeError(f"Unable to inspect GitHub release: {result.stderr.strip()}")
    response = json.loads(result.stdout)
    if response.get("errors"):
        raise RuntimeError(f"Unable to inspect GitHub release: {response['errors']}")
    repository_data = response.get("data", {}).get("repository")
    if repository_data is None:
        raise RuntimeError("Release repository is unavailable; check GITHUB_REPOSITORY and token permissions")
    entry = repository_data["release"]
    if entry is None:
        return None
    data = {"tag_name": entry["tagName"], "draft": entry["isDraft"], "prerelease": entry["isPrerelease"]}
    if data.get("tag_name") != release.tag or data.get("prerelease") != (release.channel == "beta"):
        raise ValueError("Existing release tag or prerelease status does not match requested release")
    return data


def verify_assets(release: Release, directory: Path, commit: str) -> dict[str, str]:
    if not release.public_keys.strip():
        raise ValueError("AUTO_UPDATE_FEED_PUBLIC_KEY is required to publish")
    installer, manifest = (directory / name for name in release.asset_names)
    payload = verify_release(manifest, installer, release.public_keys, release.full_version, release.channel, commit)
    with manifest.open("rb") as source:
        manifest_digest = hashlib.file_digest(source, "sha256").hexdigest()
    return {installer.name: payload["installer"]["sha256"], manifest.name: manifest_digest}


def verify_uploaded_assets(release: Release, root: Path, commit: str,
                           expected_digests: dict[str, str] | None = None) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        destination = Path(temporary)
        command(["gh", "release", "download", release.tag, "--repo", release.repository,
                 "--dir", str(destination), "--pattern", release.asset_names[0],
                 "--pattern", release.asset_names[1]], root)
        uploaded_digests = verify_assets(release, destination, commit)
        if expected_digests is not None:
            for name in release.asset_names:
                if expected_digests[name] != uploaded_digests[name]:
                    raise ValueError(f"Uploaded asset differs from verified local artifact: {name}")


def publish(release: Release, root: Path = PROJECT_ROOT) -> None:
    from tool.release.check_changelog import check
    check(root, release.full_version, release=True)
    existing_source = tagged_source(release, root)
    commit = existing_source or command(["git", "rev-parse", "HEAD"], root).stdout.strip()
    artifacts = root / "installer/dist"
    local_digests = verify_assets(release, artifacts, commit)
    metadata = release_metadata(release, root)
    if metadata is not None and not metadata["draft"]:
        if existing_source is None:
            raise ValueError("Published release has no checked-out tag; fetch tags before retrying")
        verify_uploaded_assets(release, root, commit)
        print(f"Release {release.tag} is already published and verified; keeping its assets")
        return

    if existing_source is None:
        dirty = command(["git", "status", "--porcelain", "--untracked-files=no"], root).stdout.strip()
        if dirty:
            raise ValueError("Commit tracked source changes before publishing a new release")
        command(["git", "tag", release.tag, commit], root)
        command(["git", "push", "--atomic", "origin", "HEAD:refs/heads/main", f"refs/tags/{release.tag}"], root)

    if metadata is None:
        arguments = ["gh", "release", "create", release.tag, "--repo", release.repository,
                     "--draft", "--verify-tag", "--generate-notes", "--title", f"Version {release.version}"]
        if release.channel == "beta":
            arguments.append("--prerelease")
        command(arguments, root)
    command(["gh", "release", "upload", release.tag, "--repo", release.repository,
             *(str(artifacts / name) for name in release.asset_names), "--clobber"], root)
    verify_uploaded_assets(release, root, commit, local_digests)
    command(["gh", "release", "edit", release.tag, "--repo", release.repository,
             "--draft=false", "--latest" if release.channel == "stable" else "--latest=false"], root)
    print(f"Published and verified release {release.tag}")


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check-tag", action="store_true")
    mode.add_argument("--source-commit", action="store_true")
    args = parser.parse_args(arguments)
    try:
        release = Release(os.environ.get("VERSION_SHORT", ""), os.environ.get("FULL_VERSION", ""),
                          os.environ.get("RELEASE_CHANNEL", ""), os.environ.get("GITHUB_REPOSITORY", ""),
                          os.environ.get("AUTO_UPDATE_FEED_PUBLIC_KEY", ""))
        if os.environ.get("RELEASE_TAG", release.tag) != release.tag:
            raise ValueError("RELEASE_TAG does not match VERSION_SHORT")
        if args.check_tag:
            tagged_source(release, PROJECT_ROOT)
            print(f"Release tag {release.tag} source is compatible")
        elif args.source_commit:
            print(source_commit(release, PROJECT_ROOT))
        else:
            publish(release)
        return 0
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Release publication failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
