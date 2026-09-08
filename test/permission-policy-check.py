#!/usr/bin/env python3
"""Drive hooks/auto-approve-safe.sh against the permission-policy fixtures.

The fixtures are DATA (test/fixtures/permission-policy.tsv). Each row is read,
wrapped as a hook payload, and handed to the hook on stdin. Nothing is ever
executed and nothing is interpolated into a shell command — which is what lets
the table hold the real literals a guard must match. A guard proved against
invented strings only proves it matches the string you invented.

The risk rating is FORCED, so what is under test is the policy, not the
model's opinion of any particular command.

Exit 0 = every row matched its expected verdict, and the self-check passed.
Exit 1 = at least one mismatch (printed).
Exit 2 = the table or the self-check is broken (a table that cannot fail is
         indistinguishable from one that is never run).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOK = os.path.join(REPO, "hooks", "auto-approve-safe.sh")
FIXTURES = os.path.join(REPO, "test", "fixtures", "permission-policy.tsv")


def load_rows(path):
    rows = []
    for lineno, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) == 3:
            parts.append("LOW")
        if len(parts) != 4:
            print("row %d is malformed (want 3 or 4 tab-separated fields)" % lineno)
            sys.exit(2)
        expect, command, purpose, force = parts
        # The forced rating says WHICH path the row is testing, and it matters.
        # LOW  — the rater would approve, so only the deterministic FLOOR can
        #        refuse. Proves the floor beats a permissive rating.
        # HIGH — the rater would refuse, so only the deterministic ALLOWLIST
        #        can approve. Proves the allowlist is not a bypass.
        # A row tested at the wrong rating passes for the wrong reason: the
        # allowlist-bypass rows all "passed" at LOW simply by reaching the
        # rater, which is exactly the mistake this column exists to prevent.
        if force not in ("LOW", "HIGH"):
            print("row %d has an unknown forced rating %r" % (lineno, force))
            sys.exit(2)
        # The table is newline-delimited, so a multi-line command cannot be
        # written literally. Without decoding, the entire "first line looks
        # benign, second line is destructive" bypass class is structurally
        # unrepresentable — untestable rather than untested.
        command = command.replace("\\t", "\t").replace("\\n", "\n")
        if expect not in ("allow", "defer"):
            print("row %d has an unknown expectation %r" % (lineno, expect))
            sys.exit(2)
        rows.append((lineno, expect, command, purpose, force))
    return rows


def ask(command, purpose, force="LOW"):
    """Return 'allow' or 'defer' for one command, at a forced risk rating."""
    tool_input = {"command": command}
    if purpose != "-":
        tool_input["description"] = purpose
    payload = {
        "tool_name": "Bash",
        "tool_input": tool_input,
        "cwd": REPO,
    }
    env = dict(os.environ)
    env["JJSTACK_HOOK_LOG"] = "/dev/null"
    env["JJSTACK_HOOK_FORCE_RISK"] = force
    proc = subprocess.run(
        ["bash", HOOK], input=json.dumps(payload),
        capture_output=True, text=True, env=env,
    )
    out = proc.stdout
    return "allow" if '"behavior"' in out and "allow" in out else "defer"


def main():
    rows = load_rows(FIXTURES)
    if len(rows) < 20:
        print("only %d fixtures — the table is too thin to be meaningful" % len(rows))
        return 2

    # Self-check BEFORE trusting any result: take a row the floor must refuse
    # and confirm the runner reports it as refused. If this cannot fail, every
    # pass below is meaningless. The literal comes from the fixture file, never
    # from a string invented here.
    floor = [r for r in rows if r[1] == "defer"]
    if not floor:
        print("no 'defer' fixtures — the table cannot detect a broken floor")
        return 2
    if ask(floor[0][2], floor[0][3], floor[0][4]) != "defer":
        print("SELF-CHECK FAILED: a floor case was allowed at a forced LOW rating")
        return 2

    mismatches = []
    for lineno, expect, command, purpose, force in rows:
        got = ask(command, purpose, force)
        if got != expect:
            mismatches.append(
                "  line %d: expected %s, got %s :: %s" % (lineno, expect, got, command)
            )

    print("CASES=%d" % len(rows))
    for m in mismatches:
        print("MISMATCH")
        print(m)
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
