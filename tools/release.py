#!/usr/bin/env python3
"""
Build, and optionally publish, a LiteRotation release.

    python3 tools/release.py                      # build .release/LiteRotation-v<version>.zip only
    python3 tools/release.py --publish            # also publish it on the public LiteRotation repository
    python3 tools/release.py --publish --prerelease

The addon is developed in a folder of the private wowUtilities repository but released from the public
Glawster/LiteRotation repository. Publishing:

1. syncs this folder's committed files onto the public repository's main as one ordinary commit (a fast-forward,
   history is never rewritten), leaving out the wowUtilities flag files;
2. tags that commit v<version> on the public repository and creates its GitHub release with the zip attached;
3. tags wowUtilities LiteRotation-v<version>, so you can see which monorepo commit was released.

The version is the .toc's "## Version". The zip holds the committed files (git ls-files) inside a folder named
after the addon, minus dotfiles and everything .pkgmeta's `ignore` lists, so players extract it straight into
Interface/AddOns. The release notes are CHANGELOG.md's section for the version plus install steps.

Before publishing, the script checks that this folder has no uncommitted changes, that wowUtilities is on main and
level with origin, that CHANGELOG.md has a section for the version, and that neither tag exists yet. Publishing
needs the GitHub CLI (`gh`) logged in and SSH access to the public repository; its clone is kept in .release/public.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / ".release"
BRANCH = "main"
PUBLIC_REPO = "Glawster/LiteRotation"
PUBLIC_URL = os.environ.get("LITEROTATION_PUBLIC_URL", f"git@github.com:{PUBLIC_REPO}.git")
PUBLIC_DIR = OUT_DIR / "public"
FLAG_FILES = {"_forever_", "_retail_"}  # wowUtilities deploy flags; meaningless in the standalone repository

INSTALL_NOTES = """## Install

1. Download **{zip}** below.
2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/` (you should get `AddOns/{name}/{name}.toc`).
3. Restart the game and make sure {name} is enabled in the AddOns list.

Type `/lrot` in game for the commands. See the [README]({url}#readme) for how it works and its limits, and
[open an issue]({url}/issues) if something looks wrong.
"""


def run(*args: str, capture: bool = True, cwd: Path = ROOT) -> str:
    """Run a command (in the addon folder unless cwd says otherwise); stop the script if it fails."""
    result = subprocess.run(args, cwd=cwd, capture_output=capture, text=True)
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


def checkPublishable(version: str, tag: str, publicTag: str) -> None:
    """Stop unless wowUtilities and the public repository are in a state to tag and release."""
    if run("git", "status", "--porcelain", "--", "."):
        sys.exit(f"error: {ROOT.name} has uncommitted changes; commit them first")
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
    if run("git", "ls-remote", "--tags", PUBLIC_URL, publicTag):
        sys.exit(f"error: tag {publicTag} already exists on {PUBLIC_REPO}")


def syncPublic(name: str, version: str) -> bool:
    """Make the public repository's main hold this folder's committed files; push it. Returns True if it changed."""
    if (PUBLIC_DIR / ".git").is_dir():
        run("git", "fetch", "-q", "origin", BRANCH, cwd=PUBLIC_DIR)
        run("git", "checkout", "-q", BRANCH, cwd=PUBLIC_DIR)
        run("git", "reset", "-q", "--hard", f"origin/{BRANCH}", cwd=PUBLIC_DIR)
        run("git", "clean", "-qfdx", cwd=PUBLIC_DIR)
    else:
        if PUBLIC_DIR.exists():
            shutil.rmtree(PUBLIC_DIR)
        OUT_DIR.mkdir(exist_ok=True)
        run("git", "clone", "-q", "--branch", BRANCH, PUBLIC_URL, str(PUBLIC_DIR), cwd=OUT_DIR)

    wanted = [f for f in run("git", "ls-files").splitlines() if f not in FLAG_FILES]
    for old in run("git", "ls-files", cwd=PUBLIC_DIR).splitlines():
        (PUBLIC_DIR / old).unlink(missing_ok=True)
    for file in wanted:
        out = PUBLIC_DIR / file
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / file, out)
    run("git", "add", "-A", ".", cwd=PUBLIC_DIR)
    if not run("git", "status", "--porcelain", cwd=PUBLIC_DIR):
        return False
    source = run("git", "rev-parse", "--short", "HEAD")
    run("git", "commit", "-q", "-m", f"{name} {version}\n\nSynced from wowUtilities {source}.", cwd=PUBLIC_DIR)
    run("git", "push", "-q", "origin", BRANCH, cwd=PUBLIC_DIR)
    return True


def publish(name: str, version: str, zipPath: Path, prerelease: bool) -> None:
    """Sync and tag the public repository, create its GitHub release, and tag wowUtilities."""
    tag, publicTag = f"{name}-v{version}", f"v{version}"
    url = f"https://github.com/{PUBLIC_REPO}"
    notes = changelogSection(version) + "\n\n" + INSTALL_NOTES.format(zip=zipPath.name, name=name, url=url)
    notesPath = OUT_DIR / f"{name}-v{version}-notes.md"
    notesPath.write_text(notes, encoding="utf-8")

    changed = syncPublic(name, version)
    print(f"{PUBLIC_REPO} main: {'synced and pushed' if changed else 'already up to date'}")
    run("git", "tag", "-a", publicTag, "-m", f"{name} {version}", cwd=PUBLIC_DIR)
    run("git", "push", "-q", "origin", publicTag, cwd=PUBLIC_DIR)
    run("git", "tag", "-a", tag, "-m", f"{name} {version} (released as {PUBLIC_REPO} {publicTag})")
    run("git", "push", "-q", "origin", tag)
    command = [
        "gh",
        "release",
        "create",
        publicTag,
        str(zipPath),
        "--repo",
        PUBLIC_REPO,
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
    parser.add_argument("--publish", action="store_true", help=f"sync, tag and release on {PUBLIC_REPO}")
    parser.add_argument("--prerelease", action="store_true", help="mark the GitHub release as a pre-release")
    args = parser.parse_args()

    name, ignore = packageInfo()
    version = tocVersion(name)
    if args.publish:
        checkPublishable(version, f"{name}-v{version}", f"v{version}")

    files = releaseFiles(ignore)
    zipPath = buildZip(name, version, files)
    print(f"built {zipPath.relative_to(ROOT)} ({len(files)} files)")
    for file in files:
        print(f"  {name}/{file}")

    if args.publish:
        publish(name, version, zipPath, args.prerelease)
    else:
        print(f"not published: add --publish to release it on {PUBLIC_REPO}")


if __name__ == "__main__":
    main()
