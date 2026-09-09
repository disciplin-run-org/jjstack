#!/usr/bin/env python3
"""Drive hooks/permission-floor.py against the permission-policy fixtures.

The fixtures are DATA (test/fixtures/permission-policy.tsv). Each row is read,
wrapped as a PreToolUse payload and handed to the hook on stdin. Nothing is
ever executed and nothing is interpolated into a shell command, which is what
lets the table hold the real literals a guard must match.

Every row asserts the RULE, not just the verdict. A fork bomb refused because
it happens to contain a semicolon is a hole in FORKBOMB that a bare
allow/deny verdict reports as a pass.

Exit 0 = every row matched its expected rule, and both self-checks passed.
Exit 1 = at least one mismatch (printed).
Exit 2 = the table or a self-check is broken. A table that cannot fail is
         indistinguishable from one that is never run, so this is louder than
         a mismatch, not quieter.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOK = os.path.join(REPO, "hooks", "permission-floor.py")
FIXTURES = os.path.join(REPO, "test", "fixtures", "permission-policy.tsv")


def load_rows(path):
    rows = []
    for lineno, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            print("row %d is malformed (want 3 tab-separated fields)" % lineno)
            sys.exit(2)
        expect, rule, command = parts
        if expect not in ("allow", "deny"):
            print("row %d has an unknown expectation %r" % (lineno, expect))
            sys.exit(2)
        if (expect == "allow") != (rule == "-"):
            print("row %d: an allow row needs rule '-', a deny row needs a name" % lineno)
            sys.exit(2)
        # The table is newline-delimited, so a multi-line command cannot be
        # written literally. Without decoding, the entire "first line looks
        # benign, second line is destructive" class is structurally
        # unrepresentable — untestable rather than untested.
        command = command.replace("\\t", "\t").replace("\\n", "\n")
        rows.append((lineno, expect, rule, command))
    return rows


def ask(command):
    """Return (verdict, rule) for one command."""
    payload = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": REPO}
    env = dict(os.environ)
    env["JJSTACK_FLOOR_LOG"] = "/dev/null"
    proc = subprocess.run(
        [sys.executable, HOOK], input=json.dumps(payload),
        capture_output=True, text=True, env=env,
    )
    out = proc.stdout.strip()
    if not out:
        return "allow", "-"
    try:
        got = json.loads(out)["hookSpecificOutput"]
    except Exception:
        return "malformed", proc.stdout[:80]
    if got.get("permissionDecision") != "deny":
        return "malformed", json.dumps(got)[:80]
    return "deny", got.get("permissionDecisionReason", "").split(":", 1)[0]


def declared_rules():
    proc = subprocess.run(
        [sys.executable, HOOK, "--rules"], capture_output=True, text=True
    )
    return [r for r in proc.stdout.split("\n") if r.strip()]


def main():
    rows = load_rows(FIXTURES)
    if len(rows) < 20:
        print("only %d fixtures — the table is too thin to be meaningful" % len(rows))
        return 2

    # DERIVE, DON'T ENUMERATE. Ask the hook which rules it has rather than
    # keeping a second list here that drifts. A rule shipped without a fixture
    # is a rule nobody has ever seen fire.
    rules = declared_rules()
    if not rules:
        print("the hook declared no rules — --rules is broken")
        return 2
    covered = {rule for _, expect, rule, _ in rows if expect == "deny"}
    missing = [r for r in rules if r not in covered]
    if missing:
        print("rules with no fixture: %s" % ", ".join(missing))
        return 2

    # Anti-vacuity, both directions. A table of nothing but deny rows passes
    # against a hook that refuses everything, and a table of nothing but allow
    # rows passes against a hook that has been deleted.
    if not any(expect == "allow" for _, expect, _, _ in rows):
        print("no 'allow' fixtures — the table cannot detect a hook that refuses everything")
        return 2

    # Self-check BEFORE trusting any result: confirm the runner can observe
    # both verdicts on literals taken from the file, never invented here.
    probe_deny = next(r for r in rows if r[1] == "deny")
    if ask(probe_deny[3])[0] != "deny":
        print("SELF-CHECK FAILED: a floor case was allowed (line %d)" % probe_deny[0])
        return 2
    probe_allow = next(r for r in rows if r[1] == "allow")
    if ask(probe_allow[3])[0] != "allow":
        print("SELF-CHECK FAILED: an ordinary command was refused (line %d)" % probe_allow[0])
        return 2

    mismatches = []
    for lineno, expect, rule, command in rows:
        verdict, got_rule = ask(command)
        if verdict != expect or (expect == "deny" and got_rule != rule):
            mismatches.append(
                "  line %d: expected %s/%s, got %s/%s :: %s"
                % (lineno, expect, rule, verdict, got_rule, command.replace("\n", "\\n"))
            )

    print("CASES=%d RULES=%d" % (len(rows), len(rules)))
    for m in mismatches:
        print("MISMATCH")
        print(m)
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
