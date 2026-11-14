#!/usr/bin/env python3
"""
Build, and optionally publish, a LiteRotation release.

    python3 tools/release.py                      # build .release/LiteRotation-v<version>.zip only
    python3 tools/release.py --publish            # also tag v<version>, push the tag, create the GitHub release
    python3 tools/release.py --publish --prerelease

The version is the .toc's "## Version". The zip holds the committed files (git ls-files) inside a folder named after
the addon, minus dotfiles and everything .pkgmeta's `ignore` lists, so players extract it straight into
Interface/AddOns. The release notes are CHANGELOG.md's section for the version plus install steps.

Before publishing, the script checks that the working tree is clean, that you are on main and level with origin,
that CHANGELOG.md has a section for the version, and that the tag does not exist yet. Publishing needs the GitHub
CLI (`gh`) logged in.
"""

import argparse
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / ".release"
BRANCH = "main"

INSTALL_NOTES = """## Install

1. Download **{zip}** below.
2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/` (you should get `AddOns/{name}/{name}.toc`).
3. Restart the game and make sure {name} is enabled in the AddOns list.

Type `/lrot` in game for the commands. See the [README]({url}#readme) for how it works and its limits, and
[open an issue]({url}/issues) if something looks wrong.
"""


def run(*args: str, capture: bool = True) -> str:
    """Run a command in the repository root; stop the script if it fails."""
    result = subprocess.run(args, cwd=ROOT, capture_output=capture, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip() if capture else ""
        sys.exit(f"error: {' '.join(args)} failed{': ' + detail if detail else ''}")
    return result.stdout.strip() if capture else ""


def packageInfo() -> tuple[str, list[str]]:
    """Return the package name and ignore list from .pkgmeta."""
    meta = (ROOT / ".pkgmeta").read_text(encoding="utf-8")
    name = re.search(r"^package-as:\s*(\S+)", meta, re.M).group(1)
    ignore = re.findall(r"^\s+-\s+(\S+)\s*$", meta.split("ignore:", 1)[1], re.M) if "ignore:" in meta else []
    return name, ignore


def tocVersion(name: str) -> str:
    """Return the .toc's ## Version."""
    toc = (ROOT / f"{name}.toc").read_text(encoding="utf-8-sig")
    match = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    if not match:
        sys.exit(f"error: {name}.toc has no ## Version")
    return match.group(1)


def changelogSection(version: str) -> str:
    """Return CHANGELOG.md's section for version (without its heading), or "" when there is none."""
    path = ROOT / "CHANGELOG.md"
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8")
    match = re.search(rf"^## v?{re.escape(version)}\b[^\n]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    return match.group(1).strip() if match else ""


def releaseFiles(ignore: list[str]) -> list[str]:
    """Committed files that belong in the package."""
    files = run("git", "ls-files").splitlines()
    kept = []
    for path in files:
        first = path.split("/")[0]
        if first.startswith(".") or first in ignore or path in ignore:
            continue
        kept.append(path)
    return kept


def buildZip(name: str, version: str, files: list[str]) -> Path:
    """Write .release/<name>-v<version>.zip with every file under <name>/."""
    OUT_DIR.mkdir(exist_ok=True)
    path = OUT_DIR / f"{name}-v{version}.zip"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for file in files:
            archive.write(ROOT / file, f"{name}/{file}")
    return path


def checkPublishable(version: str, tag: str) -> None:
    """Stop unless the repository is in a state to tag and release."""
    if run("git", "status", "--porcelain"):
        sys.exit("error: the working tree has uncommitted changes; commit them first")
    branch = run("git", "rev-parse", "--abbrev-ref", "HEAD")
    if branch != BRANCH:
        sys.exit(f"error: on branch {branch}; releases are made from {BRANCH}")
    run("git", "fetch", "-q", "origin", BRANCH)
    if run("git", "rev-parse", "HEAD") != run("git", "rev-parse", f"origin/{BRANCH}"):
        sys.exit(f"error: {BRANCH} is not level with origin/{BRANCH}; push or pull first")
    if not changelogSection(version):
        sys.exit(f"error: CHANGELOG.md has no '## {version}' section")
    if run("git", "tag", "-l", tag):
        sys.exit(f"error: tag {tag} already exists; bump ## Version in the .toc")
    if run("git", "ls-remote", "--tags", "origin", tag):
        sys.exit(f"error: tag {tag} already exists on origin")


def repoUrl() -> str:
    """The GitHub URL of origin, e.g. https://github.com/Glawster/LiteRotation."""
    remote = run("git", "remote", "get-url", "origin")
    match = re.search(r"github\.com[:/](.+?)(?:\.git)?$", remote)
    if not match:
        sys.exit(f"error: origin is not a GitHub remote: {remote}")
    return f"https://github.com/{match.group(1)}"


def publish(name: str, version: str, zipPath: Path, prerelease: bool) -> None:
    """Tag, push the tag and create the GitHub release with the zip attached."""
    tag = f"v{version}"
    url = repoUrl()
    notes = changelogSection(version) + "\n\n" + INSTALL_NOTES.format(zip=zipPath.name, name=name, url=url)
    notesPath = OUT_DIR / f"{name}-v{version}-notes.md"
    notesPath.write_text(notes, encoding="utf-8")

    run("git", "tag", "-a", tag, "-m", f"{name} {version}")
    run("git", "push", "-q", "origin", tag)
    command = [
        "gh",
        "release",
        "create",
        tag,
        str(zipPath),
        "--title",
        f"{name} {version}",
        "--notes-file",
        str(notesPath),
    ]
    if prerelease:
        command.append("--prerelease")
    print(run(*command))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--publish", action="store_true", help="tag, push the tag and create the GitHub release")
    parser.add_argument("--prerelease", action="store_true", help="mark the GitHub release as a pre-release")
    args = parser.parse_args()

    name, ignore = packageInfo()
    version = tocVersion(name)
    tag = f"v{version}"
    if args.publish:
        checkPublishable(version, tag)

    files = releaseFiles(ignore)
    zipPath = buildZip(name, version, files)
    print(f"built {zipPath.relative_to(ROOT)} ({len(files)} files)")
    for file in files:
        print(f"  {name}/{file}")

    if args.publish:
        publish(name, version, zipPath, args.prerelease)
    else:
        print("not published: add --publish to tag and create the GitHub release")


if __name__ == "__main__":
    main()
