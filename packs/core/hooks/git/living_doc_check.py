#!/usr/bin/env python3
"""Living-document commit gate.

Reads .trellis/living-doc.json from the repository root:
  plan          path of the living plan document, required
  triggers      globs; a staged change to any of them requires the plan in the same commit
  excludes      globs that never trigger (tests, for example)
  skipBranches  branch globs that are exempt (for example "wip/*")
  logCommand    command shown in the help text (default: node scripts/living-doc-log.mjs --write)
There is deliberately no environment variable that disables the gate; a human can use `git commit --no-verify`.
"""
import fnmatch
import json
import os
import re
import subprocess
import sys


def git(*args):
    res = subprocess.run(["git", *args], capture_output=True, text=True)
    return res.stdout.strip() if res.returncode == 0 else ""


def glob_to_regex(glob):
    out, i = "", 0
    while i < len(glob):
        c = glob[i]
        if glob[i : i + 3] == "**/":
            out += "(?:.*/)?"
            i += 3
            continue
        if glob[i : i + 2] == "**":
            out += ".*"
            i += 2
            continue
        out += "[^/]*" if c == "*" else "[^/]" if c == "?" else re.escape(c)
        i += 1
    return re.compile("^" + out + "$")


def matches(path, globs):
    return any(glob_to_regex(g).match(path) for g in globs)


def main():
    root = git("rev-parse", "--show-toplevel")
    if not root:
        return 0
    cfg_path = os.path.join(root, ".trellis", "living-doc.json")
    if not os.path.isfile(cfg_path):
        return 0
    with open(cfg_path, encoding="utf-8") as fh:
        cfg = json.load(fh)
    plan = cfg.get("plan")
    if not plan:
        print("living-doc: .trellis/living-doc.json needs a \"plan\" path", file=sys.stderr)
        return 1

    git_dir = git("rev-parse", "--git-dir")
    if os.path.exists(os.path.join(root, git_dir, "MERGE_HEAD")) or os.path.exists(os.path.join(git_dir, "MERGE_HEAD")):
        return 0
    branch = git("symbolic-ref", "--short", "-q", "HEAD") or git("rev-parse", "--abbrev-ref", "HEAD")
    if any(fnmatch.fnmatch(branch, g) for g in cfg.get("skipBranches", [])):
        return 0

    staged = [f for f in git("diff", "--cached", "--name-only", "--diff-filter=ACMRD").splitlines() if f]
    triggers, excludes = cfg.get("triggers", []), cfg.get("excludes", [])
    hit = [f for f in staged if matches(f, triggers) and not matches(f, excludes)]
    if not hit or plan in staged:
        return 0

    log_cmd = cfg.get("logCommand", "node scripts/living-doc-log.mjs --write")
    print("Commit blocked: product state changed but %s is not in this commit." % plan, file=sys.stderr)
    print("\nFiles that triggered the gate:", file=sys.stderr)
    for f in hit:
        print("  - " + f, file=sys.stderr)
    print("\nWhat to do (agents: do it yourself, without waiting for the human):", file=sys.stderr)
    print("  1. Update status, gaps and decisions in %s." % plan, file=sys.stderr)
    print("  2. Generate the log line:  %s" % log_cmd, file=sys.stderr)
    print("  3. git add %s and commit again." % plan, file=sys.stderr)
    print("\nNot applicable (a pure refactor, say)? Only the human decides: use a skipBranches branch "
          "or `git commit --no-verify`.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
