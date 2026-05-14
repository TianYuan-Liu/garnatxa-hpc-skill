#!/usr/bin/env python3
"""Lint the Garnatxa HPC skill.

Checks:
  1. SKILL.md has valid YAML frontmatter with `name` and `description`.
  2. `name` matches the skill directory name.
  3. Every relative markdown link `[...](path)` resolves to a real file.
  4. Every `assets/<file>` and `references/<file>` mentioned in any
     markdown is a real file in the skill.

Exits non-zero if anything fails; prints a tight, file:line-style report.
Run locally via:

    python3 scripts/lint_skill.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SKILL_DIR = REPO_ROOT / "skill" / "garnatxa-hpc"
EXPECTED_NAME = "garnatxa-hpc"

LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
ASSET_MENTION_RE = re.compile(r"assets/([\w.\-]+)")
REFERENCE_MENTION_RE = re.compile(r"references/([\w.\-]+\.md)")

errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def check_frontmatter() -> None:
    skill_md = SKILL_DIR / "SKILL.md"
    if not skill_md.exists():
        err(f"{skill_md.relative_to(REPO_ROOT)}: missing")
        return

    text = skill_md.read_text()
    if not text.startswith("---\n"):
        err("SKILL.md: does not start with YAML frontmatter (`---`)")
        return

    end = text.find("\n---\n", 4)
    if end < 0:
        err("SKILL.md: frontmatter not terminated by a second `---`")
        return

    front = text[4:end]

    m = re.search(r"^name:\s*(.+)$", front, re.M)
    if not m:
        err("SKILL.md frontmatter: missing `name` field")
    elif m.group(1).strip() != EXPECTED_NAME:
        err(f"SKILL.md frontmatter: name='{m.group(1).strip()}' "
            f"but skill directory is '{EXPECTED_NAME}'")

    m = re.search(r"^description:\s*(.+?)(?=^\w+:|\Z)", front, re.M | re.S)
    if not m:
        err("SKILL.md frontmatter: missing `description` field")
    else:
        desc = m.group(1).strip()
        if len(desc) < 50:
            err(f"SKILL.md frontmatter: description is short ({len(desc)} chars); "
                f"aim for ≥ 100 chars and include explicit triggers")
        if len(desc) > 3000:
            err(f"SKILL.md frontmatter: description is very long ({len(desc)} chars); "
                f"the description ships in every Claude session — keep it tight")


def check_internal_links() -> None:
    for md in sorted(SKILL_DIR.rglob("*.md")):
        rel = md.relative_to(REPO_ROOT)
        for n, line in enumerate(md.read_text().splitlines(), start=1):
            for m in LINK_RE.finditer(line):
                target = m.group(2).split("#", 1)[0].strip()
                if not target or target.startswith(
                    ("http://", "https://", "mailto:", "tel:", "data:")
                ):
                    continue
                resolved = (md.parent / target).resolve()
                if not resolved.exists():
                    err(f"{rel}:{n}: broken link → {target}")


def check_mentioned_files_exist() -> None:
    """Anywhere we mention `assets/X` or `references/Y.md`, the file must exist."""
    asset_dir = SKILL_DIR / "assets"
    ref_dir = SKILL_DIR / "references"

    for md in sorted(SKILL_DIR.rglob("*.md")):
        rel = md.relative_to(REPO_ROOT)
        text = md.read_text()

        for m in ASSET_MENTION_RE.finditer(text):
            asset = m.group(1)
            # ignore placeholders inside braces like assets/<asset>
            if asset.startswith(("<", "{")):
                continue
            if not (asset_dir / asset).exists():
                err(f"{rel}: mentions assets/{asset} which does not exist")

        for m in REFERENCE_MENTION_RE.finditer(text):
            ref = m.group(1)
            if not (ref_dir / ref).exists():
                err(f"{rel}: mentions references/{ref} which does not exist")


def check_shell_shebangs() -> None:
    for sh in sorted((SKILL_DIR / "assets").glob("*.sh")):
        first = sh.read_text().splitlines()[:1]
        if not first or not first[0].startswith("#!"):
            err(f"{sh.relative_to(REPO_ROOT)}: missing shebang line")


def main() -> int:
    if not SKILL_DIR.exists():
        err(f"skill directory not found: {SKILL_DIR.relative_to(REPO_ROOT)}")
    else:
        check_frontmatter()
        check_internal_links()
        check_mentioned_files_exist()
        check_shell_shebangs()

    if errors:
        print("✗ skill lint failed")
        for e in errors:
            print(f"  • {e}")
        return 1

    print("✓ skill lint clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
