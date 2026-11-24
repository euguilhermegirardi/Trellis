#!/usr/bin/env python3
"""Installs Trellis packs into a project (and optionally the user-level instructions).

  scripts/install.sh [target] [--stack react] [--stack dotnet] [--user] [--dry-run] [--force]

What it does, for the core pack plus each selected stack pack:
  agents/*.md          -> <target>/.claude/agents/
  skills/<name>/       -> <target>/.claude/skills/<name>/
  rules/*.md           -> <target>/.claude/rules/
  hooks/<file>         -> <target>/.claude/hooks/        (Claude Code hooks, executable)
  hooks/git/<file>     -> <target>/.githooks/            (git hooks; sets core.hooksPath locally)
  scripts/<file>       -> <target>/scripts/
  fragments/*.md       -> managed blocks inside <target>/CLAUDE.md (replaced on every run)
  templates/trellis/*  -> <target>/.trellis/             (only when missing; never overwritten)
It also merges the guard hook registration and a deny list into <target>/.claude/settings.json without
duplicating entries or touching other keys.

Updates are safe: a manifest (.trellis/installed.json) remembers the hash of every file it installed. A file you
edited since then is left alone and reported; --force overwrites it. --user adds the pull request rule to
~/.claude/CLAUDE.md as a managed block. --dry-run prints what would happen and writes nothing.
"""
import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ.get("TRELLIS_ROOT") or Path(__file__).resolve().parent.parent)
PACKS = ROOT / "packs"

GUARD_COMMAND = '"${CLAUDE_PROJECT_DIR}"/.claude/hooks/guard-unattended.sh'
DENY = [
    "Read(./.env)",
    "Read(./.env.*)",
    "Bash(git push --force:*)",
    "Bash(git push -f:*)",
    "Bash(git commit --no-verify:*)",
    "Bash(git push origin main:*)",
    "Bash(git push -u origin main:*)",
    "Bash(gh pr merge:*)",
]


class Run:
    def __init__(self, dry):
        self.dry = dry
        self.counts = {}

    def say(self, kind, what):
        self.counts[kind] = self.counts.get(kind, 0) + 1
        print("  %-9s %s" % (kind, what))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load_manifest(target):
    p = target / ".trellis" / "installed.json"
    if p.is_file():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except ValueError:
            sys.exit("error: %s is not valid JSON" % p)
    return {"files": {}}


def save_manifest(target, manifest, run):
    if run.dry:
        return
    p = target / ".trellis" / "installed.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def place(run, manifest, target, rel, data, executable, force):
    dest = target / rel
    new = sha(data)
    old = manifest["files"].get(rel)
    if not dest.exists():
        kind = "added"
    else:
        cur = sha(dest.read_bytes())
        if cur == new:
            manifest["files"][rel] = new
            run.say("unchanged", rel)
            return
        if cur == old or force:
            kind = "updated"
        else:
            run.say("kept", "%s (edited locally; use --force to overwrite)" % rel)
            return
    run.say(kind, rel)
    if not run.dry:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        if executable:
            dest.chmod(dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    manifest["files"][rel] = new


def files_in(d):
    return sorted(p for p in d.rglob("*") if p.is_file()) if d.is_dir() else []


def pack_files(pack):
    """Yields (source Path, destination relative path, executable)."""
    for f in sorted((pack / "agents").glob("*.md")):
        yield f, ".claude/agents/" + f.name, False
    for f in files_in(pack / "skills"):
        yield f, ".claude/skills/" + f.relative_to(pack / "skills").as_posix(), False
    for f in sorted((pack / "rules").glob("*.md")):
        yield f, ".claude/rules/" + f.name, False
    hooks = pack / "hooks"
    if hooks.is_dir():
        for f in sorted(hooks.iterdir()):
            if f.is_file() and f.name != "hooks.json" and f.suffix in (".sh", ".py"):
                yield f, ".claude/hooks/" + f.name, True
        for f in sorted((hooks / "git").glob("*")) if (hooks / "git").is_dir() else []:
            if f.is_file():
                yield f, ".githooks/" + f.name, True
    for f in sorted((pack / "scripts").glob("*")) if (pack / "scripts").is_dir() else []:
        if f.is_file():
            yield f, "scripts/" + f.name, f.suffix in (".sh", ".mjs", ".py")


def shift_headings(text):
    out, fence = [], False
    for line in text.splitlines():
        if line.startswith("```"):
            fence = not fence
        out.append("#" + line if (not fence and re.match(r"#{1,5} ", line)) else line)
    return "\n".join(out)


def upsert_block(path, block_id, body, run, label):
    begin, end = "<!-- trellis:begin %s -->" % block_id, "<!-- trellis:end %s -->" % block_id
    block = "%s\n%s\n%s" % (begin, body.strip(), end)
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.S)
    if pattern.search(text):
        new = pattern.sub(lambda _m: block, text, count=1)
        kind = "unchanged" if new == text else "updated"
    else:
        new = (text.rstrip("\n") + "\n\n" if text.strip() else "") + block + "\n"
        kind = "added"
    run.say(kind, label)
    if kind != "unchanged" and not run.dry:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(new, encoding="utf-8")


def merge_settings(target, run, guard_installed):
    path = target / ".claude" / "settings.json"
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            sys.exit("error: %s is not valid JSON; fix it and run again" % path)
    else:
        data = {}
    before = json.dumps(data, sort_keys=True)
    deny = data.setdefault("permissions", {}).setdefault("deny", [])
    for d in DENY:
        if d not in deny:
            deny.append(d)
    if guard_installed:
        pre = data.setdefault("hooks", {}).setdefault("PreToolUse", [])
        has = any(h.get("command") == GUARD_COMMAND for e in pre for h in e.get("hooks", []))
        if not has:
            pre.append({"matcher": "Bash", "hooks": [{"type": "command", "command": GUARD_COMMAND, "timeout": 10}]})
    changed = json.dumps(data, sort_keys=True) != before
    run.say("updated" if changed and path.exists() else "added" if changed else "unchanged", ".claude/settings.json")
    if changed and not run.dry:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def install_project(target, stacks, run, force):
    manifest = load_manifest(target)
    packs = [PACKS / "core"] + [PACKS / "stacks" / s for s in stacks]
    guard_installed = False
    git_hooks = False
    print("Installing into %s" % target)
    for pack in packs:
        for src, rel, exe in pack_files(pack):
            place(run, manifest, target, rel, src.read_bytes(), exe, force)
            guard_installed = guard_installed or rel == ".claude/hooks/guard-unattended.sh"
            git_hooks = git_hooks or rel.startswith(".githooks/")

    claude_md = target / "CLAUDE.md"
    if not claude_md.exists():
        skeleton = ROOT / "templates" / "CLAUDE.project.md"
        run.say("added", "CLAUDE.md")
        if not run.dry:
            claude_md.write_text(skeleton.read_text(encoding="utf-8") if skeleton.is_file() else "# Project instructions\n", encoding="utf-8")
    for pack in packs:
        for frag in sorted((pack / "fragments").glob("*.md")) if (pack / "fragments").is_dir() else []:
            body = shift_headings(frag.read_text(encoding="utf-8"))
            upsert_block(claude_md, frag.stem, body, run, "CLAUDE.md block %s" % frag.stem)

    templates = ROOT / "templates" / "trellis"
    for t in sorted(templates.glob("*")) if templates.is_dir() else []:
        dest = target / ".trellis" / t.name
        if dest.exists():
            run.say("unchanged", ".trellis/%s (yours; never overwritten)" % t.name)
        else:
            run.say("added", ".trellis/%s" % t.name)
            if not run.dry:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(t.read_bytes())

    merge_settings(target, run, guard_installed)

    if git_hooks:
        if (target / ".git").exists():
            run.say("config", "core.hooksPath=.githooks")
            if not run.dry:
                subprocess.run(["git", "-C", str(target), "config", "core.hooksPath", ".githooks"], check=True)
        else:
            print("  note      %s is not a git repository; set core.hooksPath=.githooks after git init" % target)
    save_manifest(target, manifest, run)


def install_user(run):
    home = Path(os.environ.get("HOME", str(Path.home())))
    rule = PACKS / "core" / "rules" / "pull-requests.md"
    if not rule.is_file():
        sys.exit("error: %s not found" % rule)
    print("Installing user-level instructions into %s" % (home / ".claude" / "CLAUDE.md"))
    body = "## Pull requests (all projects)\n\n" + shift_headings(rule.read_text(encoding="utf-8")).split("\n", 1)[1].strip()
    upsert_block(home / ".claude" / "CLAUDE.md", "pull-requests", body, run, "~/.claude/CLAUDE.md block pull-requests")


def main():
    ap = argparse.ArgumentParser(description="Install Trellis packs into a project.")
    ap.add_argument("target", nargs="?", help="project directory (default: current directory unless only --user)")
    ap.add_argument("--stack", action="append", default=[], help="stack pack to install (repeatable)")
    ap.add_argument("--user", action="store_true", help="also install the user-level pull request rule")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true", help="overwrite files you edited locally")
    args = ap.parse_args()

    available = sorted(p.name for p in (PACKS / "stacks").iterdir() if p.is_dir()) if (PACKS / "stacks").is_dir() else []
    for s in args.stack:
        if s not in available:
            print("error: unknown stack '%s'. Available: %s" % (s, ", ".join(available) or "none"), file=sys.stderr)
            return 2
    run = Run(args.dry_run)
    if args.target or not args.user:
        target = Path(args.target or ".").resolve()
        if not target.is_dir():
            print("error: %s is not a directory" % target, file=sys.stderr)
            return 2
        install_project(target, args.stack, run, args.force)
    if args.user:
        install_user(run)
    print("Done%s: %s" % (" (dry run, nothing written)" if run.dry else "", ", ".join("%d %s" % (v, k) for k, v in sorted(run.counts.items())) or "nothing to do"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
