#!/usr/bin/env python3
"""Decides whether a shell command may run in an unattended session.

Input: the PreToolUse JSON on stdin ({"tool_input": {"command": "..."}}).
Output: exit 0 to allow, exit 2 (reason on stderr) to block.

The command is parsed into simple commands (splitting on ; & | newline, descending into $(...),
backticks, `bash -c` and `eval`) and judged on argv tokens, not on raw text, so a commit message
that mentions "git push" or "--no-verify" does not trip the guard.

This is a second lock, not a sandbox: it cannot see inside scripts or interpreters.
Configuration (all optional):
  TRELLIS_PROTECTED_BRANCHES   space separated, default "main master"
  <project>/.trellis/protected-branches.txt   one branch per line
  <project>/.trellis/forbidden-files.txt      path globs a command may not name
  TRELLIS_FORBIDDEN_ENV        extra environment variable names that may not be set inline
"""
import fnmatch
import json
import os
import shlex
import subprocess
import sys

PROJECT = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


class Block(Exception):
    pass


def block(reason):
    raise Block(reason)


# ---------------------------------------------------------------- configuration
def read_list(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return [ln.strip() for ln in fh if ln.strip() and not ln.strip().startswith("#")]
    except OSError:
        return []


def protected_branches():
    names = os.environ.get("TRELLIS_PROTECTED_BRANCHES", "main master").split()
    names += read_list(os.path.join(PROJECT, ".trellis", "protected-branches.txt"))
    return set(names)


SECRET_FILE_GLOBS = [".env", ".env.*", "*.pem", "*.key", "*.p12", "*.pfx", "*id_rsa*", "*id_ed25519*"]
SECRET_FILE_ALLOW = [".env.example*", ".env.sample*", ".env.template*", "*.example", "*.sample"]


def secret_globs():
    return SECRET_FILE_GLOBS + read_list(os.path.join(PROJECT, ".trellis", "forbidden-files.txt"))


# ---------------------------------------------------------------- shell splitting
def find_close(s, i):
    """Index of the ')' that closes the '(' at s[i-1], quote aware; len(s) if unbalanced."""
    depth, quote = 1, None
    while i < len(s):
        c = s[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 1
            elif c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "\\":
            i += 1
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(s)


def split_commands(s):
    """Returns (simple, nested): simple = [(separator_before, text)], nested = [command strings]."""
    simple, nested = [], []
    cur, sep, quote, i = [], ";", None, 0

    def flush(next_sep):
        nonlocal cur, sep
        text = "".join(cur).strip()
        if text:
            simple.append((sep, text))
        cur, sep = [], next_sep

    while i < len(s):
        c = s[i]
        if quote == "'":
            cur.append(c)
            if c == "'":
                quote = None
        elif c == "\\" and i + 1 < len(s):
            cur.append(c + s[i + 1])
            i += 1
        elif c == "`":
            j = s.find("`", i + 1)
            j = len(s) if j < 0 else j
            nested.append(s[i + 1 : j])
            cur.append("X")
            i = j
        elif c == "$" and s[i + 1 : i + 2] == "(":
            j = find_close(s, i + 2)
            nested.append(s[i + 2 : j])
            cur.append("X")
            i = j
        elif quote == '"':
            cur.append(c)
            if c == '"':
                quote = None
        elif c in "'\"":
            quote = c
            cur.append(c)
        elif c in "<>" and s[i + 1 : i + 2] == "(":
            j = find_close(s, i + 2)
            nested.append(s[i + 2 : j])
            cur.append("X")
            i = j
        elif c == "|":
            if s[i + 1 : i + 2] == "|":
                i += 1
                flush(";")
            elif s[i + 1 : i + 2] == "&":
                i += 1
                flush("|")
            else:
                flush("|")
        elif c in ";\n&(){}":
            if c == "&" and s[i + 1 : i + 2] == ">":
                cur.append(c)
            else:
                if c == "&" and s[i + 1 : i + 2] == "&":
                    i += 1
                flush(";")
        else:
            cur.append(c)
        i += 1
    flush(";")
    return simple, nested


def argv_of(text):
    try:
        return shlex.split(text, comments=False, posix=True)
    except ValueError:
        return text.split()


# ---------------------------------------------------------------- rules
WRAPPERS = {"command", "builtin", "exec", "nohup", "time", "nice", "ionice", "env", "xargs", "timeout", "stdbuf"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
GH_READ_ONLY = {
    ("pr", "view"), ("pr", "list"), ("pr", "diff"), ("pr", "status"), ("pr", "checks"),
    ("issue", "view"), ("issue", "list"), ("issue", "status"),
    ("run", "view"), ("run", "list"), ("repo", "view"), ("--version",), ("--help",),
}
OPTS_WITH_VALUE = {
    "git": {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"},
    "commit": {"-m", "-F", "-C", "-c", "--message", "--file", "--reuse-message", "--reedit-message",
               "--author", "--date", "-t", "--template", "--cleanup"},
}


def forbidden_env_names():
    extra = os.environ.get("TRELLIS_FORBIDDEN_ENV", "").split()
    return set(extra)


def is_env_assignment(tok):
    if "=" not in tok or tok.startswith("="):
        return False
    name = tok.split("=", 1)[0]
    return name.replace("_", "a").isalnum() and not name[0].isdigit()


def check_env(name):
    if name.startswith("SKIP_") or name in ("HUSKY", "NO_VERIFY") or name in forbidden_env_names():
        block("setting %s skips a safety check" % name)
    if name in ("GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_DIR", "GIT_WORK_TREE"):
        block("setting %s can redirect git or its hooks" % name)


def current_branch(path):
    try:
        out = subprocess.run(["git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD"],
                             capture_output=True, text=True, timeout=5)
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def short_cluster_has(tok, letter, stop="mFCct"):
    """True if the short-option cluster tok (like -an) contains `letter` before an option that takes a value."""
    if not tok.startswith("-") or tok.startswith("--") or len(tok) < 2:
        return False
    for ch in tok[1:]:
        if ch == letter:
            return True
        if ch in stop:
            return False
    return False


def check_git(args, depth):
    path = PROJECT
    i, config_overrides = 0, []
    while i < len(args):
        a = args[i]
        if a == "-C" and i + 1 < len(args):
            path = args[i + 1] if os.path.isabs(args[i + 1]) else os.path.join(path, args[i + 1])
            i += 2
        elif a == "-c" and i + 1 < len(args):
            config_overrides.append(args[i + 1])
            i += 2
        elif a.startswith("--git-dir") or a.startswith("--work-tree"):
            block("redirecting git with %s" % a.split("=")[0])
        elif a.startswith("-"):
            i += 1 if "=" in a or a in ("-p", "--paginate", "--no-pager", "--bare", "--no-replace-objects") else 1
        else:
            break
    for ov in config_overrides:
        key = ov.split("=", 1)[0].lower()
        if key in ("core.hookspath", "core.fsmonitor", "core.sshcommand") or key.startswith("alias."):
            block("git -c %s changes hooks or commands" % key)
    if i >= len(args):
        return
    sub, rest = args[i], args[i + 1 :]

    def flags_outside_values(opts_key):
        skip = False
        for t in rest:
            if skip:
                skip = False
                continue
            if t in OPTS_WITH_VALUE.get(opts_key, set()):
                skip = True
                continue
            yield t

    if "--no-verify" in list(flags_outside_values("commit")) and sub in ("commit", "merge", "push", "am", "rebase", "cherry-pick", "revert"):
        block("--no-verify skips the hooks")
    if sub == "push":
        block("git push (the launcher pushes after the agent finishes)")
    if sub == "commit" and any(short_cluster_has(t, "n") for t in flags_outside_values("commit")):
        block("git commit -n skips the hooks")
    if sub in ("commit", "merge", "rebase", "cherry-pick", "revert", "am", "pull"):
        branch = current_branch(path)
        if branch and branch in protected_branches():
            block("%s on protected branch '%s' (work on a feature branch)" % (sub, branch))
    if sub in ("checkout", "switch"):
        creating = any(t in ("-b", "-B", "-c", "-C", "--orphan") or t.startswith("--create") for t in rest)
        names = [t for t in rest if not t.startswith("-")]
        if not creating and any(n in protected_branches() for n in names):
            block("switching to a protected branch")
    if sub == "reset" and "--hard" in rest:
        block("git reset --hard")
    if sub == "clean" and any(t == "--force" or short_cluster_has(t, "f") for t in rest):
        block("git clean with force deletes untracked work")
    if sub == "branch" and ("-D" in rest or ("--force" in rest and ("-d" in rest or "--delete" in rest))):
        block("deleting a branch with force")
    if sub in ("filter-branch", "filter-repo", "update-ref", "gc", "prune"):
        block("git %s rewrites or removes history" % sub)
    if sub == "reflog" and rest[:1] == ["expire"]:
        block("git reflog expire")
    if sub == "config":
        keys = [t.lower() for t in rest if not t.startswith("-")]
        if any(k in ("core.hookspath",) or k.startswith("alias.") for k in keys[:1]):
            block("changing git hook configuration")
    if sub == "checkout" or sub == "restore":
        pass


def check_gh(args):
    positional = [t for t in args if not t.startswith("-")]
    key = tuple(positional[:2])
    if key in GH_READ_ONLY or tuple(positional[:1]) in GH_READ_ONLY or (not positional and set(args) <= {"--version", "--help", "-h"}):
        return
    block("gh %s (the launcher opens the pull request; gh is read-only here)" % " ".join(positional[:2]))


def touches_secret_file(tok):
    if tok.startswith("-") and "=" in tok:
        tok = tok.split("=", 1)[1]
    base = os.path.basename(tok.rstrip("/"))
    if not base:
        return False
    if any(fnmatch.fnmatch(base, g) for g in SECRET_FILE_ALLOW):
        return False
    return any(fnmatch.fnmatch(base, g) or fnmatch.fnmatch(tok, g) for g in secret_globs())


def check_rm(args):
    recursive = any(t in ("-r", "-R", "--recursive") or (t.startswith("-") and not t.startswith("--") and ("r" in t or "R" in t)) for t in args)
    if not recursive:
        return
    for t in [a for a in args if not a.startswith("-")]:
        outside = (
            t.startswith("~") or t.startswith("$") or ".." in t.split("/")
            or (os.path.isabs(t) and not os.path.abspath(t).startswith(os.path.abspath(PROJECT) + os.sep)
                and os.path.abspath(t) != os.path.abspath(PROJECT))
        )
        if outside or t in ("/", "*", "."):
            block("recursive rm outside the project or on the project root")


def check_simple(text, sep, prev_prog, depth):
    if depth > 6:
        block("command nesting too deep to inspect")
    argv = argv_of(text)
    # leading environment assignments
    while argv and is_env_assignment(argv[0]):
        check_env(argv[0].split("=", 1)[0])
        argv = argv[1:]
    # wrappers
    while argv:
        prog = os.path.basename(argv[0])
        if prog in ("sudo", "doas", "su"):
            block("%s: privilege escalation" % prog)
        if prog in WRAPPERS:
            argv = argv[1:]
            while argv and (argv[0].startswith("-") or is_env_assignment(argv[0]) or (prog == "timeout" and argv[0][:1].isdigit())):
                if is_env_assignment(argv[0]):
                    check_env(argv[0].split("=", 1)[0])
                argv = argv[1:]
            continue
        break
    if not argv:
        return None
    prog = os.path.basename(argv[0])
    args = argv[1:]
    if prog in SHELLS:
        if sep == "|" and prev_prog in ("curl", "wget", "fetch"):
            block("piping a download into a shell")
        for k, a in enumerate(args):
            if a == "-c" or (a.startswith("-") and not a.startswith("--") and "c" in a and k + 1 < len(args)):
                inspect(args[k + 1], depth + 1)
                break
        else:
            if sep == "|":
                block("piping into a shell")
    elif prog == "eval":
        inspect(" ".join(args), depth + 1)
    elif prog == "git":
        check_git(args, depth)
    elif prog == "gh":
        check_gh(args)
    elif prog == "rm":
        check_rm(args)
    elif prog in ("python", "python3", "node", "ruby", "perl") and sep == "|" and prev_prog in ("curl", "wget"):
        block("piping a download into an interpreter")
    for t in args:
        if touches_secret_file(t):
            block("naming a secret file (%s)" % os.path.basename(t))
    return prog


def inspect(command, depth=0):
    simple, nested = split_commands(command)
    prev = None
    for sep, text in simple:
        prev = check_simple(text, sep, prev if sep == "|" else None, depth)
    for inner in nested:
        inspect(inner, depth + 1)


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except ValueError:
        print("Blocked in unattended mode: the guard could not read the tool input.", file=sys.stderr)
        return 2
    tool_input = payload.get("tool_input") if isinstance(payload, dict) else None
    command = tool_input.get("command", "") if isinstance(tool_input, dict) else ""
    if not command:
        return 0
    try:
        inspect(command)
    except Block as exc:
        print("Blocked in unattended mode: %s. Do not try to work around it; note it in the morning report "
              "if you need it." % exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
